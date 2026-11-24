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
    expect(localization.text('Assessment already running'), 'Assessment sedang berjalan');
    expect(localization.text('Another assessment is already running.'), 'Assessment lain sedang berjalan. Batalkan atau tunggu sampai selesai sebelum memulai lagi.');
    expect(localization.text('Developer Diagnostics'), 'Diagnostik Pengembang');
    expect(localization.text('Untuk apa halaman ini?'), 'Untuk apa halaman ini?');
    expect(localization.text('Contoh cara memakai'), 'Contoh cara memakai');
    expect(localization.text('Buat laporan uji lokal'), 'Buat laporan uji lokal');
    expect(localization.text('DIGITAL EARTH'), 'DIGITAL EARTH');
    expect(localization.text('Unavailable'), 'Belum tersedia');
    expect(localization.text('No findings in this loaded view'), 'Tidak ada temuan pada data yang dimuat ini');
  });

  test('English can be selected through the same source-key catalog', () {
    const localization = AppLocalizations(Locale('en'));

    expect(localization.text('Beranda'), 'Home');
    expect(localization.text('Riwayat lokal tidak dapat dimuat.'), 'Could not load local history.');
    expect(localization.text('Memerlukan API key milik pengguna'), 'User-owned API key required');
    expect(localization.text('Diagnostik Pengembang'), 'Developer Diagnostics');
    expect(localization.text('Untuk apa halaman ini?'), 'What is this page for?');
    expect(localization.text('Contoh cara memakai'), 'Example: how to use it');
    expect(localization.text('Buat laporan uji lokal'), 'Create local test report');
    expect(localization.text('Belum tersedia'), 'Unavailable');
    expect(localization.text('Tidak ada temuan pada data yang dimuat ini'), 'No findings in this loaded view');
  });
}
