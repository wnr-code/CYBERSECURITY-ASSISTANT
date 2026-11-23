import 'dart:io';

import 'package:cybersecurity_assistant/core/local_result_store.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
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

  test('refuses derived analyzer results', () async {
    final store = createStore();
    addTearDown(store.close);
    final analyzer = SecurityTools().analyze([result('example.com')], target: 'example.com');

    await expectLater(store.save(analyzer), throwsArgumentError);
  });
}
