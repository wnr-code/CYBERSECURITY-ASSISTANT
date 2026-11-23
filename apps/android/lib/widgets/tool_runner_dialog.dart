import 'package:material_ui/material_ui.dart';

import '../core/security_tools.dart';
import '../core/tool_orchestrator.dart';
import '../core/tool_registry.dart';

class ToolRunnerDialog extends StatefulWidget {
  const ToolRunnerDialog({super.key, required this.tool, required this.recentResults});

  final ToolDefinition tool;
  final List<ToolRunResult> recentResults;

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
  final _orchestrator = ToolOrchestrator();
  bool _authorized = false;
  bool _running = false;
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
    return AlertDialog(
      title: Text(widget.tool.name),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.tool.description, style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.4)),
              const SizedBox(height: 8),
              Text(
                'v${widget.tool.version} · ${widget.tool.license} · ${widget.tool.supportedPlatforms.join(', ')}',
                style: TextStyle(color: Colors.white.withValues(alpha: .52), fontSize: 11),
              ),
              if (widget.tool.dependencies.isNotEmpty)
                Text('Dependencies: ${widget.tool.dependencies.join(', ')}', style: const TextStyle(fontSize: 11)),
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
                  decoration: const InputDecoration(labelText: 'Authorized domain', hintText: 'example.com'),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _authorized,
                  onChanged: _running ? null : (value) => setState(() => _authorized = value ?? false),
                  title: const Text('I own this target or have explicit permission to assess it.', style: TextStyle(fontSize: 13)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  _analysisInput.isEmpty
                      ? 'Run a DNS, TLS, or HTTP header check first. Results stay in memory for this session only.'
                      : 'This analyzes ${_analysisInput.length} result(s) for ${_analysisInput.first.target} locally on this device.',
                  style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.4),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
              ],
              if (_result != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                Text(_result!.summary, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('${_result!.target} · ${_result!.completedAt.toLocal()}', style: const TextStyle(fontSize: 11)),
                if (_result!.toolId != 'response_analyzer')
                  Text('Authorization confirmation accepted: ${_result!.authorizationConfirmed} (self-attestation only)', style: const TextStyle(fontSize: 11)),
                for (final finding in _result!.findings) ...[
                  const SizedBox(height: 8),
                  Text('${finding.severity.name.toUpperCase()} · ${finding.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(finding.recommendation, style: const TextStyle(fontSize: 12, height: 1.35)),
                ],
                if (_result!.details.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final detail in _result!.details.take(12))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SelectableText(detail, style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(_result),
          child: Text(_result == null ? 'Cancel' : 'Save to session'),
        ),
        FilledButton.icon(
          onPressed: _running || (isAnalyzer && _analysisInput.isEmpty) ? null : _run,
          icon: _running
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow_rounded),
          label: Text(_running ? 'Running…' : isAnalyzer ? 'Analyze results' : 'Run check'),
        ),
      ],
    );
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      final isAnalyzer = widget.tool.id == 'response_analyzer';
      final result = await _orchestrator.execute(ToolInvocation(
        toolId: widget.tool.id,
        target: isAnalyzer ? (_analysisInput.isEmpty ? '' : _analysisInput.first.target) : _targetController.text,
        authorized: _authorized,
        priorResults: _analysisInput,
      ));
      if (mounted) setState(() => _result = result);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}
