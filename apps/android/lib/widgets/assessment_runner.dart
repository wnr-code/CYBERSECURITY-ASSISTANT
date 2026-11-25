import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/assessment_execution_manager.dart';
import '../core/assessment_report_exporter.dart';
import '../core/package_manager.dart';
import '../core/tool_orchestrator.dart';
import '../core/tool_registry.dart';
import '../l10n/app_localizations.dart';

class AssessmentRunner extends StatefulWidget {
  const AssessmentRunner({
    super.key,
    required this.executionManager,
    this.packageManager,
  });

  final AssessmentExecutionManager executionManager;
  final MarketPackageManager? packageManager;

  @override
  State<AssessmentRunner> createState() => _AssessmentRunnerState();
}

class _AssessmentRunnerState extends State<AssessmentRunner> {
  final _targetController = TextEditingController();
  final Set<String> _selected = {};
  final Map<String, Future<ToolAvailability>> _readinessFutures = {};
  bool _authorized = false;
  bool _allowPrivateNetwork = false;
  bool _hideStoredOutcomes = false;
  String? _startError;
  String? _syncedRunId;

  AssessmentRunView? get _runView => widget.executionManager.currentRun;
  AssessmentRunView? get _activeRun => widget.executionManager.activeRun;
  List<AssessmentCheckOutcome> get _outcomes => _hideStoredOutcomes ? const [] : (_runView?.outcomes ?? const []);
  bool get _running => widget.executionManager.isRunning;
  bool get _cancelRequested => _activeRun?.cancellationRequested ?? false;
  String? get _error => _startError ?? (_hideStoredOutcomes ? null : _runView?.error);
  String? get _assessmentTarget => _hideStoredOutcomes ? null : _runView?.target;

  Future<ToolAvailability> _readinessFor(String id) =>
      _readinessFutures.putIfAbsent(id, () => widget.executionManager.availabilityForTool(id));

  @override
  void initState() {
    super.initState();
    final previousRun = widget.executionManager.currentRun;
    if (previousRun != null) {
      _syncedRunId = previousRun.runId;
      _targetController.text = previousRun.target;
      _selected.addAll(previousRun.selectedToolIds);
      _authorized = previousRun.authorized;
      _allowPrivateNetwork = previousRun.allowPrivateNetwork;
    }
    widget.executionManager.addListener(_executionChanged);
    widget.packageManager?.addListener(_refreshReadiness);
  }

  void _executionChanged() {
    final run = widget.executionManager.currentRun;
    if (run != null && run.runId != _syncedRunId) {
      _syncedRunId = run.runId;
      _targetController.text = run.target;
      _selected
        ..clear()
        ..addAll(run.selectedToolIds);
      _authorized = run.authorized;
      _allowPrivateNetwork = run.allowPrivateNetwork;
      _hideStoredOutcomes = false;
    }
    if (mounted) setState(() {});
  }

  void _refreshReadiness() {
    _readinessFutures.clear();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AssessmentRunner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.executionManager != widget.executionManager) {
      oldWidget.executionManager.removeListener(_executionChanged);
      widget.executionManager.addListener(_executionChanged);
      _readinessFutures.clear();
      final run = widget.executionManager.currentRun;
      if (run != null) {
        _syncedRunId = run.runId;
        _targetController.text = run.target;
        _selected
          ..clear()
          ..addAll(run.selectedToolIds);
        _authorized = run.authorized;
        _allowPrivateNetwork = run.allowPrivateNetwork;
      }
    }
    if (oldWidget.packageManager != widget.packageManager) {
      oldWidget.packageManager?.removeListener(_refreshReadiness);
      widget.packageManager?.addListener(_refreshReadiness);
      _readinessFutures.clear();
    }
  }

  @override
  void dispose() {
    widget.executionManager.removeListener(_executionChanged);
    widget.packageManager?.removeListener(_refreshReadiness);
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checks = toolRegistry.where((tool) => tool.id != 'response_analyzer');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.radar_rounded, color: Color(0xFF73F0C2)),
            const SizedBox(width: 9),
            Expanded(child: Text(context.tr('Security assessment'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            if (_running) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 6),
          Text(
            context.tr('Choose an authorized target and run multiple local checks in one assessment. Checks run sequentially; each outcome is reported separately.'),
            style: TextStyle(color: Colors.white.withValues(alpha: .7), height: 1.4, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _targetController,
            enabled: !_running,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) => setState(() {
              _authorized = false;
              _allowPrivateNetwork = false;
              _startError = null;
              _hideStoredOutcomes = true;
            }),
            decoration: InputDecoration(
              labelText: context.tr('Target domain or HTTPS URL'),
              hintText: 'https://example.com/api/endpoint',
              prefixIcon: const Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Text(context.tr('Checks to run'), style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final check in checks)
            FutureBuilder<ToolAvailability>(
              future: _readinessFor(check.id),
              builder: (context, snapshot) {
                final availability = snapshot.data;
                final status = availability?.status ?? (snapshot.hasError ? ToolStatus.error : null);
                final ready = status == ToolStatus.ready;
                final readinessText = status == null || ready ? null : '${context.tr('Unavailable')}: ${status.name}';
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: ready && _selected.contains(check.id),
                  onChanged: _running || !ready
                      ? null
                      : (selected) => setState(() {
                            if (selected == true) {
                              _selected.add(check.id);
                            } else {
                              _selected.remove(check.id);
                            }
                          }),
                  title: Text(_selectionName(check.id, context)),
                  subtitle: Text(
                    readinessText == null
                        ? _toolDescription(check.id, context)
                        : '${_toolDescription(check.id, context)} · $readinessText',
                    style: const TextStyle(fontSize: 11),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _authorized,
            onChanged: _running ? null : (value) => setState(() => _authorized = value ?? false),
            title: Text(context.tr('I own this target or have permission to assess it.'), style: const TextStyle(fontSize: 12)),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _allowPrivateNetwork,
            onChanged: _running ? null : (value) => setState(() => _allowPrivateNetwork = value ?? false),
            title: Text(context.tr('Allow local/private network targets'), style: const TextStyle(fontSize: 12)),
            subtitle: Text(
              context.tr('Off by default. Enable only when you are authorized to assess a loopback, private, or link-local system.'),
              style: const TextStyle(fontSize: 11),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _running || _selected.isEmpty ? null : _run,
              icon: _running
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_running
                  ? context.tr('Assessment already running')
                  : _selected.isEmpty
                      ? context.tr('Select at least one check')
                      : context.tr('Run assessment')),
            ),
            if (_running)
              OutlinedButton.icon(
                onPressed: _cancelRequested ? null : _cancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(_cancelRequested ? context.tr('Stopping…') : context.tr('Cancel checks')),
              ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
          if (_assessmentTarget != null || _outcomes.isNotEmpty) ...[
            const Divider(height: 24),
            Text('${context.tr('Assessment target')}: ${_assessmentTarget ?? _targetController.text.trim()}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (_running) Text(context.tr('Checks are running sequentially; these are live outcomes.'), style: const TextStyle(fontSize: 11)),
            Text(
              '${_outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.completed).length} ${context.tr('completed')} · ${_outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.failed).length} ${context.tr('failed')} · ${_outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.skipped).length} ${context.tr('skipped')} (partial)${_outcomes.any((outcome) => outcome.status == AssessmentCheckStatus.cancelled) ? ' · ${_outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.cancelled).length} ${context.tr('cancelled')}' : ''}',
              style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12),
            ),
            if (_outcomes.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _running ? null : _copyAssessmentReport,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(context.tr('Export assessment JSON')),
                ),
              ),
            for (final outcome in _outcomes) _outcomeTile(outcome, context),
          ],
        ]),
      ),
    );
  }

  Widget _outcomeTile(AssessmentCheckOutcome outcome, BuildContext context) {
    final succeeded = outcome.status == AssessmentCheckStatus.completed;
    final cancelled = outcome.status == AssessmentCheckStatus.cancelled;
    final skipped = outcome.status == AssessmentCheckStatus.skipped;
    final result = outcome.result;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: Icon(
        succeeded ? Icons.check_circle_outline : cancelled ? Icons.cancel_outlined : skipped ? Icons.hourglass_empty_rounded : Icons.error_outline,
        color: succeeded ? const Color(0xFF73F0C2) : cancelled ? Colors.white54 : Colors.orangeAccent,
      ),
      title: Text(_toolName(outcome.toolId, context), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(succeeded ? result!.summary : context.tr(outcome.error ?? 'Check failed'), maxLines: 2, overflow: TextOverflow.ellipsis),
      childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 10),
      children: [
        if (result != null) ...[
          for (final finding in result.findings)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${context.tr(finding.confidence.name).toUpperCase()} · ${finding.severity.name.toUpperCase()} · ${finding.title}', style: const TextStyle(fontSize: 12)),
              subtitle: Text(finding.recommendation, style: const TextStyle(fontSize: 11)),
            ),
          for (final detail in result.details.take(16))
            Align(alignment: Alignment.centerLeft, child: SelectableText(detail, style: const TextStyle(fontSize: 11))),
        ] else if (outcome.error != null)
          Align(alignment: Alignment.centerLeft, child: SelectableText(outcome.error!, style: const TextStyle(fontSize: 11))),
      ],
    );
  }

  Future<void> _copyAssessmentReport() async {
    final run = _runView;
    if (run == null || run.isRunning || run.outcomes.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('Copy assessment report?')),
        content: Text(dialogContext.tr(
          'The JSON includes the assessed target, check outcomes, evidence, and findings. The system clipboard may be readable by other apps. Share it only if you are comfortable disclosing this data.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.tr('Copy report'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await Clipboard.setData(ClipboardData(
        text: buildAssessmentReportJson(
          target: run.target,
          selectedToolIds: run.selectedToolIds,
          authorizationConfirmed: run.authorized,
          privateNetworkAllowed: run.allowPrivateNetwork,
          outcomes: run.outcomes,
        ),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Assessment report copied to clipboard.'))),
        );
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('System clipboard is unavailable.'))),
        );
      }
    }
  }

  void _run() {
    if (_running || _selected.isEmpty) return;
    setState(() {
      _startError = null;
      _hideStoredOutcomes = false;
    });
    final result = widget.executionManager.startAssessment(
      target: _targetController.text,
      toolIds: List<String>.of(_selected),
      authorized: _authorized,
      allowPrivateNetwork: _allowPrivateNetwork,
    );
    if (!result.accepted && mounted) {
      setState(() => _startError = context.tr('Another assessment is already running.'));
    }
  }

  void _cancel() {
    final run = _activeRun;
    if (run == null) return;
    widget.executionManager.cancelRun(run.runId);
  }

  String _selectionName(String id, BuildContext context) => switch (id) {
        'dns_lookup' => context.tr('DNS address records · A / AAAA'),
        'tls_inspector' => context.tr('TLS certificate and hostname validation'),
        'http_headers' => context.tr('HTTP headers and API response'),
        _ => id,
      };

  String _toolName(String id, BuildContext context) => switch (id) {
        'dns_lookup' => context.tr('DNS Lookup'),
        'tls_inspector' => context.tr('TLS Certificate Inspection'),
        'http_headers' => context.tr('HTTP Security Headers'),
        'response_analyzer' => context.tr('Security Response Analyzer'),
        _ => id,
      };

  String _toolDescription(String id, BuildContext context) => switch (id) {
        'dns_lookup' => context.tr('Resolve A and AAAA addresses using the device resolver.'),
        'tls_inspector' => context.tr('Validate the HTTPS handshake and inspect the peer certificate dates and issuer.'),
        'http_headers' => context.tr('Send one bounded HTTPS GET to the exact authorized path; redirects are not followed.'),
        _ => '',
      };
}
