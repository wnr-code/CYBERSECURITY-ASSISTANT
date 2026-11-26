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
    expect(localization.text('ASSESSMENT STATUS'), 'STATUS ASSESSMENT');
    expect(localization.text('Floating Terminal'), 'Terminal Mengambang');
    expect(localization.text('Terminal ready'), 'Terminal siap');
    expect(localization.text('Exit terminal session?'), 'Keluar dari sesi terminal?');
    expect(
      localization.text('The bridge currently accepts only ready app-registered network tools; Market packages are not loaded as executable code.'),
      'Saat ini jalur hanya menerima tool jaringan terdaftar di aplikasi yang siap; paket Market tidak dimuat sebagai kode yang dapat dijalankan.',
    );
    expect(
      localization.text('The orb shows operational status only; grid and particles are decorative, not network topology or security score.'),
      'Orb hanya menampilkan status operasional; kisi dan partikel dekoratif, bukan topologi jaringan atau skor keamanan.',
    );
    expect(localization.text('Critical'), 'KRITIS');
    expect(localization.text('Informational'), 'INFORMASIONAL');
    expect(localization.text('Severity'), 'Tingkat keparahan');
    expect(localization.text('Run a check that produces an indicator, or revise the filters. Finding status is managed separately from report history.'),
        'Jalankan pemeriksaan yang menghasilkan indikator atau sesuaikan filter. Status temuan dikelola terpisah dari riwayat laporan.');
    expect(localization.text('Unavailable'), 'Belum tersedia');
    expect(localization.text('No findings in this loaded view'), 'Tidak ada temuan pada data yang dimuat ini');
    expect(localization.text('AI requests'), 'Permintaan AI');
    expect(localization.text('Confirm AI data sharing'), 'Konfirmasi pembagian data AI');
    expect(localization.text('Runtime Execution ID'), 'ID Eksekusi Runtime');
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
    expect(localization.text('Belum tersedia'), 'Not available yet');
    expect(localization.text('Terminal Mengambang'), 'Floating Terminal');
    expect(localization.text('Terminal siap'), 'Terminal ready');
    expect(localization.text('Keluar dari sesi terminal?'), 'Exit terminal session?');
    expect(
      localization.text('Saat ini jalur hanya menerima tool jaringan terdaftar di aplikasi yang siap; paket Market tidak dimuat sebagai kode yang dapat dijalankan.'),
      'The bridge currently accepts only ready app-registered network tools; Market packages are not loaded as executable code.',
    );
    expect(
      localization.text('The orb shows operational status only; grid and particles are decorative, not network topology or security score.'),
      'The orb shows operational status only; grid and particles are decorative, not network topology or security score.',
    );
    expect(localization.text('Tidak ada temuan pada data yang dimuat ini'), 'No findings in this loaded view');
    expect(localization.text('Permintaan AI'), 'AI requests');
    expect(localization.text('Konfirmasi pembagian data AI'), 'Confirm AI data sharing');
    expect(localization.text('ID Eksekusi Runtime'), 'Runtime Execution ID');
    expect(localization.text('Siap dijalankan'), 'Ready to run');
    expect(localization.text('Memerlukan izin'), 'Requires permission');
    expect(
      localization.text('Memvalidasi koneksi TLS dan memeriksa identitas serta masa berlaku sertifikat.'),
      'Validates the TLS connection and checks certificate identity and expiry.',
    );
    expect(localization.text('Laporan sumber:'), 'Source reports:');
  });
}
