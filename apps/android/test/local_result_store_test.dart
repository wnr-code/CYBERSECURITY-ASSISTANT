import 'dart:convert';
import 'dart:io';

import 'package:cybersecurity_assistant/core/activity_timeline.dart';
import 'package:cybersecurity_assistant/core/local_result_store.dart';
import 'package:cybersecurity_assistant/core/security_findings.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:cybersecurity_assistant/core/tool_result_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

FindingRecord _testFindingRecord(DateTime observedAt, {required String sourceKey, String? assessmentId}) =>
    findingRecordFromTool(
      finding: const SecurityFinding(
        title: 'HSTS header not observed',
        severity: FindingSeverity.low,
        category: 'HTTP Security Headers',
        description: 'The response did not include HSTS.',
        evidence: ['strict-transport-security was not observed.'],
        riskIdentity: 'missing-hsts',
        recommendation: 'Review the header configuration.',
      ),
      result: ToolRunResult(
        toolId: 'http_headers',
        target: 'https://findings.example/path?token=private',
        summary: 'Fixture completed.',
        details: const [],
        findings: const [],
        completedAt: observedAt,
      ),
      sourceReportKey: sourceKey,
      assessmentId: assessmentId,
    );

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

  test('re-saving the same check does not create a duplicate and retains assessment linkage', () async {
    final store = createStore();
    addTearDown(store.close);
    final saved = result('example.com');

    await store.save(saved);
    final id = activityResultKey(saved.toolId, saved.target, saved.completedAt);
    await store.save(saved, assessmentId: 'assessment-event-1');
    await store.save(saved, assessmentId: 'assessment-event-2');

    expect(await store.loadRecent(), hasLength(1));
    expect((await store.loadReportById(id))?.assessmentId, 'assessment-event-1');
    expect(await store.loadReportById('not-a-report-id'), isNull);
  });

  test('keeps older reports when recent results are capped and clears only on explicit request', () async {
    final directory = await Directory.systemTemp.createTemp('cybersecurity-report-retention-');
    final databasePath = p.join(directory.path, 'history.sqlite');
    final firstStore = LocalResultStore(
      databaseFactory: databaseFactoryFfi,
      databasePathProvider: () async => databasePath,
      maxRecords: 2,
    );
    await firstStore.save(result('one.example'));
    await firstStore.save(result('two.example'));
    await firstStore.save(result('three.example'));
    expect((await firstStore.loadRecent()).map((entry) => entry.target), ['three.example', 'two.example']);
    await firstStore.close();

    final reopenedStore = LocalResultStore(
      databaseFactory: databaseFactoryFfi,
      databasePathProvider: () async => databasePath,
      maxRecords: 10,
    );
    addTearDown(() async {
      await reopenedStore.close();
      await directory.delete(recursive: true);
    });
    expect((await reopenedStore.loadRecent(limit: 10)).map((entry) => entry.target), ['three.example', 'two.example', 'one.example']);
    await reopenedStore.clear();
    expect(await reopenedStore.loadRecent(), isEmpty);
  });

  test('activity timeline persists across store reopen, deduplicates updates and supports filters', () async {
    final directory = await Directory.systemTemp.createTemp('cybersecurity-activity-');
    final databasePath = p.join(directory.path, 'history.sqlite');
    final firstStore = LocalResultStore(
      databaseFactory: databaseFactoryFfi,
      databasePathProvider: () async => databasePath,
    );
    final startedAt = DateTime.utc(2026, 11, 23, 12);
    final aiRequest = ActivityEvent(
      eventId: 'ai-persisted-1',
      kind: ActivityKind.aiRequest,
      target: 'gemini',
      status: ActivityStatus.completed,
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(seconds: 5)),
      summary: 'Assistant request completed.',
    );
    final started = ActivityEvent(
      eventId: 'tool-persisted-1',
      kind: ActivityKind.tool,
      parentEventId: 'ai-persisted-1',
      toolId: 'tls_inspector',
      target: 'persisted.example',
      status: ActivityStatus.started,
      startedAt: startedAt,
    );

    await firstStore.upsertActivity(aiRequest);
    await firstStore.upsertActivity(started);
    await firstStore.upsertActivity(started.copyWith(status: ActivityStatus.running));
    await firstStore.upsertActivity(started.copyWith(
      status: ActivityStatus.completed,
      finishedAt: startedAt.add(const Duration(seconds: 4)),
      summary: 'TLS completed.',
      findingCount: 1,
      sourceResultKey: activityResultKey('tls_inspector', 'persisted.example', startedAt.add(const Duration(seconds: 4))),
      runtimeExecutionId: 'runtime-execution-42',
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
    expect(loaded.single.runtimeExecutionId, 'runtime-execution-42');
    expect(loaded.single.parentEventId, 'ai-persisted-1');
    final aiActivity = await reopenedStore.loadActivityById('ai-persisted-1');
    expect(aiActivity!.kind, ActivityKind.aiRequest);
    expect(aiActivity.target, 'gemini');
    expect(aiActivity.summary, isNot(contains('prompt')));
    expect((await reopenedStore.loadActivityById('tool-persisted-1'))?.status, ActivityStatus.completed);
  });

  test('version three migration replaces legacy report keys without losing data', () async {
    final directory = await Directory.systemTemp.createTemp('cybersecurity-v3-migration-');
    final databasePath = p.join(directory.path, 'legacy-v3.sqlite');
    final legacyResult = result('legacy-v3.example');
    final stableId = activityResultKey(legacyResult.toolId, legacyResult.target, legacyResult.completedAt);
    final legacyFinding = _testFindingRecord(DateTime.utc(2026, 11, 23), sourceKey: stableId);
    final legacyDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 3,
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
          await db.execute('''
            CREATE TABLE activity_events (
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
          await db.execute('''
            CREATE TABLE security_findings (
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
          final legacyReportKey = 'dns_lookup|legacy-v3.example|${legacyResult.completedAt.toUtc().microsecondsSinceEpoch}';
          await db.insert('scan_results', {
            'result_key': legacyReportKey,
            'tool_id': legacyResult.toolId,
            'target': legacyResult.target,
            'completed_at': legacyResult.completedAt.toUtc().toIso8601String(),
            'authorization_confirmed': 1,
            'payload_json': encodeToolRunResult(legacyResult),
          });
          await db.insert('activity_events', {
            'event_id': 'legacy-activity',
            'kind': ActivityKind.tool.name,
            'tool_id': 'dns_lookup',
            'target': 'legacy-v3.example',
            'status': ActivityStatus.completed.name,
            'started_at': activityTimestamp(DateTime.utc(2026, 11, 23)),
            'finished_at': activityTimestamp(DateTime.utc(2026, 11, 23, 0, 0, 2)),
            'summary': 'Legacy activity survived migration.',
            'finding_count': 1,
            'source_result_key': stableId,
          });
          await db.insert('security_findings', {
            'finding_id': legacyFinding.findingId,
            'fingerprint': legacyFinding.fingerprint,
            'title': legacyFinding.title,
            'category': legacyFinding.category,
            'target': legacyFinding.target,
            'severity': legacyFinding.severity.name,
            'confidence': legacyFinding.confidence.name,
            'status': legacyFinding.status.name,
            'description': legacyFinding.description,
            'evidence_json': jsonEncode(legacyFinding.evidence),
            'source_report_keys_json': jsonEncode(legacyFinding.sourceReportKeys),
            'recommendation': legacyFinding.recommendation,
            'first_seen': activityTimestamp(legacyFinding.firstSeen),
            'last_seen': activityTimestamp(legacyFinding.lastSeen),
            'created_at': activityTimestamp(legacyFinding.createdAt),
            'updated_at': activityTimestamp(legacyFinding.updatedAt),
            'source_tool': legacyFinding.sourceTool,
            'assessment_id': legacyFinding.assessmentId,
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
    expect((await upgradedStore.loadReportById(stableId))?.target, 'legacy-v3.example');
    expect(await upgradedStore.loadRecent(), hasLength(1));
    final migratedActivities = await upgradedStore.loadActivities();
    expect(migratedActivities, hasLength(1));
    expect(migratedActivities.single.summary, 'Legacy activity survived migration.');
    expect(migratedActivities.single.sourceResultKey, stableId);
    final migratedFindings = await upgradedStore.loadFindings();
    expect(migratedFindings, hasLength(1));
    expect(migratedFindings.single.title, legacyFinding.title);
    expect(migratedFindings.single.sourceReportKeys, [stableId]);
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

  test('version two migration preserves saved reports and activity events', () async {
    final directory = await Directory.systemTemp.createTemp('cybersecurity-v2-migration-');
    final databasePath = p.join(directory.path, 'legacy.sqlite');
    final legacyResult = result('kept-report.example');
    final legacyDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
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
          await db.execute('''
            CREATE TABLE activity_events (
              event_id TEXT PRIMARY KEY, kind TEXT NOT NULL, parent_event_id TEXT, tool_id TEXT,
              target TEXT NOT NULL, status TEXT NOT NULL, started_at TEXT NOT NULL, finished_at TEXT,
              summary TEXT, finding_count INTEGER, source_result_key TEXT
            )
          ''');
          await db.insert('scan_results', {
            'result_key': 'dns_lookup|kept-report.example|${legacyResult.completedAt.toUtc().microsecondsSinceEpoch}',
            'tool_id': legacyResult.toolId,
            'target': legacyResult.target,
            'completed_at': legacyResult.completedAt.toUtc().toIso8601String(),
            'authorization_confirmed': 1,
            'payload_json': encodeToolRunResult(legacyResult),
          });
          await db.insert('activity_events', {
            'event_id': 'legacy-event',
            'kind': 'tool',
            'tool_id': 'dns_lookup',
            'target': 'kept-report.example',
            'status': 'completed',
            'started_at': activityTimestamp(DateTime.utc(2026, 11, 23)),
            'summary': 'Legacy event remains.',
          });
        },
      ),
    );
    await legacyDatabase.close();

    final store = LocalResultStore(databaseFactory: databaseFactoryFfi, databasePathProvider: () async => databasePath);
    addTearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
    expect((await store.loadRecent()).single.target, 'kept-report.example');
    expect((await store.loadActivities()).single.eventId, 'legacy-event');
    expect((await store.saveObservedFindings([_testFindingRecord(DateTime.utc(2026), sourceKey: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc')])).single.category,
        'HTTP Security Headers');
  });

  test('findings persist, deduplicate observations and preserve a user-selected status', () async {
    final directory = await Directory.systemTemp.createTemp('cybersecurity-findings-');
    final databasePath = p.join(directory.path, 'findings.sqlite');
    final firstStore = LocalResultStore(databaseFactory: databaseFactoryFfi, databasePathProvider: () async => databasePath);
    final firstAt = DateTime.utc(2026, 11, 1);
    final secondAt = DateTime.utc(2026, 11, 15);
    final initial = (await firstStore.saveObservedFindings([
      _testFindingRecord(firstAt, sourceKey: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', assessmentId: 'assessment-1'),
    ])).single;
    await firstStore.updateFindingStatus(initial.findingId, FindingStatus.falsePositive);
    final updated = (await firstStore.saveObservedFindings([
      _testFindingRecord(secondAt, sourceKey: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', assessmentId: 'assessment-2'),
    ])).single;
    expect(updated.status, FindingStatus.falsePositive);
    expect(updated.firstSeen, firstAt);
    expect(updated.lastSeen, secondAt);
    await firstStore.close();

    final reopenedStore = LocalResultStore(databaseFactory: databaseFactoryFfi, databasePathProvider: () async => databasePath);
    addTearDown(() async {
      await reopenedStore.close();
      await directory.delete(recursive: true);
    });
    final loaded = await reopenedStore.loadFindings(status: FindingStatus.falsePositive, query: 'HSTS');
    expect(loaded, hasLength(1));
    expect(loaded.single.findingId, initial.findingId);
    expect(loaded.single.fingerprint, initial.fingerprint);
    expect(loaded.single.firstSeen, firstAt);
    expect(loaded.single.lastSeen, secondAt);
    expect(loaded.single.sourceReportKeys.toSet(), {'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'});
    expect(loaded.single.assessmentId, 'assessment-2');
  });

  test('refuses derived analyzer results', () async {
    final store = createStore();
    addTearDown(store.close);
    final analyzer = SecurityTools().analyze([result('example.com')], target: 'example.com');

    await expectLater(store.save(analyzer), throwsArgumentError);
  });
}
