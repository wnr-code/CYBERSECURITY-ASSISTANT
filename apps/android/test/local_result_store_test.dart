import 'dart:io';

import 'package:cybersecurity_assistant/core/activity_timeline.dart';
import 'package:cybersecurity_assistant/core/local_result_store.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:cybersecurity_assistant/core/tool_result_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  ToolRunResult result(String target, {bool authorizationConfirmed = true}) => ToolRunResult(
        toolId: 'dns_lookup',
        target: target,
        summary: 'Resolved one address.',
        details: const ['192.0.2.1'],
        findings: const [],
        completedAt: DateTime.utc(2026, 11, 23),
        authorizationConfirmed: authorizationConfirmed,
      );

  LocalResultStore createStore({int maxRecords = 500}) => LocalResultStore(
        databaseFactory: databaseFactoryFfi,
        databasePathProvider: () async => inMemoryDatabasePath,
        maxRecords: maxRecords,
      );

  test('persists and reloads completed results and the consent marker', () async {
    final store = createStore();
    addTearDown(store.close);

    await store.save(result('example.com'));
    final loaded = await store.loadRecent();

    expect(loaded, hasLength(1));
    expect(loaded.single.target, 'example.com');
    expect(loaded.single.details, ['192.0.2.1']);
    expect(loaded.single.authorizationConfirmed, isTrue);
  });

  test('file-backed SQLite history survives closing and reopening the store', () async {
    final directory = await Directory.systemTemp.createTemp('cybersecurity-assistant-history-');
    final databasePath = p.join(directory.path, 'history.sqlite');
    final firstStore = LocalResultStore(
      databaseFactory: databaseFactoryFfi,
      databasePathProvider: () async => databasePath,
    );

    await firstStore.save(result('restart-persist.example'));
    await firstStore.close();

    final reopenedStore = LocalResultStore(
      databaseFactory: databaseFactoryFfi,
      databasePathProvider: () async => databasePath,
    );
    addTearDown(() async {
      await reopenedStore.close();
      await directory.delete(recursive: true);
    });

    final loaded = await reopenedStore.loadRecent();
    expect(loaded, hasLength(1));
    expect(loaded.single.target, 'restart-persist.example');
  });

  test('re-saving the same check does not create a duplicate record', () async {
    final store = createStore();
    addTearDown(store.close);
    final saved = result('example.com');

    await store.save(saved);
    await store.save(saved);

    expect(await store.loadRecent(), hasLength(1));
  });

  test('limits recent history and clear removes stored results', () async {
    final store = createStore(maxRecords: 2);
    addTearDown(store.close);

    await store.save(result('one.example'));
    await store.save(result('two.example'));
    await store.save(result('three.example'));

    expect((await store.loadRecent()).map((entry) => entry.target), ['three.example', 'two.example']);
    await store.clear();
    expect(await store.loadRecent(), isEmpty);
  });

  test('activity timeline persists across store reopen, deduplicates updates and supports filters', () async {
    final directory = await Directory.systemTemp.createTemp('cybersecurity-activity-');
    final databasePath = p.join(directory.path, 'history.sqlite');
    final firstStore = LocalResultStore(
      databaseFactory: databaseFactoryFfi,
      databasePathProvider: () async => databasePath,
    );
    final startedAt = DateTime.utc(2026, 11, 23, 12);
    final started = ActivityEvent(
      eventId: 'tool-persisted-1',
      kind: ActivityKind.tool,
      toolId: 'tls_inspector',
      target: 'persisted.example',
      status: ActivityStatus.started,
      startedAt: startedAt,
    );

    await firstStore.upsertActivity(started);
    await firstStore.upsertActivity(started.copyWith(status: ActivityStatus.running));
    await firstStore.upsertActivity(started.copyWith(
      status: ActivityStatus.completed,
      finishedAt: startedAt.add(const Duration(seconds: 4)),
      summary: 'TLS completed.',
      findingCount: 1,
      sourceResultKey: activityResultKey('tls_inspector', 'persisted.example', startedAt.add(const Duration(seconds: 4))),
    ));
    await firstStore.close();

    final reopenedStore = LocalResultStore(
      databaseFactory: databaseFactoryFfi,
      databasePathProvider: () async => databasePath,
    );
    addTearDown(() async {
      await reopenedStore.close();
      await directory.delete(recursive: true);
    });

    final loaded = await reopenedStore.loadActivities(
      target: 'persisted',
      kind: ActivityKind.tool,
      toolId: 'tls_inspector',
      status: ActivityStatus.completed,
    );
    expect(loaded, hasLength(1));
    expect(loaded.single.status, ActivityStatus.completed);
    expect(loaded.single.startedAt, startedAt);
    expect(loaded.single.finishedAt, startedAt.add(const Duration(seconds: 4)));
    expect(loaded.single.findingCount, 1);
    expect(loaded.single.summary, 'TLS completed.');
  });

  test('version one database migrates without losing saved reports', () async {
    final directory = await Directory.systemTemp.createTemp('cybersecurity-v1-migration-');
    final databasePath = p.join(directory.path, 'legacy.sqlite');
    final legacyResult = result('legacy.example');
    final legacyDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE scan_results (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              result_key TEXT NOT NULL UNIQUE,
              tool_id TEXT NOT NULL,
              target TEXT NOT NULL,
              completed_at TEXT NOT NULL,
              authorization_confirmed INTEGER NOT NULL,
              payload_json TEXT NOT NULL
            )
          ''');
          await db.execute('CREATE INDEX scan_results_completed_at ON scan_results(completed_at)');
          await db.insert('scan_results', {
            'result_key': 'dns_lookup|legacy.example|${legacyResult.completedAt.toUtc().microsecondsSinceEpoch}',
            'tool_id': legacyResult.toolId,
            'target': legacyResult.target,
            'completed_at': legacyResult.completedAt.toUtc().toIso8601String(),
            'authorization_confirmed': 1,
            'payload_json': encodeToolRunResult(legacyResult),
          });
        },
      ),
    );
    await legacyDatabase.close();

    final upgradedStore = LocalResultStore(
      databaseFactory: databaseFactoryFfi,
      databasePathProvider: () async => databasePath,
    );
    addTearDown(() async {
      await upgradedStore.close();
      await directory.delete(recursive: true);
    });

    final preserved = await upgradedStore.loadRecent();
    expect(preserved, hasLength(1));
    expect(preserved.single.target, 'legacy.example');
    expect(await upgradedStore.loadActivities(), isEmpty);
    await upgradedStore.upsertActivity(ActivityEvent(
      eventId: 'after-migration',
      kind: ActivityKind.tool,
      toolId: 'dns_lookup',
      target: 'legacy.example',
      status: ActivityStatus.completed,
      startedAt: DateTime.utc(2026, 11, 24),
      finishedAt: DateTime.utc(2026, 11, 24, 0, 0, 2),
      summary: 'Resolved one address.',
      findingCount: 0,
    ));
    expect(await upgradedStore.loadActivities(), hasLength(1));
    expect((await upgradedStore.loadRecent()).single.target, 'legacy.example');
  });

  test('refuses derived analyzer results', () async {
    final store = createStore();
    addTearDown(store.close);
    final analyzer = SecurityTools().analyze([result('example.com')], target: 'example.com');

    await expectLater(store.save(analyzer), throwsArgumentError);
  });
}
