import 'package:cybersecurity_assistant/core/local_result_store.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:cybersecurity_assistant/main.dart';
import 'package:cybersecurity_assistant/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _SavedHistory implements ResultHistoryStore {
  final saved = ToolRunResult(
    toolId: 'dns_lookup',
    target: 'persisted.example',
    summary: 'Resolved one address.',
    details: const ['192.0.2.10'],
    findings: const [],
    completedAt: DateTime.utc(2026, 11, 23),
    authorizationConfirmed: true,
  );
  bool loaded = false;

  @override
  Future<int> save(ToolRunResult result) async => 1;

  @override
  Future<List<ToolRunResult>> loadRecent({int limit = 30}) async {
    loaded = true;
    return [saved];
  }

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('dashboard loads saved history automatically at startup', (tester) async {
    final history = _SavedHistory();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: MainShell(resultStore: history),
    ));
    await tester.pumpAndSettle();

    expect(history.loaded, isTrue);
    final savedTarget = find.textContaining('persisted.example');
    await tester.scrollUntilVisible(savedTarget, 250);
    expect(savedTarget, findsOneWidget);
    expect(find.text('Pencarian DNS'), findsOneWidget);
  });
}
