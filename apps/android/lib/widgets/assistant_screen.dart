import 'package:material_ui/material_ui.dart';

import '../core/ai_assistant_coordinator.dart';
import '../core/ai_data_sharing_consent.dart';
import '../core/ai_provider_manager.dart';
import '../core/capability_status.dart';
import '../core/market_provider_manager.dart';
import '../core/ai_terminal_execution_bridge.dart';
import '../l10n/app_localizations.dart';
import 'ai_assistant_avatar.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    required this.providers,
    required this.marketProviders,
    required this.consentStore,
    required this.coordinator,
    required this.reviewTool,
    required this.onOpenMarket,
    required this.onOpenTools,
  });

  final AiProviderManager providers;
  final MarketProviderManager marketProviders;
  final AiDataSharingConsentStore consentStore;
  final AiAssistantCoordinator coordinator;
  final Future<bool> Function(AiTerminalToolProposal proposal) reviewTool;
  final Future<void> Function() onOpenMarket;
  final VoidCallback onOpenTools;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final List<_AssistantBubble> _messages = [];
  List<String> _readyProviders = const [];
  final Set<String> _consentedProviders = {};
  String? _providerId;
  bool _loadingProviders = true;
  bool _providerInitializationFailed = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    widget.marketProviders.addListener(_marketProviderChanged);
    _loadProviders();
    _loadConsentStatuses();
  }

  void _marketProviderChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.marketProviders.removeListener(_marketProviderChanged);
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    // The provider manager is owned by MainShell and shared across routes.
    // Closing its HTTP client here breaks later Assistant visits.
    super.dispose();
  }

  Future<void> _loadProviders() async {
    var initializationFailed = false;
    try {
      await widget.marketProviders.initialize();
    } catch (_) {
      initializationFailed = true;
    }
    final ready = <String>[];
    for (final id in widget.providers.registeredProviderIds) {
      if (await widget.providers.isReady(id)) ready.add(id);
    }
    if (!mounted) return;
    setState(() {
      _providerInitializationFailed = initializationFailed;
      _readyProviders = List.unmodifiable(ready);
      _providerId = ready.contains(_providerId) ? _providerId : ready.isEmpty ? null : ready.first;
      _loadingProviders = false;
    });
  }

  Future<void> _loadConsentStatuses() async {
    final granted = <String>{};
    for (final providerId in AiDataSharingConsentStore.supportedProviderIds) {
      try {
        if (await widget.consentStore.hasConsent(providerId)) granted.add(providerId);
      } catch (_) {
        // Fail closed. Sending still re-reads consent and reports storage errors.
      }
    }
    if (!mounted) return;
    setState(() {
      _consentedProviders
        ..clear()
        ..addAll(granted);
    });
  }

  Future<void> _refreshConsentStatus(String providerId) async {
    try {
      final granted = await widget.consentStore.hasConsent(providerId);
      if (!mounted) return;
      setState(() {
        if (granted) {
          _consentedProviders.add(providerId);
        } else {
          _consentedProviders.remove(providerId);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _consentedProviders.remove(providerId));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_sending,
        child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('AI assistant module')),
          actions: [
            IconButton(
              key: const ValueKey('assistant-info-button'),
              tooltip: context.tr('Assistant information'),
              onPressed: _showAssistantInfo,
              icon: const Icon(Icons.info_outline_rounded),
            ),
          ],
        ),
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
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: DropdownButtonFormField<String>(
                          initialValue: _providerId,
                          decoration: InputDecoration(labelText: context.tr('AI provider')),
                          items: [for (final id in _readyProviders) DropdownMenuItem(value: id, child: Text(_providerName(id, context)))],
                          onChanged: _sending
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() => _providerId = value);
                                  _refreshConsentStatus(value);
                                },
                        )),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: context.tr('Manage AI providers in Market'),
                          onPressed: _navigateToMarket,
                          icon: const Icon(Icons.storefront_outlined),
                        ),
                      ]),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          context.tr(_geminiCapabilityStatus().sourceLabel),
                          key: const ValueKey('assistant-provider-capability-status'),
                          style: TextStyle(color: _geminiCapabilityStatus() == CapabilityStatus.connected ? const Color(0xFF73F0C2) : Colors.white70, fontSize: 11),
                        ),
                      ),
                      if (_providerId != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            context.tr(_consentedProviders.contains(_providerId) ? 'Data-sharing consent saved for this provider' : 'Consent required before first message to this provider'),
                            key: const ValueKey('assistant-consent-status'),
                            style: TextStyle(color: _consentedProviders.contains(_providerId) ? const Color(0xFF73F0C2) : Colors.white60, fontSize: 10),
                          ),
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
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                    child: Container(
                      key: const ValueKey('assistant-floating-composer'),
                      padding: const EdgeInsets.fromLTRB(16, 7, 7, 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF19243A),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white.withValues(alpha: .12)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .28), blurRadius: 20, offset: const Offset(0, 7))],
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocusNode,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: AiAssistantCoordinator.maxPromptLength,
                          enabled: !_sending && _providerId != null,
                          decoration: InputDecoration(
                            hintText: context.tr('Ask a defensive security question…'),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            counterText: '',
                          ),
                          onSubmitted: (_) => _send(),
                        )),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          onPressed: _sending || _providerId == null ? null : _send,
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF73F0C2), foregroundColor: const Color(0xFF081520)),
                          icon: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.arrow_upward_rounded),
                          tooltip: context.tr('Send'),
                        ),
                      ]),
                    ),
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
        AiAssistantAvatar(
          key: const ValueKey('assistant-avatar-not-connected'),
          diameter: 48,
          connectionVerified: _geminiCapabilityStatus() == CapabilityStatus.connected,
        ),
        const SizedBox(height: 14),
        Text(context.tr('AI assistant is not connected'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(context.tr('Connect a supported provider before sending a message. Conversation-sharing consent is saved once per provider and can be revoked in Privacy Settings. Tool actions require separate review. Never send credentials, secrets, or personal data.'), style: const TextStyle(height: 1.5)),
        const SizedBox(height: 14),
        Wrap(spacing: 10, children: [
          OutlinedButton.icon(onPressed: _navigateToMarket, icon: const Icon(Icons.storefront_outlined), label: Text(context.tr('Manage AI providers in Market'))),
          FilledButton.icon(onPressed: _navigateToTools, icon: const Icon(Icons.grid_view_rounded), label: Text(context.tr('Use local tools'))),
        ]),
        const SizedBox(height: 18),
        _capabilitySummary(context),
      ]);

  Widget _welcome(BuildContext context) => ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
        children: [
          Center(child: Column(children: [
            AiAssistantAvatar(
              key: const ValueKey('assistant-avatar-welcome'),
              diameter: 62,
              connectionVerified: _geminiCapabilityStatus() == CapabilityStatus.connected,
            ),
            const SizedBox(height: 14),
            Text(context.tr('What can I help you with?'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                context.tr('Choose an example to start, or write your own defensive security question below.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.5),
              ),
            ),
          ])),
          const SizedBox(height: 22),
          Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(context.tr('Example questions'), style: TextStyle(color: Colors.white.withValues(alpha: .64), fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _suggestionButton(context, 'Explain what this security finding means'),
              const SizedBox(height: 8),
              _suggestionButton(context, 'How can I safely check an HTTPS security header?'),
              const SizedBox(height: 8),
              _suggestionButton(context, 'What should I review before an authorized DNS check?'),
              const SizedBox(height: 14),
              _capabilitySummary(context),
              const SizedBox(height: 10),
              Center(child: Text(
                context.tr('Your message will be sent only to the selected provider after you approve data sharing.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: .52), fontSize: 11, height: 1.4),
              )),
            ]),
          )),
        ],
      );

  Widget _suggestionButton(BuildContext context, String suggestion) => OutlinedButton(
        key: ValueKey('assistant-suggestion-$suggestion'),
        onPressed: () => _useSuggestion(suggestion),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(children: [
          const Icon(Icons.auto_awesome_outlined, size: 17, color: Color(0xFF73F0C2)),
          const SizedBox(width: 10),
          Expanded(child: Text(context.tr(suggestion), style: const TextStyle(height: 1.35))),
          const Icon(Icons.north_west_rounded, size: 15),
        ]),
      );

  void _useSuggestion(String suggestion) {
    setState(() => _inputController.text = context.tr(suggestion));
    _inputFocusNode.requestFocus();
  }

  Future<void> _showAssistantInfo() => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.tr('Assistant information')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              _infoHeading(dialogContext, 'Integrated capabilities'),
              Text(dialogContext.tr('Gemini chat · model') + ': ${GeminiAiProviderAdapter.modelId}'),
              const SizedBox(height: 5),
              Text(dialogContext.tr('Only registered DNS, TLS, and HTTP checks can be proposed by the assistant.'), style: const TextStyle(height: 1.4)),
              const SizedBox(height: 14),
              _infoHeading(dialogContext, 'Privacy and consent'),
              Text(dialogContext.tr('Conversation data is sent only to the selected provider after you agree once for that provider. You can revoke consent in Privacy Settings.'), style: const TextStyle(height: 1.4)),
              const SizedBox(height: 7),
              Text(dialogContext.tr('Earlier messages are not automatically included in a later request. The current message and any necessary context for an approved tool step may be sent.'), style: const TextStyle(height: 1.4)),
              const SizedBox(height: 14),
              _infoHeading(dialogContext, 'Separate tool approval'),
              Text(dialogContext.tr('Every proposed tool action is shown for review, and the target still requires separate authorization before execution.'), style: const TextStyle(height: 1.4)),
              const SizedBox(height: 14),
              _infoHeading(dialogContext, 'Session storage'),
              Text(dialogContext.tr('Chat messages remain in this screen session and are not saved to the local activity log.'), style: const TextStyle(height: 1.4)),
            ])),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(dialogContext.tr('Close')))],
        ),
      );

  Widget _infoHeading(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(context.tr(title), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF73F0C2))),
      );

  CapabilityStatus _geminiCapabilityStatus() {
    if (_providerInitializationFailed) return CapabilityStatus.error;
    if (!_loadingProviders && !_readyProviders.contains('gemini') && widget.marketProviders.geminiConfigured) {
      return CapabilityStatus.error;
    }
    return switch (widget.marketProviders.statusFor('gemini')) {
      ManagedProviderStatus.connected => CapabilityStatus.connected,
      ManagedProviderStatus.error => CapabilityStatus.error,
      ManagedProviderStatus.disconnected => CapabilityStatus.configured,
      ManagedProviderStatus.installed => CapabilityStatus.available,
      ManagedProviderStatus.notReady => CapabilityStatus.unavailable,
    };
  }

  Widget _capabilitySummary(BuildContext context) => Card(
        color: const Color(0xFF151E31),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFFAA9AFF)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('Gemini chat · model') + ': ${GeminiAiProviderAdapter.modelId}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 3),
              Text(context.tr(_geminiCapabilityStatus().sourceLabel), style: TextStyle(color: Colors.white.withValues(alpha: .66), fontSize: 11)),
            ])),
          ]),
        ),
      );

  Widget _messageTile(BuildContext context, _AssistantBubble message) {
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 680),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: message.fromUser ? const Color(0xFF24545C) : const Color(0xFF182238),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(message.fromUser ? 22 : 7),
          bottomRight: Radius.circular(message.fromUser ? 7 : 22),
        ),
        border: Border.all(color: Colors.white.withValues(alpha: message.fromUser ? .12 : .08)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .14), blurRadius: 14, offset: const Offset(0, 4))],
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
              AiAssistantAvatar(
                key: ValueKey('assistant-avatar-${message.requestId ?? 'pending'}'),
                diameter: 36,
                connectionVerified: _geminiCapabilityStatus() == CapabilityStatus.connected,
              ),
              const SizedBox(width: 8),
              Flexible(child: bubble),
            ]),
    );
  }

  Future<bool?> _requestDataSharingConsent(String providerId) {
    var checked = false;
    final providerName = _providerName(providerId, context);
    final isLocalProvider = providerId == 'local_ai';
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('AI data-sharing consent')),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr(isLocalProvider
                  ? 'Messages sent to Local AI are processed on this device and are not sent to a cloud AI provider. If local inference is unavailable, the request fails without cloud fallback.'
                  : 'Messages you send are forwarded to the selected AI provider to generate a response. Data sent may include conversation text and necessary context.'), style: const TextStyle(height: 1.45)),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const ValueKey('ai-data-sharing-consent-checkbox'),
                contentPadding: EdgeInsets.zero,
                value: checked,
                onChanged: (value) => setDialogState(() => checked = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(context.tr(isLocalProvider
                    ? 'I understand and agree to process this conversation locally on this device.'
                    : 'I understand and agree to share conversation data with this provider.'), style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 7),
              Text(context.tr('Consent applies only to {provider}. Switching providers requires separate consent.').replaceFirst('{provider}', providerName), style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12, height: 1.4)),
              const SizedBox(height: 5),
              Text(context.tr('Consent can be revoked at any time in Privacy Settings.'), style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12, height: 1.4)),
              const SizedBox(height: 5),
              Text(context.tr('Tool execution and target authorization still require separate approval.'), style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12, height: 1.4)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.tr('Batal'))),
            FilledButton(
              onPressed: checked ? () => Navigator.of(dialogContext).pop(true) : null,
              child: Text(dialogContext.tr('Continue')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final prompt = _inputController.text.trim();
    final provider = _providerId;
    if (prompt.isEmpty || provider == null || _sending) return;

    bool consentGranted;
    try {
      consentGranted = await widget.consentStore.hasConsent(provider);
    } catch (_) {
      if (mounted) {
        setState(() => _consentedProviders.remove(provider));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Could not read AI privacy consent. No message was sent.'))));
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      if (consentGranted) {
        _consentedProviders.add(provider);
      } else {
        _consentedProviders.remove(provider);
      }
    });
    if (!consentGranted) {
      final accepted = await _requestDataSharingConsent(provider);
      if (accepted != true || !mounted) return;
      try {
        await widget.consentStore.grant(provider);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Could not save AI privacy consent. No message was sent.'))));
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _consentedProviders.add(provider);
      _inputController.clear();
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

  Future<void> _navigateToMarket() async {
    await widget.onOpenMarket();
    if (mounted) await _loadProviders();
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
