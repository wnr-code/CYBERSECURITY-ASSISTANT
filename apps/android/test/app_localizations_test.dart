import 'package:cybersecurity_assistant/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Indonesian is the primary interface language', () {
    const localization = AppLocalizations(Locale('id'));

    expect(localization.text('Home'), 'Beranda');
    expect(localization.text('Could not load local history.'), 'Riwayat lokal tidak dapat dimuat.');
    expect(localization.text('User-owned API key required'), 'Memerlukan API key milik pengguna');
    expect(localization.text('Assessment'), 'Assessment');
    expect(localization.text('Run assessment'), 'Jalankan assessment');
  });

  test('English can be selected through the same source-key catalog', () {
    const localization = AppLocalizations(Locale('en'));

    expect(localization.text('Beranda'), 'Home');
    expect(localization.text('Riwayat lokal tidak dapat dimuat.'), 'Could not load local history.');
    expect(localization.text('Memerlukan API key milik pengguna'), 'User-owned API key required');
  });
}
