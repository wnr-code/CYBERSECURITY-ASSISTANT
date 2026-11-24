import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'activity_timeline.dart';
import 'security_findings.dart';
import 'security_tools.dart';
import 'tool_result_codec.dart';

abstract interface class ResultHistoryStore {
  Future<int> save(ToolRunResult result, {String? assessmentId});
  Future<List<ToolRunResult>> loadRecent({int limit = 30});
  Future<ToolRunResult?> loadReportById(String reportId);
  Future<void> clear();
  Future<void> close();
}

/// SQLite-backed local history for explicitly saved, completed tool checks.
/// This stores no provider API keys and never syncs data to a remote service.
class LocalResultStore implements ResultHistoryStore, ActivityHistoryStore, FindingRepository {
  LocalResultStore({
    sqflite.DatabaseFactory? databaseFactory,
    Future<String> Function()? databasePathProvider,
    this.maxRecords = 500,
  })  : _databaseFactoryOverride = databaseFactory,
        _databasePathProvider = databasePathProvider ?? _defaultDatabasePath {
    if (maxRecords < 1) throw ArgumentError.value(maxRecords, 'maxRecords', 'Must be at least 1.');
  }

  static const tableName = 'scan_results';
  static const activityTableName = 'activity_events';
  static const findingTableName = 'security_findings';
  static const _databaseVersion = 4;
  final sqflite.DatabaseFactory? _databaseFactoryOverride;
  sqflite.DatabaseFactory get _databaseFactory => _databaseFactoryOverride ?? sqflite.databaseFactory;
  final Future<String> Function() _databasePathProvider;
  final int maxRecords;
  sqflite.Database? _database;
  Future<sqflite.Database>? _opening;

  static Future<String> _defaultDatabasePath() async =>
      p.join(await sqflite.getDatabasesPath(), 'cybersecurity_assistant.db');

  Future<sqflite.Database> _open() async {
    final opened = _database;
    if (opened != null && opened.isOpen) return opened;
    final pending = _opening;
    if (pending != null) return pending;

    final future = _createDatabase();
    _opening = future;
    try {
      final db = await future;
      _database = db;
      return db;
    } finally {
      _opening = null;
    }
  }

  Future<sqflite.Database> _createDatabase() async {
    final path = await _databasePathProvider();
    return _databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: (db, version) async {
          await _migrate(db, 1);
          await _migrate(db, 2);
          await _migrate(db, 3);
          await _migrate(db, 4);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          for (var version = oldVersion + 1; version <= newVersion; version++) {
            await _migrate(db, version);
          }
        },
      ),
    );
  }

  Future<void> _migrate(sqflite.Database db, int version) async {
    switch (version) {
      case 1:
        await db.execute('''
          CREATE TABLE $tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            result_key TEXT NOT NULL UNIQUE,
            tool_id TEXT NOT NULL,
            target TEXT NOT NULL,
            completed_at TEXT NOT NULL,
            authorization_confirmed INTEGER NOT NULL,
            payload_json TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX scan_results_completed_at ON $tableName(completed_at)');
      case 2:
        await db.execute('''
          CREATE TABLE $activityTableName (
            event_id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            parent_event_id TEXT,
            tool_id TEXT,
            target TEXT NOT NULL,
            status TEXT NOT NULL,
            started_at TEXT NOT NULL,
            finished_at TEXT,
            summary TEXT,
            finding_count INTEGER,
            source_result_key TEXT
          )
        ''');
        await db.execute('CREATE INDEX activity_events_started_at ON $activityTableName(started_at DESC)');
        await db.execute('CREATE INDEX activity_events_target ON $activityTableName(target)');
        await db.execute('CREATE INDEX activity_events_status ON $activityTableName(status)');
      case 3:
        await db.execute('''
          CREATE TABLE $findingTableName (
            finding_id TEXT PRIMARY KEY,
            fingerprint TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            target TEXT NOT NULL,
            severity TEXT NOT NULL,
            confidence TEXT NOT NULL,
            status TEXT NOT NULL,
            description TEXT NOT NULL,
            evidence_json TEXT NOT NULL,
            source_report_keys_json TEXT NOT NULL,
            recommendation TEXT NOT NULL,
            first_seen TEXT NOT NULL,
            last_seen TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            source_tool TEXT,
            assessment_id TEXT
          )
        ''');
        await db.execute('CREATE INDEX security_findings_last_seen ON $findingTableName(last_seen DESC)');
        await db.execute('CREATE INDEX security_findings_target ON $findingTableName(target)');
        await db.execute('CREATE INDEX security_findings_severity ON $findingTableName(severity)');
        await db.execute('CREATE INDEX security_findings_status ON $findingTableName(status)');
        await db.execute('CREATE INDEX security_findings_category ON $findingTableName(category)');
      case 4:
        await db.execute('ALTER TABLE $tableName ADD COLUMN assessment_id TEXT');
        final existingReports = await db.query(tableName, columns: ['id', 'result_key', 'tool_id', 'target', 'completed_at']);
        final migratedIds = <String, String>{};
        for (final row in existingReports) {
          final completedAt = DateTime.tryParse(row['completed_at'] as String? ?? '');
          final toolId = row['tool_id'];
          final target = row['target'];
          final legacyId = row['result_key'];
          if (completedAt == null || toolId is! String || target is! String || legacyId is! String) continue;
          final stableReportId = activityResultKey(toolId, target, completedAt);
          await db.update(tableName, {'result_key': stableReportId}, where: 'id = ?', whereArgs: [row['id']]);
          migratedIds[legacyId] = stableReportId;
        }
        for (final entry in migratedIds.entries) {
          await db.update(activityTableName, {'source_result_key': entry.value},
              where: 'source_result_key = ?', whereArgs: [entry.key]);
        }
        final findingRows = await db.query(findingTableName, columns: ['finding_id', 'source_report_keys_json']);
        for (final finding in findingRows) {
          final findingId = finding['finding_id'];
          final rawKeys = finding['source_report_keys_json'];
          if (findingId is! String || rawKeys is! String) continue;
          try {
            final decoded = jsonDecode(rawKeys);
            if (decoded is! List) continue;
            final updated = decoded.map((key) => key is String ? migratedIds[key] ?? key : key).toList();
            if (updated.toString() != decoded.toString()) {
              await db.update(findingTableName, {'source_report_keys_json': jsonEncode(updated)},
                  where: 'finding_id = ?', whereArgs: [findingId]);
            }
          } on FormatException {
            // Preserve malformed legacy metadata rather than risking data loss during upgrade.
          }
        }
      default:
        throw StateError('No safe SQLite migration is registered for schema version $version.');
    }
  }

  @override
  Future<int> save(ToolRunResult result, {String? assessmentId}) async {
    if (result.toolId == 'response_analyzer') {
      throw ArgumentError.value(result.toolId, 'result.toolId', 'Derived analyzer summaries are not stored.');
    }
    if (maxRecords < 1) throw StateError('maxRecords must be at least 1.');
    final db = await _open();
    final persistedResult = assessmentId == null ? result : result.copyWith(assessmentId: assessmentId);
    final reportId = activityResultKey(persistedResult.toolId, persistedResult.target, persistedResult.completedAt);
    return db.transaction((transaction) async {
      await transaction.insert(tableName, {
        'result_key': reportId,
        'tool_id': persistedResult.toolId,
        'target': persistedResult.target,
        'completed_at': persistedResult.completedAt.toUtc().toIso8601String(),
        'authorization_confirmed': persistedResult.authorizationConfirmed ? 1 : 0,
        'payload_json': encodeToolRunResult(persistedResult),
        'assessment_id': persistedResult.assessmentId,
      }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
      if (persistedResult.assessmentId != null) {
        await transaction.rawUpdate(
          'UPDATE $tableName SET assessment_id = COALESCE(assessment_id, ?), payload_json = CASE WHEN assessment_id IS NULL THEN ? ELSE payload_json END WHERE result_key = ?',
          [persistedResult.assessmentId, encodeToolRunResult(persistedResult), reportId],
        );
      }
      final rows = await transaction.query(tableName, columns: ['id'], where: 'result_key = ?', whereArgs: [reportId], limit: 1);
      if (rows.isEmpty) throw StateError('Saved report was not readable after its transaction.');
      return rows.single['id'] as int;
    });
  }

  @override
  Future<List<ToolRunResult>> loadRecent({int limit = 30}) async {
    final safeLimit = limit < 1 ? 1 : limit > maxRecords ? maxRecords : limit;
    final db = await _open();
    final rows = await db.query(tableName, orderBy: 'id DESC', limit: safeLimit);
    return [
      for (final row in rows) decodeToolRunResult(row['payload_json'] as String),
    ];
  }

  @override
  Future<ToolRunResult?> loadReportById(String reportId) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(reportId)) return null;
    final db = await _open();
    final rows = await db.query(tableName, where: 'result_key = ?', whereArgs: [reportId], limit: 1);
    if (rows.isEmpty) return null;
    return decodeToolRunResult(rows.single['payload_json'] as String);
  }

  @override
  Future<void> clear() async {
    final db = await _open();
    await db.delete(tableName);
  }

  @override
  Future<void> upsertActivity(ActivityEvent event) async {
    final validated = event.sanitizedForStorage().validated();
    final db = await _open();
    await db.insert(
      activityTableName,
      {
        'event_id': validated.eventId,
        'kind': validated.kind.name,
        'parent_event_id': validated.parentEventId,
        'tool_id': validated.toolId,
        'target': validated.target,
        'status': validated.status.name,
        'started_at': activityTimestamp(validated.startedAt),
        'finished_at': validated.finishedAt == null ? null : activityTimestamp(validated.finishedAt!),
        'summary': validated.summary,
        'finding_count': validated.findingCount,
        'source_result_key': validated.sourceResultKey,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  @override
  Future<ActivityEvent?> loadActivityById(String eventId) async {
    final db = await _open();
    final rows = await db.query(activityTableName, where: 'event_id = ?', whereArgs: [eventId], limit: 1);
    if (rows.isEmpty) return null;
    return _activityFromRow(rows.single);
  }

  @override
  Future<List<ActivityEvent>> loadActivities({
    int limit = 500,
    DateTime? from,
    DateTime? to,
    String? target,
    ActivityKind? kind,
    String? toolId,
    ActivityStatus? status,
  }) async {
    final safeLimit = limit.clamp(1, 500).toInt();
    final clauses = <String>[];
    final args = <Object?>[];
    if (from != null) {
      clauses.add('started_at >= ?');
      args.add(activityTimestamp(from));
    }
    if (to != null) {
      clauses.add('started_at <= ?');
      args.add(activityTimestamp(to));
    }
    final normalizedTarget = target?.trim();
    if (normalizedTarget != null && normalizedTarget.isNotEmpty) {
      clauses.add('target LIKE ? COLLATE NOCASE');
      args.add('%$normalizedTarget%');
    }
    if (kind != null) {
      clauses.add('kind = ?');
      args.add(kind.name);
    }
    if (toolId != null && toolId.isNotEmpty) {
      clauses.add('tool_id = ?');
      args.add(toolId);
    }
    if (status != null) {
      clauses.add('status = ?');
      args.add(status.name);
    }
    final db = await _open();
    final rows = await db.query(
      activityTableName,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'started_at DESC, event_id ASC',
      limit: safeLimit,
    );
    return List.unmodifiable(rows.map(_activityFromRow));
  }

  ActivityEvent _activityFromRow(Map<String, Object?> row) => ActivityEvent(
        eventId: row['event_id'] as String,
        kind: ActivityKind.values.byName(row['kind'] as String),
        parentEventId: row['parent_event_id'] as String?,
        toolId: row['tool_id'] as String?,
        target: row['target'] as String,
        status: ActivityStatus.values.byName(row['status'] as String),
        startedAt: DateTime.parse(row['started_at'] as String).toUtc(),
        finishedAt: row['finished_at'] == null ? null : DateTime.parse(row['finished_at'] as String).toUtc(),
        summary: row['summary'] as String?,
        findingCount: row['finding_count'] as int?,
        sourceResultKey: row['source_result_key'] as String?,
      ).validated();

  @override
  Future<void> clearActivities() async {
    final db = await _open();
    await db.delete(activityTableName);
  }

  @override
  Future<List<FindingRecord>> loadFindings({
    int limit = 500,
    FindingSeverity? severity,
    FindingStatus? status,
    String? category,
    String? target,
    String? query,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (severity != null) {
      clauses.add('severity = ?');
      args.add(severity.name);
    }
    if (status != null) {
      clauses.add('status = ?');
      args.add(status.name);
    }
    final normalizedCategory = category?.trim();
    if (normalizedCategory != null && normalizedCategory.isNotEmpty) {
      clauses.add('category LIKE ? COLLATE NOCASE');
      args.add('%$normalizedCategory%');
    }
    final normalizedTarget = target?.trim();
    if (normalizedTarget != null && normalizedTarget.isNotEmpty) {
      clauses.add('target LIKE ? COLLATE NOCASE');
      args.add('%$normalizedTarget%');
    }
    final normalizedQuery = query?.trim();
    if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
      clauses.add('(title LIKE ? COLLATE NOCASE OR category LIKE ? COLLATE NOCASE OR target LIKE ? COLLATE NOCASE OR description LIKE ? COLLATE NOCASE OR recommendation LIKE ? COLLATE NOCASE OR evidence_json LIKE ? COLLATE NOCASE)');
      args.addAll(List<Object?>.filled(6, '%$normalizedQuery%'));
    }
    final db = await _open();
    final rows = await db.query(
      findingTableName,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'last_seen DESC, finding_id ASC',
      limit: limit.clamp(1, 5000).toInt(),
    );
    return List.unmodifiable(rows.map(_findingFromRow));
  }

  @override
  Future<List<FindingRecord>> saveObservedFindings(Iterable<FindingRecord> findings) async {
    final candidates = findings.map((finding) => finding.sanitized().validated()).toList(growable: false);
    if (candidates.isEmpty) return const [];
    final db = await _open();
    return db.transaction((transaction) async {
      final saved = <FindingRecord>[];
      for (final incoming in candidates) {
        final existingRows = await transaction.query(
          findingTableName,
          where: 'fingerprint = ?',
          whereArgs: [incoming.fingerprint],
          limit: 1,
        );
        final existing = existingRows.isEmpty ? null : _findingFromRow(existingRows.single);
        final merged = existing == null
            ? incoming
            : existing.copyWith(
                lastSeen: incoming.lastSeen.isAfter(existing.lastSeen) ? incoming.lastSeen : existing.lastSeen,
                updatedAt: incoming.updatedAt.isAfter(existing.updatedAt) ? incoming.updatedAt : existing.updatedAt,
                sourceReportKeys: {...existing.sourceReportKeys, ...incoming.sourceReportKeys}.take(50).toList(),
                sourceTool: incoming.sourceTool ?? existing.sourceTool,
                assessmentId: incoming.assessmentId ?? existing.assessmentId,
                title: incoming.title,
                category: incoming.category,
                target: incoming.target,
                severity: incoming.severity,
                confidence: incoming.confidence,
                description: incoming.description,
                evidence: incoming.evidence,
                recommendation: incoming.recommendation,
              ).validated();
        final values = _findingValues(merged);
        if (existing == null) {
          await transaction.insert(findingTableName, values);
        } else {
          await transaction.update(findingTableName, values, where: 'finding_id = ?', whereArgs: [existing.findingId]);
        }
        saved.add(merged);
      }
      return List.unmodifiable(saved);
    });
  }

  @override
  Future<FindingRecord> updateFindingStatus(String findingId, FindingStatus status) async {
    final db = await _open();
    return db.transaction((transaction) async {
      final rows = await transaction.query(findingTableName, where: 'finding_id = ?', whereArgs: [findingId], limit: 1);
      if (rows.isEmpty) throw StateError('Finding was not found.');
      final current = _findingFromRow(rows.single);
      final updated = current.copyWith(status: status, updatedAt: DateTime.now().toUtc()).validated();
      await transaction.update(findingTableName, _findingValues(updated), where: 'finding_id = ?', whereArgs: [findingId]);
      return updated;
    });
  }

  @override
  Future<void> clearFindings() async {
    final db = await _open();
    await db.delete(findingTableName);
  }

  Map<String, Object?> _findingValues(FindingRecord finding) => {
        'finding_id': finding.findingId,
        'fingerprint': finding.fingerprint,
        'title': finding.title,
        'category': finding.category,
        'target': finding.target,
        'severity': finding.severity.name,
        'confidence': finding.confidence.name,
        'status': finding.status.name,
        'description': finding.description,
        'evidence_json': jsonEncode(finding.evidence),
        'source_report_keys_json': jsonEncode(finding.sourceReportKeys),
        'recommendation': finding.recommendation,
        'first_seen': activityTimestamp(finding.firstSeen),
        'last_seen': activityTimestamp(finding.lastSeen),
        'created_at': activityTimestamp(finding.createdAt),
        'updated_at': activityTimestamp(finding.updatedAt),
        'source_tool': finding.sourceTool,
        'assessment_id': finding.assessmentId,
      };

  FindingRecord _findingFromRow(Map<String, Object?> row) {
    List<String> decodeStringList(String key) {
      final value = jsonDecode(row[key] as String);
      if (value is! List || value.any((entry) => entry is! String)) {
        throw FormatException('Stored finding field "$key" is invalid.');
      }
      return value.cast<String>();
    }

    return FindingRecord(
      findingId: row['finding_id'] as String,
      fingerprint: row['fingerprint'] as String,
      title: row['title'] as String,
      category: row['category'] as String,
      target: row['target'] as String,
      severity: FindingSeverity.values.byName(row['severity'] as String),
      confidence: FindingConfidence.values.byName(row['confidence'] as String),
      status: FindingStatus.values.byName(row['status'] as String),
      description: row['description'] as String,
      evidence: decodeStringList('evidence_json'),
      sourceReportKeys: decodeStringList('source_report_keys_json'),
      recommendation: row['recommendation'] as String,
      firstSeen: DateTime.parse(row['first_seen'] as String).toUtc(),
      lastSeen: DateTime.parse(row['last_seen'] as String).toUtc(),
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
      sourceTool: row['source_tool'] as String?,
      assessmentId: row['assessment_id'] as String?,
    ).validated();
  }

  @override
  Future<void> close() async {
    final pending = _opening;
    if (pending != null) await pending;
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }
}
