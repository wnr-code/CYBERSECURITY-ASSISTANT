import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

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
class LocalResultStore implements ResultHistoryStore {
  LocalResultStore({
    sqflite.DatabaseFactory? databaseFactory,
    Future<String> Function()? databasePathProvider,
    this.maxRecords = 500,
  })  : _databaseFactoryOverride = databaseFactory,
        _databasePathProvider = databasePathProvider ?? _defaultDatabasePath {
    if (maxRecords < 1) throw ArgumentError.value(maxRecords, 'maxRecords', 'Must be at least 1.');
  }

  static const tableName = 'scan_results';
  static const _databaseVersion = 1;
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
        onCreate: (db, version) => _migrate(db, 1),
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
  Future<void> close() async {
    final pending = _opening;
    if (pending != null) await pending;
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }
}
