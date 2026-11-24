import 'package:material_ui/material_ui.dart';

import '../core/runtime_manager.dart';
import '../core/security_tools.dart';
import '../core/tool_orchestrator.dart';
import '../core/tool_registry.dart';
import '../l10n/app_localizations.dart';

String _toolName(String id, BuildContext context) => switch (id) {
      'dns_lookup' => context.tr('Pencarian DNS'),
      'tls_inspector' => context.tr('Inspeksi Sertifikat TLS'),
      'http_headers' => context.tr('Pemeriksa Header HTTP'),
      'response_analyzer' => context.tr('Analisis Temuan'),
      _ => id,
    };

String _toolDescription(String id, BuildContext context) => switch (id) {
      'dns_lookup' => context.tr('Mencari alamat IPv4 dan IPv6 melalui resolver sistem Android; CNAME dan record lain belum tersedia.'),
      'tls_inspector' => context.tr('Memvalidasi koneksi TLS dan memeriksa identitas serta masa berlaku sertifikat.'),
      'http_headers' => context.tr('Mengirim satu GET HTTPS terbatas ke path yang dipilih dan memeriksa header serta body respons.'),
      'response_analyzer' => context.tr('Merangkum temuan dari pemeriksaan yang sudah dijalankan.'),
      _ => '',
    };

String _targetLabel(String id, BuildContext context) => switch (id) {
      'dns_lookup' => context.tr('Domain to resolve'),
      'tls_inspector' => context.tr('HTTPS hostname'),
      'http_headers' => context.tr('Website origin'),
      _ => context.tr('Target domain'),
    };

String _resultSummary(String summary, BuildContext context) {
  final dns = RegExp(r'^Resolved (\d+) address(?:es)?\.$').firstMatch(summary);
  if (dns != null) {
    final count = dns.group(1)!;
    return AppLocalizations.of(context).locale.languageCode == 'id'
        ? 'Menemukan $count alamat IP.'
        : 'Resolved $count address${count == '1' ? '' : 'es'}.';
  }
  final tls = RegExp(r'^TLS handshake succeeded; certificate expires (.+)\.$').firstMatch(summary);
  if (tls != null) return '${context.tr('Handshake TLS berhasil; sertifikat berlaku hingga')}: ${tls.group(1)}';
  final http = RegExp(r'^Received HTTP (\d+) and inspected (\d+) response headers\.$').firstMatch(summary);
  if (http != null) return '${context.tr('Respons HTTP')} ${http.group(1)} · ${http.group(2)} ${context.tr('header diperiksa')}';
  final analyzer = RegExp(r'^(\d+) finding(s?) across (\d+) check(s?)\.$').firstMatch(summary);
  if (analyzer != null && AppLocalizations.of(context).locale.languageCode == 'id') {
    return '${analyzer.group(1)} temuan dari ${analyzer.group(3)} pemeriksaan.';
  }
  return context.tr(summary);
}

String _resultDetail(String detail, BuildContext context) {
  const labels = {
    'Subject: ': 'Subjek: ',
    'Issuer: ': 'Penerbit: ',
    'Valid from: ': 'Berlaku sejak: ',
    'Valid until: ': 'Berlaku hingga: ',
    'Days remaining: ': 'Sisa hari: ',
    'Trust validation: passed by the device TLS stack': 'Validasi kepercayaan: lolos pada sistem TLS perangkat',
    'The response contained no headers.': 'Respons tidak berisi header.',
    'Redirect returned; it was not followed.': 'Server mengirim pengalihan; pengalihan tidak diikuti.',
  };
  for (final entry in labels.entries) {
    if (detail.startsWith(entry.key)) return '${context.tr(entry.value)}${detail.substring(entry.key.length)}';
  }
  final summarySeparator = detail.indexOf(': ');
  if (summarySeparator > 0) {
    final toolId = detail.substring(0, summarySeparator);
    if (toolId == 'dns_lookup' || toolId == 'tls_inspector' || toolId == 'http_headers' || toolId == 'response_analyzer') {
      return '${_toolName(toolId, context)}: ${_resultSummary(detail.substring(summarySeparator + 2), context)}';
    }
  }
  return context.tr(detail);
}

String _toolError(String error, BuildContext context) {
  for (final prefix in ['DNS lookup failed: ', 'Could not connect to HTTPS service: ', 'Could not reach HTTPS service: ']) {
    if (error.startsWith(prefix)) {
      return '${context.tr(switch (prefix) {
        'DNS lookup failed: ' => 'Pencarian DNS gagal',
        'Could not connect to HTTPS service: ' => 'Tidak dapat terhubung ke layanan HTTPS',
        _ => 'Layanan HTTPS tidak dapat dijangkau',
      })}: ${error.substring(prefix.length)}';
    }
  }
  return context.tr(error);
}

String _findingTitle(String title, BuildContext context) {
  final expiry = RegExp(r'^Certificate expires in (-?\d+) day\(s\)$').firstMatch(title);
  final isIndonesian = AppLocalizations.of(context).locale.languageCode == 'id';
  if (expiry != null && isIndonesian) return 'Sertifikat kedaluwarsa dalam ${expiry.group(1)} hari';
  final missingHeader = RegExp(r'^(.*) header not observed$').firstMatch(title);
  if (missingHeader != null && isIndonesian) return 'Header tidak ditemukan: ${missingHeader.group(1)}';
  return context.tr(title);
}

String _severityLabel(FindingSeverity severity, BuildContext context) => switch (severity) {
      FindingSeverity.high => context.tr('TINGGI'),
      FindingSeverity.medium => context.tr('SEDANG'),
      FindingSeverity.low => context.tr('RENDAH'),
      FindingSeverity.info => context.tr('INFO'),
    };

class ToolRunnerDialog extends StatefulWidget {
  const ToolRunnerDialog({super.key, required this.tool, required this.recentResults, this.orchestrator});

  final ToolDefinition tool;
  final List<ToolRunResult> recentResults;
  final ToolOrchestrator? orchestrator;

  @override
  State<ToolRunnerDialog> createState() => _ToolRunnerDialogState();
}

class _ToolRunnerDialogState extends State<ToolRunnerDialog> {
  final _targetController = TextEditingController();

  List<ToolRunResult> get _analysisInput {
    final checks = widget.recentResults.where((result) => result.toolId != 'response_analyzer').toList();
    if (checks.isEmpty) return const [];
    final latestTarget = checks.first.target;
    return checks.where((result) => result.target == latestTarget).toList();
  }
  late final _orchestrator = widget.orchestrator ?? ToolOrchestrator();
  bool _authorized = false;
  bool _running = false;
  bool _cancelRequested = false;
  RuntimeCancellationToken? _cancellationToken;
  String? _error;
  ToolRunResult? _result;

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAnalyzer = widget.tool.id == 'response_analyzer';
    return PopScope(
      canPop: !_running,
      child: AlertDialog(
      title: Text(_toolName(widget.tool.id, context)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_toolDescription(widget.tool.id, context), style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.4)),
              const SizedBox(height: 8),
              Text(
                'v${widget.tool.version} · ${widget.tool.license} · ${widget.tool.supportedPlatforms.join(', ')}',
                style: TextStyle(color: Colors.white.withValues(alpha: .52), fontSize: 11),
              ),
              if (widget.tool.dependencies.isNotEmpty)
                Text('${context.tr('Ketergantungan')}: ${widget.tool.dependencies.join(', ')}', style: const TextStyle(fontSize: 11)),
              if (!isAnalyzer) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _targetController,
                  enabled: !_running,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (_) => setState(() {
                    _authorized = false;
                    _error = null;
                    _result = null;
                  }),
                  decoration: InputDecoration(labelText: _targetLabel(widget.tool.id, context), hintText: context.tr('example.com')),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _authorized,
                  onChanged: _running ? null : (value) => setState(() => _authorized = value ?? false),
                  title: Text(context.tr('Saya memiliki target ini atau mendapat izin untuk memeriksanya.'), style: const TextStyle(fontSize: 13)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  _analysisInput.isEmpty
                      ? context.tr('Jalankan pemeriksaan DNS, TLS, atau header HTTP terlebih dahulu. Hasil sesi hanya disimpan sementara.')
                      : '${context.tr('Analisis lokal')} ${_analysisInput.length} ${context.tr('hasil untuk')} ${_analysisInput.first.target}.',
                  style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.4),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_toolError(_error!, context), style: const TextStyle(color: Colors.orangeAccent)),
              ],
              if (_result != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                Text(_resultSummary(_result!.summary, context), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('${_result!.target} · ${_result!.completedAt.toLocal()}', style: const TextStyle(fontSize: 11)),
                if (_result!.toolId != 'response_analyzer')
                  Text('${context.tr('Konfirmasi izin diterima')}: ${_result!.authorizationConfirmed} (${context.tr('pernyataan mandiri saja')})', style: const TextStyle(fontSize: 11)),
                for (final finding in _result!.findings) ...[
                  const SizedBox(height: 8),
                  Text('${context.tr(finding.confidence.name).toUpperCase()} · ${_severityLabel(finding.severity, context)} · ${_findingTitle(finding.title, context)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(context.tr(finding.recommendation), style: const TextStyle(fontSize: 12, height: 1.35)),
                ],
                if (_result!.details.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final detail in _result!.details.take(12))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SelectableText(_resultDetail(detail, context), style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_running)
          TextButton.icon(
            onPressed: _cancelRequested ? null : _cancel,
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(_cancelRequested ? context.tr('Stopping…') : context.tr('Cancel checks')),
          ),
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(_result),
          child: Text(_result == null ? context.tr('Batal') : context.tr('Simpan ke sesi')),
        ),
        FilledButton.icon(
          onPressed: _running || (isAnalyzer && _analysisInput.isEmpty) ? null : _run,
          icon: _running
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow_rounded),
          label: Text(_running ? context.tr('Memproses…') : isAnalyzer ? context.tr('Analisis hasil') : context.tr('Jalankan pemeriksaan')),
        ),
      ],
      ),
    );
  }

  Future<void> _run() async {
    final isAnalyzer = widget.tool.id == 'response_analyzer';
    if (!isAnalyzer && !_authorized) {
      setState(() => _error = 'Confirm that you own or are authorized to test this target.');
      return;
    }
    final cancellationToken = RuntimeCancellationToken();
    setState(() {
      _running = true;
      _cancelRequested = false;
      _cancellationToken = cancellationToken;
      _error = null;
      _result = null;
    });
    try {
      final result = await _orchestrator.execute(ToolInvocation(
        toolId: widget.tool.id,
        target: isAnalyzer ? (_analysisInput.isEmpty ? '' : _analysisInput.first.target) : _targetController.text,
        authorized: _authorized,
        priorResults: _analysisInput,
        cancellationToken: cancellationToken,
      ));
      if (mounted) setState(() => _result = result);
    } on RuntimeExecutionCancelled {
      if (mounted) setState(() => _error = context.tr('Check cancelled.'));
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _cancelRequested = false;
          _cancellationToken = null;
        });
      }
    }
  }

  void _cancel() {
    if (_cancelRequested) return;
    setState(() => _cancelRequested = true);
    _cancellationToken?.cancel();
  }
}
