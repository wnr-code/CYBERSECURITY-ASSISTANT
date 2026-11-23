import 'dart:io';

import 'package:cybersecurity_assistant/core/local_result_store.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:cybersecurity_assistant/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('dashboard reloads file-backed saved history at startup', (tester) async {
    final directory = await Directory.systemTemp.createTemp('cybersecurity-assistant-app-history-');
    final databasePath = p.join(directory.path, 'history.sqlite');
    LocalResultStore makeStore() => LocalResultStore(
          databaseFactory: databaseFactoryFfi,
          databasePathProvider: () async => databasePath,
        );

    final seedStore = makeStore();
    await seedStore.save(ToolRunResult(
      toolId: 'dns_lookup',
      target: 'persisted.example',
      summary: 'Resolved one address.',
      details: const ['192.0.2.10'],
      findings: const [],
      completedAt: DateTime.utc(2026, 11, 23),
      authorizationConfirmed: true,
    ));
    await seedStore.close();

    final appStore = makeStore();
    addTearDown(() async {
      await appStore.close();
      await directory.delete(recursive: true);
    });

    await tester.pumpWidget(MaterialApp(home: MainShell(resultStore: appStore)));
    await tester.pumpAndSettle();

    expect(find.textContaining('persisted.example'), findsOneWidget);
    expect(find.text('DNS Lookup'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await appStore.close();
  });
}
