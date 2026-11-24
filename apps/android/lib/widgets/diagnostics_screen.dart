import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/diagnostics.dart';
import '../core/package_manager.dart';
import '../l10n/app_localizations.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, required this.reporter, required this.marketManager});

  final DiagnosticReporter reporter;
  final MarketPackageManager marketManager;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final _endpoint = TextEditingController();
  final _repository = TextEditingController();
  bool _saving = false;
  String _device = '';
  String _version = '';
  String? _message;
  bool _consent = false;
  bool _enabled = false;
  bool _wifiOnly = false;
  bool _review = true;

  DiagnosticReporter get reporter => widget.reporter;

  @override
  void initState() {
    super.initState();
    reporter.addListener(_changed);
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await reporter.initialize();
    await widget.marketManager.initialize();
    if (!mounted) return;
    _endpoint.text = reporter.settings.backendEndpoint;
    _repository.text = reporter.settings.repository;
    _consent = reporter.settings.consentGranted;
    _enabled = reporter.settings.autoReportingEnabled;
    _wifiOnly = reporter.settings.wifiOnly;
    _review = reporter.settings.reviewBeforeUpload;
    _version = '${reporter.appVersion} (${reporter.buildNumber})';
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        _device = 'Android ${info.version.release} · API ${info.version.sdkInt} · ${info.supportedAbis.join(', ')}';
      }
    } catch (_) {
      // Device details are best effort; no unique identifiers are collected.
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await reporter.configure(DiagnosticSettings(
        consentGranted: _consent,
        autoReportingEnabled: _enabled,
        wifiOnly: _wifiOnly,
        reviewBeforeUpload: _review,
        backendEndpoint: _endpoint.text.trim(),
        repository: _repository.text.trim(),
      ));
      if (mounted) setState(() => _message = context.tr('Pengaturan tersimpan. Laporan tetap di ponsel kecuali Anda mengaktifkan upload dan mengatur relay.'));
    } catch (_) {
      if (mounted) setState(() => _message = context.tr('Pengaturan tidak dapat disimpan. Coba lagi.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _saving = true);
    try {
      final ok = await reporter.testRelayEndpoint(_endpoint.text);
      if (mounted) {
        setState(() => _message = ok
            ? context.tr('Relay merespons. Ini belum membuktikan bahwa Issue GitHub dibuat.')
            : context.tr('Relay tidak merespons atau URL tidak valid. Tidak ada laporan yang dikirim.'));
      }
    } catch (_) {
      if (mounted) setState(() => _message = context.tr('Tes relay gagal. Periksa alamat HTTPS dan koneksi internet.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reviewReport(DiagnosticReport report) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('Tinjau laporan error')),
        content: SingleChildScrollView(
          child: SelectableText(
            '${report.category.name} · ${report.errorType}\n\n${report.message}\n\n${report.stack}\n\n${dialogContext.tr('Jumlah kejadian')}: ${report.occurrences}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(dialogContext.tr('Simpan di ponsel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(dialogContext.tr('Setujui upload'))),
        ],
      ),
    );
    if (approved == true) {
      if (!reporter.settings.consentGranted || !reporter.settings.autoReportingEnabled) {
        if (mounted) setState(() => _message = context.tr('Berikan persetujuan dan aktifkan pelaporan sebelum menyetujui upload.'));
        return;
      }
      await reporter.approveAndUpload(report.id);
    }
  }

  Future<void> _createLocalTestReport() async {
    await reporter.recordLocalTestReport(message: context.tr('Laporan contoh lokal; ini bukan error aplikasi nyata.'));
    if (mounted) setState(() => _message = context.tr('Laporan uji contoh tersimpan di ponsel dan tidak akan dikirim.'));
  }

  void _export() {
    final data = reporter.exportReport();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('Ekspor laporan diagnostik')),
        content: SizedBox(width: 560, child: SingleChildScrollView(child: SelectableText(data))),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: data));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(dialogContext.tr('Salin JSON')),
          ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(dialogContext.tr('Tutup'))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    reporter.removeListener(_changed);
    _endpoint.dispose();
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sentCount = reporter.reports.where((report) => report.status == DiagnosticStatus.sent).length;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Diagnostik Pengembang'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _helpCard(context),
          const SizedBox(height: 12),
          _section(context, 'Info aplikasi dan ponsel', [
            ListTile(leading: const Icon(Icons.info_outline), title: Text(context.tr('Versi aplikasi')), subtitle: Text(_version.isEmpty ? context.tr('Sedang memuat…') : _version)),
            ListTile(leading: const Icon(Icons.phone_android), title: Text(context.tr('Info ponsel (tanpa ID unik)')), subtitle: Text(_device.isEmpty ? context.tr('Belum tersedia') : _device)),
            ListTile(leading: const Icon(Icons.memory), title: Text(context.tr('Runtime tertanam')), subtitle: Text(context.tr('Belum ada runtime yang dapat dijalankan di versi aplikasi ini.'))),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(context.tr('Paket Market')),
              subtitle: Text(widget.marketManager.installedPackages.isEmpty
                  ? context.tr('Belum ada paket yang dipasang pengguna.')
                  : '${widget.marketManager.installedPackages.length} ${context.tr('paket terpasang')}: ${widget.marketManager.installedPackages.map((entry) => '${entry.id} ${entry.version}').join(' · ')}'),
            ),
          ]),
          const SizedBox(height: 12),
          _section(context, 'Laporan error (tersimpan lokal)', [
            Text(
              context.tr('Secara bawaan, laporan hanya disimpan di ponsel. Upload tidak aktif tanpa persetujuan Anda dan pengaturan relay.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SwitchListTile(
              value: _consent,
              onChanged: (value) => setState(() => _consent = value),
              title: Text(context.tr('Saya setuju mengirim laporan error secara opsional')),
            ),
            SwitchListTile(
              value: _enabled,
              onChanged: _consent ? (value) => setState(() => _enabled = value) : null,
              title: Text(context.tr('Aktifkan pelaporan otomatis')),
            ),
            SwitchListTile(
              value: _review,
              onChanged: (value) => setState(() => _review = value),
              title: Text(context.tr('Tinjau setiap laporan sebelum dikirim')),
            ),
            SwitchListTile(
              value: _wifiOnly,
              onChanged: (value) => setState(() => _wifiOnly = value),
              title: Text(context.tr('Gunakan Wi-Fi saja')),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _endpoint,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: context.tr('Alamat relay HTTPS (opsional)'),
                  hintText: 'https://example.com/diagnostics',
                  helperText: context.tr('Biarkan kosong jika Anda tidak menyiapkan server relay. Jangan masukkan token atau kata sandi di sini.'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                controller: _repository,
                decoration: InputDecoration(
                  labelText: context.tr('Repositori GitHub (pemilik/nama)'),
                  hintText: context.tr('contoh: organisasi/nama-proyek'),
                  helperText: context.tr('Mengisi repositori saja tidak membuat Issue GitHub. Relay yang dapat membuat Issue belum tersedia di aplikasi ini.'),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.report_outlined),
              title: Text(context.tr('Laporan tertunda')),
              subtitle: Text('${reporter.pendingCount} ${context.tr('di ponsel')} · $sentCount ${context.tr('terkirim')}'),
              trailing: TextButton(
                onPressed: reporter.pendingCount == 0 ? null : () => reporter.deletePendingReports(),
                child: Text(context.tr('Hapus tertunda')),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: Text(context.tr('Status upload')),
              subtitle: Text(reporter.lastSuccessfulUpload == null
                  ? context.tr('Belum pernah ada upload berhasil')
                  : '${context.tr('Upload berhasil terakhir')}: ${reporter.lastSuccessfulUpload!.toLocal()}'),
            ),
            if (reporter.pendingReports.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(context.tr('Belum ada laporan tertunda. Jika aplikasi mengalami error, laporan yang berhasil direkam akan muncul di sini.')),
              ),
            for (final report in reporter.pendingReports)
              ListTile(
                leading: Icon(report.status == DiagnosticStatus.failed ? Icons.error_outline : Icons.pending_outlined),
                title: Text(report.isLocalTest ? context.tr('Contoh laporan (bukan error nyata)') : '${report.category.name}: ${report.errorType}'),
                subtitle: Text('${report.message}\n${_reportStatusLabel(context, report)} · ${report.occurrences} ${context.tr('kejadian')}'),
                isThreeLine: true,
                trailing: report.status == DiagnosticStatus.waitingForReview && !report.isLocalTest
                    ? IconButton(
                        tooltip: context.tr('Tinjau dan setujui'),
                        icon: const Icon(Icons.rate_review_outlined),
                        onPressed: () => _reviewReport(report),
                      )
                    : null,
              ),
          ]),
          if (reporter.storageWarning != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('${context.tr('Peringatan penyimpanan lokal')}: ${reporter.storageWarning}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_message != null) Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(context.tr('Simpan pengaturan'))),
              OutlinedButton.icon(onPressed: _createLocalTestReport, icon: const Icon(Icons.fact_check_outlined), label: Text(context.tr('Buat laporan uji lokal'))),
              OutlinedButton.icon(onPressed: _saving ? null : _testConnection, icon: const Icon(Icons.wifi_tethering), label: Text(context.tr('Tes relay'))),
              OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.ios_share), label: Text(context.tr('Ekspor laporan JSON'))),
              OutlinedButton.icon(onPressed: reporter.clearLocalReports, icon: const Icon(Icons.delete_outline), label: Text(context.tr('Hapus semua laporan lokal'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _helpCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.help_outline),
              const SizedBox(width: 8),
              Expanded(child: Text(context.tr('Untuk apa halaman ini?'), style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 8),
            Text(context.tr('Halaman ini membantu melihat dan membagikan catatan error aplikasi kepada tim dukungan. Ini bukan pemindai virus dan tidak menjalankan program di ponsel.')),
            const SizedBox(height: 12),
            Text(context.tr('Contoh cara memakai'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text('1. ${context.tr('Jika aplikasi bermasalah, buka bagian Laporan tertunda dan baca pesan errornya.')}'),
            Text('2. ${context.tr('Tekan Ekspor laporan JSON untuk menyalin laporan, lalu kirim hanya kepada tim dukungan yang Anda percaya.')}'),
            Text('3. ${context.tr('Jika tidak diminta mengirim laporan, biarkan persetujuan upload tetap mati.')}'),
            const SizedBox(height: 8),
            Text(context.tr('Contoh: aplikasi tertutup sendiri → buka halaman ini → ekspor laporan JSON → kirim ke dukungan resmi.'), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _section(BuildContext context, String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.all(8), child: Text(context.tr(title), style: Theme.of(context).textTheme.titleMedium)),
            ...children,
          ]),
        ),
      );

  String _reportStatusLabel(BuildContext context, DiagnosticReport report) => report.isLocalTest
      ? context.tr('Uji lokal · tidak dikirim')
      : _statusLabel(context, report.status);

  String _statusLabel(BuildContext context, DiagnosticStatus status) => switch (status) {
        DiagnosticStatus.waitingForReview => context.tr('Menunggu ditinjau'),
        DiagnosticStatus.queued => context.tr('Menunggu dikirim'),
        DiagnosticStatus.uploading => context.tr('Sedang mengirim'),
        DiagnosticStatus.sent => context.tr('Terkirim'),
        DiagnosticStatus.failed => context.tr('Gagal mengirim'),
      };
}
