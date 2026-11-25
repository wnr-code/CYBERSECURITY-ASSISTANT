import 'package:material_ui/material_ui.dart';

import '../core/ai_assistant_coordinator.dart';
import '../core/ai_provider_manager.dart';
import '../core/ai_terminal_execution_bridge.dart';
import '../l10n/app_localizations.dart';
import 'ai_assistant_avatar.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    required this.providers,
    required this.coordinator,
    required this.reviewTool,
    required this.onOpenConnections,
    required this.onOpenTools,
  });

  final AiProviderManager providers;
  final AiAssistantCoordinator coordinator;
  final Future<bool> Function(AiTerminalToolProposal proposal) reviewTool;
  final VoidCallback onOpenConnections;
  final VoidCallback onOpenTools;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_AssistantBubble> _messages = [];
  List<String> _readyProviders = const [];
  String? _providerId;
  bool _loadingProviders = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    widget.providers.close();
    super.dispose();
  }

  Future<void> _loadProviders() async {
    final ready = <String>[];
    for (final id in widget.providers.registeredProviderIds) {
      if (await widget.providers.isReady(id)) ready.add(id);
    }
    if (!mounted) return;
    setState(() {
      _readyProviders = List.unmodifiable(ready);
      _providerId = ready.contains(_providerId) ? _providerId : ready.isEmpty ? null : ready.first;
      _loadingProviders = false;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_sending,
        child: Scaffold(
        appBar: AppBar(title: Text(context.tr('AI assistant module'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(children: [
              if (_loadingProviders) const LinearProgressIndicator(),
              if (!_loadingProviders && _readyProviders.isEmpty)
                Expanded(child: _notConfigured(context))
              else ...[
                if (_readyProviders.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(children: [
                      Expanded(child: DropdownButtonFormField<String>(
                        initialValue: _providerId,
                        decoration: InputDecoration(labelText: context.tr('AI provider')),
                        items: [for (final id in _readyProviders) DropdownMenuItem(value: id, child: Text(_providerName(id, context)))],
                        onChanged: _sending ? null : (value) => setState(() => _providerId = value),
                      )),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: context.tr('View connection center'),
                        onPressed: _navigateToConnections,
                        icon: const Icon(Icons.hub_outlined),
                      ),
                    ]),
                  ),
                Expanded(child: _messages.isEmpty
                    ? _welcome(context)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) => _messageTile(context, _messages[index]),
                      )),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(child: TextField(
                        controller: _inputController,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: AiAssistantCoordinator.maxPromptLength,
                        enabled: !_sending && _providerId != null,
                        decoration: InputDecoration(
                          hintText: context.tr('Ask a defensive security question…'),
                          border: const OutlineInputBorder(),
                          counterText: '',
                        ),
                        onSubmitted: (_) => _send(),
                      )),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending || _providerId == null ? null : _send,
                        icon: _sending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_rounded),
                        tooltip: context.tr('Send'),
                      ),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ),
        ),
      );

  Widget _notConfigured(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 20),
        const AiAssistantAvatar(key: ValueKey('assistant-avatar-not-connected'), diameter: 48),
        const SizedBox(height: 14),
        Text(context.tr('AI assistant is not connected'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(context.tr('Connect and configure a supported AI provider before sending a message. Prompts and approved tool results are sent to the selected provider. Do not send credentials, secrets, or personal data.'), style: const TextStyle(height: 1.5)),
        const SizedBox(height: 14),
        Wrap(spacing: 10, children: [
          OutlinedButton.icon(onPressed: _navigateToConnections, icon: const Icon(Icons.hub_outlined), label: Text(context.tr('View connection center'))),
          FilledButton.icon(onPressed: _navigateToTools, icon: const Icon(Icons.grid_view_rounded), label: Text(context.tr('Use local tools'))),
        ]),
        const SizedBox(height: 18),
        Text(context.tr('Only configured providers are shown. Local AI is available only when an on-device inference runtime is explicitly connected; there is no cloud fallback.'), style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 12, height: 1.45)),
      ]);

  Widget _welcome(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
        const AiAssistantAvatar(key: ValueKey('assistant-avatar-welcome'), diameter: 48),
        const SizedBox(height: 12),
        Text(context.tr('AI ASSISTANT'), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        Text(context.tr('AI assistance'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(context.tr('Ask defensive questions. The assistant can propose only registered network tools. Each proposal requires your review and the existing authorization confirmation before execution.'), style: const TextStyle(height: 1.5)),
        const SizedBox(height: 8),
        Text(context.tr('Tool results are structured app-runtime evidence; this application does not expose shell stdout, stderr, or process exit codes.'), style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 12, height: 1.45)),
        const SizedBox(height: 6),
        Text(context.tr('Chat display stays in this screen session only. Each send is a separate provider request; earlier messages are not resent and prompt text is not written to the local activity log.'), style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 11, height: 1.4)),
      ]);

  Widget _messageTile(BuildContext context, _AssistantBubble message) {
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 680),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: message.fromUser ? const Color(0xFF153B42) : const Color(0xFF151D31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText(message.text, style: const TextStyle(height: 1.45)),
        if (message.requestId != null) ...[
          const SizedBox(height: 7),
          Text('${context.tr('Request ID')}: ${message.requestId}', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: .55))),
        ],
        if (message.executionIds.isNotEmpty) ...[
          const SizedBox(height: 7),
          for (final id in message.executionIds)
            Text('${context.tr('Runtime Execution ID')}: $id', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: .62))),
        ],
      ]),
    );

    return Align(
      alignment: message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: message.fromUser
          ? bubble
          : Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              AiAssistantAvatar(key: ValueKey('assistant-avatar-${message.requestId ?? 'pending'}'), diameter: 36),
              const SizedBox(width: 8),
              Flexible(child: bubble),
            ]),
    );
  }

  Future<void> _send() async {
    final prompt = _inputController.text.trim();
    final provider = _providerId;
    if (prompt.isEmpty || provider == null || _sending) return;
    final approvedDataSharing = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('Confirm AI data sharing')),
        content: Text(dialogContext.tr(provider == 'gemini'
            ? 'This message and any approved tool results will be sent to Google Gemini using your key and may incur provider charges. Do not include passwords, API keys, secrets, or personal data. Tool execution is separately reviewed and authorized. Continue?'
            : 'This message and any approved tool results will be processed by the selected local AI runtime. Tool execution is separately reviewed and authorized. Continue?')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.tr('Batal'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.tr('Continue'))),
        ],
      ),
    );
    if (approvedDataSharing != true || !mounted) return;
    _inputController.clear();
    setState(() {
      _sending = true;
      _messages.add(_AssistantBubble(text: prompt, fromUser: true));
      _messages.add(_AssistantBubble(text: context.tr('Thinking…'), fromUser: false));
    });
    _scrollToEnd();
    try {
      final result = await widget.coordinator.submit(
        providerId: provider,
        prompt: prompt,
        reviewTool: widget.reviewTool,
        translate: (source) => context.tr(source),
      );
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _messages.add(_AssistantBubble(
          text: result.reply,
          fromUser: false,
          requestId: result.requestId,
          executionIds: result.toolExecutions.map((execution) => execution.executionId).whereType<String>().toList(),
        ));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _messages.add(_AssistantBubble(
          text: error is AiProviderException ? context.tr(error.message) : context.tr('The AI request failed. Sensitive diagnostic details were omitted.'),
          fromUser: false,
        ));
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigateToConnections() {
    Navigator.of(context).pop();
    widget.onOpenConnections();
  }

  void _navigateToTools() {
    Navigator.of(context).pop();
    widget.onOpenTools();
  }

  String _providerName(String id, BuildContext context) => switch (id) {
        'gemini' => 'Google Gemini',
        'local_ai' => context.tr('Local AI runtime'),
        _ => id,
      };
}

class _AssistantBubble {
  const _AssistantBubble({required this.text, required this.fromUser, this.requestId, this.executionIds = const []});
  final String text;
  final bool fromUser;
  final String? requestId;
  final List<String> executionIds;
}
