import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/diagnostics.dart';
import '../core/package_manager.dart';

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
  String _device = 'Android details unavailable';
  String _version = 'Loading…';
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

  void _changed() { if (mounted) setState(() {}); }

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
    try {
      final package = await PackageInfo.fromPlatform();
      _version = '${package.version} (${package.buildNumber})';
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
    setState(() { _saving = true; _message = null; });
    try {
      await reporter.configure(DiagnosticSettings(
        consentGranted: _consent,
        autoReportingEnabled: _enabled,
        wifiOnly: _wifiOnly,
        reviewBeforeUpload: _review,
        backendEndpoint: _endpoint.text.trim(),
        repository: _repository.text.trim(),
      ));
      if (mounted) setState(() => _message = 'Settings saved. Reports stay on this device unless the optional relay is configured and upload is enabled.');
    } catch (error) {
      if (mounted) setState(() => _message = sanitizeDiagnosticText(error.toString()));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _saving = true);
    try {
      final ok = await reporter.testRelayEndpoint(_endpoint.text);
      if (mounted) setState(() => _message = ok ? 'Relay responds. This does not verify GitHub issue creation.' : 'Relay connection failed or URL is invalid. No report was sent.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reviewReport(DiagnosticReport report) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review diagnostic report'),
        content: SingleChildScrollView(child: SelectableText('${report.category.name} · ${report.errorType}\n\n${report.message}\n\n${report.stack}\n\nOccurrences: ${report.occurrences}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep local')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve upload')),
        ],
      ),
    );
    if (approved == true) {
      if (!reporter.settings.consentGranted || !reporter.settings.autoReportingEnabled) {
        if (mounted) setState(() => _message = 'Grant consent and enable reporting before approving upload.');
        return;
      }
      await reporter.approveAndUpload(report.id);
    }
  }

  void _export() {
    final data = reporter.exportReport();
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('Export diagnostics'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: SelectableText(data))),
      actions: [TextButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: data)); if (context.mounted) Navigator.pop(context); }, child: const Text('Copy JSON')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  @override
  void dispose() {
    reporter.removeListener(_changed);
    _endpoint.dispose();
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Developer Diagnostics')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _section('App & device', [
            ListTile(leading: const Icon(Icons.info_outline), title: const Text('Application'), subtitle: Text(_version)),
            ListTile(leading: const Icon(Icons.phone_android), title: const Text('Device (non-unique)'), subtitle: Text(_device)),
            ListTile(leading: const Icon(Icons.memory), title: const Text('Embedded runtime'), subtitle: const Text('No executable runtime is installed or enabled in this build.')),
            ListTile(leading: const Icon(Icons.inventory_2_outlined), title: Text('Market packages (${widget.marketManager.installedPackages.length} installed)'), subtitle: Text(widget.marketManager.installedPackages.isEmpty ? 'No user-installed packages.' : widget.marketManager.installedPackages.map((entry) => '${entry.id} ${entry.version}').join(' · '))),
          ]),
          const SizedBox(height: 12),
          _section('Error reporting · local-first', [
            SwitchListTile(value: _consent, onChanged: (value) => setState(() => _consent = value), title: const Text('I consent to optional upload of locally stored diagnostic reports')),
            SwitchListTile(value: _enabled, onChanged: _consent ? (value) => setState(() => _enabled = value) : null, title: const Text('Enable automatic reporting')),
            SwitchListTile(value: _review, onChanged: (value) => setState(() => _review = value), title: const Text('Review before each upload')),
            SwitchListTile(value: _wifiOnly, onChanged: (value) => setState(() => _wifiOnly = value), title: const Text('Wi-Fi only')),
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: TextField(controller: _endpoint, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Optional HTTPS relay URL (no query tokens)', hintText: 'https://your-worker.example/diagnostics'))),
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: TextField(controller: _repository, decoration: const InputDecoration(labelText: 'GitHub owner/repository'))),
            ListTile(leading: const Icon(Icons.report_outlined), title: const Text('Pending reports'), subtitle: Text('${reporter.pendingCount} local · ${reporter.reports.where((r) => r.status == DiagnosticStatus.sent).length} sent'), trailing: TextButton(onPressed: reporter.pendingCount == 0 ? null : () => reporter.deletePendingReports(), child: const Text('Clear pending'))),
            ListTile(leading: const Icon(Icons.cloud_done_outlined), title: const Text('Upload status'), subtitle: Text(reporter.lastSuccessfulUpload == null ? 'No successful upload recorded' : 'Last success: ${reporter.lastSuccessfulUpload!.toLocal()}')),
            for (final report in reporter.pendingReports)
              ListTile(
                leading: Icon(report.status == DiagnosticStatus.failed ? Icons.error_outline : Icons.pending_outlined),
                title: Text('${report.category.name}: ${report.errorType}'),
                subtitle: Text('${report.message}\n${report.status.name} · ${report.occurrences} occurrence(s)'),
                isThreeLine: true,
                trailing: report.status == DiagnosticStatus.waitingForReview ? IconButton(tooltip: 'Review and approve', icon: const Icon(Icons.rate_review_outlined), onPressed: () => _reviewReport(report)) : null,
              ),
          ]),
          if (reporter.storageWarning != null) Padding(padding: const EdgeInsets.all(12), child: Text('Local storage warning: ${reporter.storageWarning}', style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_message != null) Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('Save')),
            OutlinedButton.icon(onPressed: _saving ? null : _testConnection, icon: const Icon(Icons.wifi_tethering), label: const Text('Test relay')),
            OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.ios_share), label: const Text('Export JSON')),
            OutlinedButton.icon(onPressed: reporter.clearLocalReports, icon: const Icon(Icons.delete_outline), label: const Text('Clear logs')),
          ]),
          const SizedBox(height: 10),
          const Text('A configured relay is optional. This app does not contain GitHub credentials. Relay reachability does not prove that a GitHub issue was created; no Issues are created by local tests.', style: TextStyle(height: 1.45)),
        ]),
      );

  Widget _section(String title, List<Widget> children) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.all(8), child: Text(title, style: Theme.of(context).textTheme.titleMedium)), ...children])));
}
