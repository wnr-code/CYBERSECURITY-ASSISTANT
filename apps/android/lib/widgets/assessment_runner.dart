import 'package:material_ui/material_ui.dart';

import '../core/tool_orchestrator.dart';
import '../core/security_tools.dart';
import '../core/tool_registry.dart';
import '../l10n/app_localizations.dart';

class AssessmentRunner extends StatefulWidget {
  const AssessmentRunner({super.key, required this.onResult});

  final ValueChanged<ToolRunResult> onResult;

  @override
  State<AssessmentRunner> createState() => _AssessmentRunnerState();
}

class _AssessmentRunnerState extends State<AssessmentRunner> {
  final _targetController = TextEditingController();
  final _orchestrator = ToolOrchestrator();
  final Set<String> _selected = {'dns_lookup', 'tls_inspector', 'http_headers'};
  final List<AssessmentCheckOutcome> _outcomes = [];
  bool _authorized = false;
  bool _allowPrivateNetwork = false;
  bool _running = false;
  String? _error;
  String? _assessmentTarget;

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checks = toolRegistry.where((tool) => tool.id != 'response_analyzer' && tool.status == ToolStatus.available);
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
              _error = null;
              _outcomes.clear();
              _assessmentTarget = null;
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
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _selected.contains(check.id),
              onChanged: _running
                  ? null
                  : (selected) => setState(() {
                        if (selected == true) {
                          _selected.add(check.id);
                        } else {
                          _selected.remove(check.id);
                        }
                      }),
              title: Text(_selectionName(check.id, context)),
              subtitle: Text(_toolDescription(check.id, context), style: const TextStyle(fontSize: 11)),
              controlAffinity: ListTileControlAffinity.leading,
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
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_running ? context.tr('Running selected checks…') : context.tr('Run assessment')),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
          if (_assessmentTarget != null || _outcomes.isNotEmpty) ...[
            const Divider(height: 24),
            Text('${context.tr('Assessment target')}: ${_assessmentTarget ?? _targetController.text.trim()}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (_running) Text(context.tr('Checks are running sequentially; these are live outcomes.'), style: const TextStyle(fontSize: 11)),
            Text(
              '${_outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.completed).length} ${context.tr('completed')} · ${_outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.failed).length} ${context.tr('failed')}',
              style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12),
            ),
            for (final outcome in _outcomes) _outcomeTile(outcome, context),
          ],
        ]),
      ),
    );
  }

  Widget _outcomeTile(AssessmentCheckOutcome outcome, BuildContext context) {
    final succeeded = outcome.status == AssessmentCheckStatus.completed;
    final result = outcome.result;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: Icon(succeeded ? Icons.check_circle_outline : Icons.error_outline, color: succeeded ? const Color(0xFF73F0C2) : Colors.orangeAccent),
      title: Text(_toolName(outcome.toolId, context), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(succeeded ? result!.summary : outcome.error ?? context.tr('Check failed'), maxLines: 2, overflow: TextOverflow.ellipsis),
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

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _outcomes.clear();
      _assessmentTarget = null;
    });
    try {
      final execution = await _orchestrator.runAssessment(
        target: _targetController.text,
        toolIds: _selected,
        authorized: _authorized,
        allowPrivateNetwork: _allowPrivateNetwork,
        onOutcome: (outcome) {
          if (!mounted) return;
          setState(() => _outcomes.add(outcome));
          if (outcome.result != null) widget.onResult(outcome.result!);
        },
      );
      if (mounted) setState(() => _assessmentTarget = execution.target);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
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
