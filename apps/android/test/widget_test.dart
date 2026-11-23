import 'package:cybersecurity_assistant/core/provider_registry.dart';
import 'package:cybersecurity_assistant/core/secure_credential_store.dart';
import 'package:cybersecurity_assistant/l10n/app_localizations.dart';
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

    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Alat'), findsOneWidget);
    expect(find.text('Asisten'), findsOneWidget);
    expect(find.text('Koneksi'), findsOneWidget);
    expect(find.text('Keamanan digital, kendali tetap di tangan Anda.'), findsOneWidget);
  });

  testWidgets('filters the tool registry by search text', (tester) async {
    await tester.pumpWidget(const CybersecurityAssistantApp());
    await tester.tap(find.text('Alat'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'TLS');
    await tester.pump();

    expect(find.text('Inspeksi Sertifikat TLS'), findsOneWidget);
    expect(find.text('Pencarian DNS'), findsNothing);
  });

  testWidgets('does not run a network check until authorization is confirmed', (tester) async {
    await tester.pumpWidget(const CybersecurityAssistantApp());
    await tester.tap(find.text('Alat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pencarian DNS'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'example.com');
    await tester.tap(find.text('Jalankan pemeriksaan'));
    await tester.pumpAndSettle();

    expect(find.text('Konfirmasi bahwa Anda memiliki atau mendapat izin untuk menguji target ini.'), findsOneWidget);

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
    await tester.tap(find.text('Alat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lihat rilis GitHub'));
    await tester.pumpAndSettle();

    expect(find.text('Metadata rilis GitHub'), findsOneWidget);
    expect(find.text('Periksa rilis terbaru'), findsOneWidget);
    expect(find.text('Pilih repositori referensi yang diizinkan. Halaman ini hanya membaca metadata rilis; file tidak diunduh atau dijalankan.'), findsOneWidget);
  });

  testWidgets('provider catalog search opens an explicitly unconnected guide', (tester) async {
    await tester.pumpWidget(const CybersecurityAssistantApp());
    await tester.tap(find.text('Koneksi'));
    await tester.pumpAndSettle();

    final providerSearch = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == 'Cari penyedia layanan',
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
    expect(find.text('Status: Panduan saja · belum terhubung'), findsOneWidget);
    expect(find.text('Autentikasi: Memerlukan API key milik pengguna'), findsOneWidget);
    expect(find.text('Status penyimpanan kredensial: belum diperiksa'), findsOneWidget);
    expect(find.text('Kredensial tersimpan belum dikirim ke provider. Permintaan terautentikasi dan uji koneksi khusus provider belum dibuat.'), findsOneWidget);
  });

  testWidgets('provider details stores a masked credential without making a provider request', (tester) async {
    final backend = _MemorySecretBackend();
    final credentialStore = SecureCredentialStore(backend: backend);
    final provider = providerRegistry.firstWhere((item) => item.id == 'openai');

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
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
    final storeCredentialButton = find.widgetWithText(OutlinedButton, 'Store API key');
    await tester.ensureVisible(storeCredentialButton);
    await tester.tap(storeCredentialButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'test-key-never-send');
    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText, isTrue);
    await tester.ensureVisible(find.text('Save securely'));
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
    await tester.tap(find.text('Koneksi'));
    await tester.pumpAndSettle();

    final connectionButton = find.widgetWithText(FilledButton, 'Uji koneksi');
    final authorization = find.byType(CheckboxListTile).first;
    final connectionScroll = find.descendant(
      of: find.byType(ConnectionsScreen),
      matching: find.byType(Scrollable),
    ).first;
    Future<void> confirmCurrentEndpoint() async {
      await tester.scrollUntilVisible(authorization, 100, scrollable: connectionScroll);
      await tester.drag(connectionScroll, const Offset(0, 160));
      await tester.pumpAndSettle();
      await tester.tap(authorization);
      await tester.pump();
    }

    await tester.enterText(find.byType(TextField).first, 'http://example.com');
    expect(tester.widget<FilledButton>(connectionButton).onPressed, isNull);

    await confirmCurrentEndpoint();
    expect(tester.widget<FilledButton>(connectionButton).onPressed, isNotNull);
    await tester.ensureVisible(connectionButton);
    await tester.tap(find.text('Uji koneksi'));
    await tester.pump();
    expect(find.text('Masukkan URL HTTPS valid tanpa kredensial, kueri, atau fragmen.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'https://example.com/?token=secret');
    await tester.pump();
    expect(tester.widget<FilledButton>(connectionButton).onPressed, isNull);
    await confirmCurrentEndpoint();
    expect(tester.widget<FilledButton>(connectionButton).onPressed, isNotNull);
    await tester.ensureVisible(connectionButton);
    await tester.tap(find.text('Uji koneksi'));
    await tester.pump();
    expect(find.text('Masukkan URL HTTPS valid tanpa kredensial, kueri, atau fragmen.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'https://example.com:not-a-port');
    await confirmCurrentEndpoint();
    await tester.ensureVisible(connectionButton);
    await tester.tap(find.text('Uji koneksi'));
    await tester.pump();
    expect(find.text('Masukkan URL HTTPS valid tanpa kredensial, kueri, atau fragmen.'), findsOneWidget);
  });
}
