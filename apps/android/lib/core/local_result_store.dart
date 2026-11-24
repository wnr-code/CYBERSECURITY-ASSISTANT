import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'activity_timeline.dart';
import 'security_tools.dart';
import 'tool_result_codec.dart';

abstract interface class ResultHistoryStore {
  Future<int> save(ToolRunResult result);
  Future<List<ToolRunResult>> loadRecent({int limit = 30});
  Future<void> clear();
  Future<void> close();
}

/// SQLite-backed local history for explicitly saved, completed tool checks.
/// This stores no provider API keys and never syncs data to a remote service.
class LocalResultStore implements ResultHistoryStore, ActivityHistoryStore {
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
  static const _databaseVersion = 2;
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
      default:
        throw StateError('No safe SQLite migration is registered for schema version $version.');
    }
  }

  @override
  Future<int> save(ToolRunResult result) async {
    if (result.toolId == 'response_analyzer') {
      throw ArgumentError.value(result.toolId, 'result.toolId', 'Derived analyzer summaries are not stored.');
    }
    if (maxRecords < 1) throw StateError('maxRecords must be at least 1.');
    final db = await _open();
    return db.transaction((transaction) async {
      final id = await transaction.insert(tableName, {
        'result_key': '${result.toolId}|${result.target}|${result.completedAt.toUtc().microsecondsSinceEpoch}',
        'tool_id': result.toolId,
        'target': result.target,
        'completed_at': result.completedAt.toUtc().toIso8601String(),
        'authorization_confirmed': result.authorizationConfirmed ? 1 : 0,
        'payload_json': encodeToolRunResult(result),
      }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
      await transaction.rawDelete(
        'DELETE FROM $tableName WHERE id NOT IN (SELECT id FROM $tableName ORDER BY id DESC LIMIT ?)',
        [maxRecords],
      );
      return id;
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
    await db.rawDelete(
      'DELETE FROM $activityTableName WHERE event_id NOT IN (SELECT event_id FROM $activityTableName ORDER BY started_at DESC LIMIT ?)',
      [500],
    );
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
    return List.unmodifiable([
      for (final row in rows)
        ActivityEvent(
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
        ).validated(),
    ]);
  }

  @override
  Future<void> clearActivities() async {
    final db = await _open();
    await db.delete(activityTableName);
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
