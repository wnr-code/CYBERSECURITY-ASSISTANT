import 'package:cybersecurity_assistant/core/provider_registry.dart';
import 'package:cybersecurity_assistant/core/secure_credential_store.dart';
import 'package:cybersecurity_assistant/main.dart';
import 'package:cybersecurity_assistant/widgets/provider_details_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _MemorySecretBackend implements SecureStorageBackend {
  final values = <String, String>{};

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

void main() {
  testWidgets('shows the primary navigation destinations', (tester) async {
    await tester.pumpWidget(const CybersecurityAssistantApp());

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Assistant'), findsOneWidget);
    expect(find.text('Connections'), findsOneWidget);
    expect(find.text('Your security,\nyour infrastructure.'), findsOneWidget);
  });

  testWidgets('filters the tool registry by search text', (tester) async {
    await tester.pumpWidget(const CybersecurityAssistantApp());
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'TLS');
    await tester.pump();

    expect(find.text('SSL/TLS Inspector'), findsOneWidget);
    expect(find.text('DNS Lookup'), findsNothing);
  });

  testWidgets('does not run a network check until authorization is confirmed', (tester) async {
    await tester.pumpWidget(const CybersecurityAssistantApp());
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DNS Lookup'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'example.com');
    await tester.tap(find.text('Run check'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm that you own or are authorized to test this target.'), findsOneWidget);

    final authorization = find.byType(CheckboxListTile).first;
    await tester.tap(authorization);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(authorization).value, isTrue);

    await tester.enterText(find.byType(TextField).last, 'other.example');
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(authorization).value, isFalse);
  });

  testWidgets('GitHub release metadata lookup is user-triggered', (tester) async {
    await tester.pumpWidget(const CybersecurityAssistantApp());
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check GitHub releases'));
    await tester.pumpAndSettle();

    expect(find.text('GitHub release metadata'), findsOneWidget);
    expect(find.text('Check latest release'), findsOneWidget);
    expect(find.text('Choose an allowlisted reference repository. This reads release metadata only; it does not download or run files.'), findsOneWidget);
  });

  testWidgets('provider catalog search opens an explicitly unconnected guide', (tester) async {
    await tester.pumpWidget(const CybersecurityAssistantApp());
    await tester.tap(find.text('Connections'));
    await tester.pumpAndSettle();

    final providerSearch = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == 'Search providers',
    );
    final connectionsScroll = find.descendant(
      of: find.byType(ConnectionsScreen),
      matching: find.byType(Scrollable),
    ).first;
    await tester.scrollUntilVisible(providerSearch, 300, scrollable: connectionsScroll);
    await tester.enterText(providerSearch, 'OpenAI');
    await tester.pump();
    final openAiTile = find.widgetWithText(ListTile, 'OpenAI');
    expect(openAiTile, findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Supabase'), findsNothing);

    await tester.scrollUntilVisible(openAiTile, 300, scrollable: connectionsScroll);
    await tester.tap(openAiTile);
    await tester.pumpAndSettle();
    expect(find.text('Status: Guide only · not connected'), findsOneWidget);
    expect(find.text('Authentication: User-owned API key required'), findsOneWidget);
    expect(find.text('Credential storage: not checked'), findsOneWidget);
    expect(find.text('Stored credentials are not sent to this provider: authenticated requests and provider-specific connection tests are not implemented.'), findsOneWidget);
  });

  testWidgets('provider details stores a masked credential without making a provider request', (tester) async {
    final backend = _MemorySecretBackend();
    final credentialStore = SecureCredentialStore(backend: backend);
    final provider = providerRegistry.firstWhere((item) => item.id == 'openai');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ProviderDetailsDialog(provider: provider, credentialStore: credentialStore),
              ),
              child: const Text('Open details'),
            )),
      ),
    ));

    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Store API key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'test-key-never-send');
    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText, isTrue);
    await tester.tap(find.text('Save securely'));
    await tester.pumpAndSettle();

    expect(backend.values.values, contains('test-key-never-send'));
    expect(find.text('Credential stored locally. No provider request was made.'), findsOneWidget);
    expect(find.text('test-key-never-send'), findsNothing);

    final checkStatusButton = find.text('Check stored status');
    await tester.ensureVisible(checkStatusButton);
    await tester.tap(checkStatusButton);
    await tester.pumpAndSettle();
    expect(find.text('Credential storage: present'), findsOneWidget);
    expect(find.text('A credential is stored; its value was not displayed.'), findsOneWidget);

    await tester.ensureVisible(find.text('Delete').first);
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(backend.values, isEmpty);
    expect(find.text('Credential deleted.'), findsOneWidget);
  });

  testWidgets('requires current authorization and rejects invalid connection URLs', (tester) async {
    await tester.pumpWidget(const CybersecurityAssistantApp());
    await tester.tap(find.text('Connections'));
    await tester.pumpAndSettle();

    final connectionButton = find.widgetWithText(FilledButton, 'Test Connection');
    final authorization = find.byType(CheckboxListTile).first;
    final connectionScroll = find.descendant(
      of: find.byType(ConnectionsScreen),
      matching: find.byType(Scrollable),
    ).first;
    Future<void> confirmCurrentEndpoint() async {
      await tester.scrollUntilVisible(authorization, 100, scrollable: connectionScroll);
      await tester.tap(authorization);
      await tester.pump();
    }

    await tester.enterText(find.byType(TextField).first, 'http://example.com');
    expect(tester.widget<FilledButton>(connectionButton).onPressed, isNull);

    await confirmCurrentEndpoint();
    expect(tester.widget<FilledButton>(connectionButton).onPressed, isNotNull);
    await tester.ensureVisible(connectionButton);
    await tester.tap(find.text('Test Connection'));
    await tester.pump();
    expect(find.text('Enter a valid HTTPS URL without credentials, query, or fragment'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'https://example.com/?token=secret');
    await tester.pump();
    expect(tester.widget<FilledButton>(connectionButton).onPressed, isNull);
    await confirmCurrentEndpoint();
    await tester.ensureVisible(connectionButton);
    await tester.tap(find.text('Test Connection'));
    await tester.pump();
    expect(find.text('Enter a valid HTTPS URL without credentials, query, or fragment'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'https://example.com:not-a-port');
    await confirmCurrentEndpoint();
    await tester.ensureVisible(connectionButton);
    await tester.tap(find.text('Test Connection'));
    await tester.pump();
    expect(find.text('Enter a valid HTTPS URL without credentials, query, or fragment'), findsOneWidget);
  });
}
