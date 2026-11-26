import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/terminal_process_executor.dart';
import '../core/terminal_session_manager.dart';
import '../l10n/app_localizations.dart';

const _terminalMint = Color(0xFF73F0C2);
const _terminalSurface = Color(0xFF0B1220);

class FloatingTerminal extends StatefulWidget {
  const FloatingTerminal({
    super.key,
    required this.session,
    required this.executor,
    required this.onMinimize,
    required this.onExit,
    required this.onDrag,
  });

  final TerminalSessionManager session;
  final SafeTerminalProcessExecutor executor;
  final VoidCallback onMinimize;
  final VoidCallback onExit;
  final ValueChanged<Offset> onDrag;

  @override
  State<FloatingTerminal> createState() => _FloatingTerminalState();
}

class _FloatingTerminalState extends State<FloatingTerminal> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _input.text;
    if (value.trim().isEmpty || widget.session.status != TerminalSessionStatus.ready) return;
    _input.clear();
    final auditLabel = _auditLabel(value);
    await widget.session.submit(
      value,
      auditLabel: auditLabel,
      translate: (source) => context.tr(source),
      execute: (command) => widget.executor.execute(
        command,
        sessionStatus: widget.session.status,
        translate: (source) => context.tr(source),
      ),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        if (MediaQuery.of(context).disableAnimations) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        } else {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
        }
      }
    });
  }

  String _auditLabel(String input) {
    final words = input.trim().split(RegExp(r'\s+'));
    final first = words.isEmpty ? '' : words.first;
    return const {'help', 'status', 'tools', 'run', 'workspace'}.contains(first) ? first : 'rejected_input';
  }

  Future<void> _exit() async {
    if (widget.session.status == TerminalSessionStatus.running) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Exit terminal session?')),
        content: Text(context.tr('Exiting closes this session. The activity audit records action types; the workspace transcript is cleared when a new session starts.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Batal'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Exit'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await widget.session.exit();
    if (mounted) widget.onExit();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: _terminalSurface,
        elevation: 20,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => widget.onDrag(details.delta),
            child: Container(
              height: 48,
              padding: const EdgeInsets.only(left: 12, right: 4),
              decoration: const BoxDecoration(color: Color(0xFF142238)),
              child: Row(children: [
                const Icon(Icons.drag_indicator_rounded, size: 18, color: _terminalMint),
                const SizedBox(width: 6),
                Expanded(child: Text(context.tr('App Terminal · safe commands'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                _SessionStatus(status: widget.session.status),
                IconButton(
                  tooltip: context.tr('Minimize terminal'),
                  onPressed: widget.onMinimize,
                  icon: const Icon(Icons.minimize_rounded),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: context.tr('Exit terminal'),
                  onPressed: widget.session.status == TerminalSessionStatus.running ? null : _exit,
                  icon: const Icon(Icons.logout_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              ]),
            ),
          ),
          if (!widget.session.auditPersistenceAvailable)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              color: const Color(0xFF4A3215),
              child: Text(
                context.tr('Terminal audit storage is unavailable; tool execution is disabled.'),
                style: const TextStyle(color: Color(0xFFFFD18A), fontSize: 10, height: 1.3),
              ),
            ),
          Expanded(
            child: widget.session.entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(context.tr('Type help to view the commands supported by this app workspace.'),
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 12, height: 1.45)),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    itemCount: widget.session.entries.length,
                    itemBuilder: (context, index) {
                      final entry = widget.session.entries[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('› ${entry.command}', style: const TextStyle(color: _terminalMint, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w700)),
                          if (entry.output.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            SelectableText(entry.output,
                                style: TextStyle(
                                  color: entry.status == TerminalEntryStatus.failed
                                      ? Colors.orangeAccent
                                      : entry.status == TerminalEntryStatus.cancelled
                                          ? Colors.white60
                                          : Colors.white.withValues(alpha: .85),
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  height: 1.4,
                                )),
                          ] else if (entry.status == TerminalEntryStatus.running) ...[
                            const SizedBox(height: 4),
                            Text(context.tr('Memproses…'), style: const TextStyle(color: _terminalMint, fontSize: 11)),
                          ],
                        ]),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: Color(0xFF28364D)),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
            child: Row(children: [
              const Text('›', style: TextStyle(color: _terminalMint, fontFamily: 'monospace', fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: widget.session.status == TerminalSessionStatus.ready,
                  onSubmitted: (_) => _submit(),
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 256,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  decoration: InputDecoration(
                    hintText: context.tr('Enter an app command'),
                    counterText: '',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: context.tr('Run command'),
                onPressed: widget.session.status == TerminalSessionStatus.ready ? _submit : null,
                icon: const Icon(Icons.arrow_upward_rounded, color: _terminalMint),
              ),
            ]),
          ),
        ]),
      );
}

class MinimizedTerminal extends StatelessWidget {
  const MinimizedTerminal({super.key, required this.status, required this.onExpand, required this.onExit, required this.canExit});
  final TerminalSessionStatus status;
  final VoidCallback onExpand;
  final VoidCallback onExit;
  final bool canExit;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF142238),
        elevation: 18,
        borderRadius: BorderRadius.circular(28),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton.icon(
            onPressed: onExpand,
            icon: const Icon(Icons.terminal_rounded, color: _terminalMint),
            label: Text(context.tr(status == TerminalSessionStatus.running ? 'Terminal busy' : 'Terminal minimized')),
          ),
          IconButton(tooltip: context.tr('Exit terminal'), onPressed: canExit ? onExit : null, icon: const Icon(Icons.logout_rounded, size: 18)),
        ]),
      );
}

class _SessionStatus extends StatelessWidget {
  const _SessionStatus({required this.status});
  final TerminalSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      TerminalSessionStatus.ready => ('Terminal ready', _terminalMint),
      TerminalSessionStatus.running => ('Terminal busy', const Color(0xFF71B7FF)),
      TerminalSessionStatus.exited => ('Terminal exited', Colors.white54),
    };
    return Semantics(
      liveRegion: true,
      child: Text(context.tr(label), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }
}
