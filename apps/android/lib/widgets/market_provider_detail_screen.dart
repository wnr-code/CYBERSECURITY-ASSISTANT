import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/ai_provider_manager.dart';
import '../core/market_provider_manager.dart';
import '../l10n/app_localizations.dart';
import 'market_brand_mark.dart';
import 'market_provider_dialog.dart';
import 'local_ai_diagnostic_test.dart';
import 'local_ai_model_install_action.dart';

class MarketProviderDetailScreen extends StatelessWidget {
  const MarketProviderDetailScreen({
    super.key,
    required this.providerId,
    required this.manager,
    this.onOpenCloudflareDashboard,
  });

  final String providerId;
  final MarketProviderManager manager;
  final VoidCallback? onOpenCloudflareDashboard;

  String get _name => switch (providerId) {
        'cloudflare' => 'Cloudflare',
        'gemini' => 'Gemini',
        _ => 'Local AI',
      };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: manager,
        builder: (context, _) {
          final status = manager.statusFor(providerId);
          return Scaffold(
            appBar: AppBar(title: Text(_name)),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                  children: [
                    _identityCard(context, status),
                    const SizedBox(height: 14),
                    if (providerId == 'cloudflare') _cloudflareDetails(context),
                    if (providerId == 'gemini') _geminiDetails(context),
                    if (providerId == 'local_ai') _localAiDetails(context),
                    const SizedBox(height: 14),
                    _actions(context, status),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _identityCard(BuildContext context, ManagedProviderStatus status) {
    final subtitle = switch (providerId) {
      'cloudflare' => context.tr('Cloud Infrastructure Provider'),
      'gemini' => context.tr('Cloud AI Provider'),
      _ => context.tr('Offline AI Provider'),
    };
    final detail = switch (status) {
      ManagedProviderStatus.installed => context.tr('Integration available; no credential is configured.'),
      ManagedProviderStatus.connected => context.tr(providerId == 'cloudflare'
          ? 'Cloudflare token is verified; account and zone read permissions are checked separately.'
          : 'Connection test succeeded for the implemented capability only.'),
      ManagedProviderStatus.disconnected => context.tr('Configured · not tested'),
      ManagedProviderStatus.error => context.tr('The latest provider test failed. Review the error and try again.'),
      ManagedProviderStatus.notReady => context.tr('Not Ready: the runtime, compatible model, and successful local inference are not all available.'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MarketBrandMark(providerId: providerId, diameter: 50),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12)),
            const SizedBox(height: 6),
            _statusBadge(context, status),
            if (providerId == 'gemini' || providerId == 'cloudflare') ...[
              const SizedBox(height: 7),
              Text(
                context.tr((providerId == 'gemini' ? manager.geminiConfigured : manager.cloudflareConfigured)
                    ? 'Credential saved on this device. Run Test Connection to verify it.'
                    : 'No credential saved yet. Open Configuration to enter it.'),
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ],
            const SizedBox(height: 8),
            Text(detail, style: const TextStyle(fontSize: 12, height: 1.4)),
            if (manager.messageFor(providerId) case final message?) ...[
              const SizedBox(height: 7),
              Text(context.tr(message), style: TextStyle(color: status == ManagedProviderStatus.error ? Colors.redAccent : Colors.white70, fontSize: 12)),
            ],
          ])),
        ]),
      ),
    );
  }

  Widget _cloudflareDetails(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _sectionCard(context, 'Account Configuration', [
          _detailLine(context, 'Account ID', _maskedAccountId(manager.cloudflareAccountId)),
          Text(context.tr('Account and zone reads are available after token verification. The optional Account ID is a local filter; discovered account identities come from the Cloudflare API response.'),
              style: const TextStyle(fontSize: 12, height: 1.4)),
          _referenceLink(context, 'Cloudflare List Accounts API', MarketProviderManager.cloudflareAccountsApiDocs),
        ]),
        const SizedBox(height: 10),
        _sectionCard(context, 'Permissions & Capabilities', [
          Text(context.tr('Read-only capabilities: GET /user/tokens/verify, GET /accounts, GET /zones, and GET /zones/{zone_id}. Each account or zone read is checked independently; verification alone does not reveal token scopes.'),
              style: const TextStyle(fontSize: 12, height: 1.4)),
          const SizedBox(height: 7),
          Text(context.tr('Zone listing requires Zone Zone Read. Account access is determined by the account endpoint response. DNS records, Workers, Pages, R2, Security, Analytics, and all write actions remain unavailable.'),
              style: const TextStyle(fontSize: 12, height: 1.4)),
          _referenceLink(context, 'Cloudflare List Zones API', MarketProviderManager.cloudflareZonesApiDocs),
          _referenceLink(context, 'Cloudflare Zone Details API', MarketProviderManager.cloudflareZoneDetailApiDocs),
        ]),
      ]);

  Widget _geminiDetails(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _sectionCard(context, 'API Configuration', [
          Text(context.tr('The API key is stored in Android secure storage. Saving it does not send a request.'),
              style: const TextStyle(fontSize: 12, height: 1.4)),
        ]),
        const SizedBox(height: 10),
        _sectionCard(context, 'Model Information', [
          Text('${context.tr('Configured model')}: ${GeminiAiProviderAdapter.modelId}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 5),
          Text(context.tr('The connection test checks model access without sending a user prompt.'),
              style: const TextStyle(fontSize: 12, height: 1.4)),
        ]),
        const SizedBox(height: 10),
        _sectionCard(context, 'Data & Privacy', [
          Text(context.tr('Conversation data is sent to Google only after provider-specific consent is saved locally. Revoke it in Privacy Settings to be asked again; tool execution requires separate review. Review current Google terms and pricing before use.'),
              style: const TextStyle(fontSize: 12, height: 1.4)),
        ]),
      ]);

  Widget _localAiDetails(BuildContext context) {
    final capability = manager.localAiCapabilities;
    String gib(int? bytes) => bytes == null ? context.tr('Unknown') : '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionCard(context, 'Device Compatibility', [
        Text(capability == null
            ? context.tr('Device compatibility is unknown because the Android capability probe is unavailable.')
            : '${context.tr('Supported ABIs')}: ${capability.supportedAbis.isEmpty ? context.tr('Unknown') : capability.supportedAbis.join(', ')}\n'
                '${context.tr('Available RAM')}: ${gib(capability.availableRamBytes)}\n'
                '${context.tr('Available storage')}: ${gib(capability.availableStorageBytes)}',
            style: const TextStyle(fontSize: 12, height: 1.5)),
        const SizedBox(height: 6),
        Text(context.tr('This device probe does not establish model compatibility. Bundle format, architecture, tokenizer, runtime support, peak memory, and storage requirements must also be verified.'),
            style: const TextStyle(fontSize: 12, height: 1.4)),
      ]),
      const SizedBox(height: 10),
      _sectionCard(context, 'Runtime Information', [
        Text(context.tr('The source-built CPU-only ARM64 APK passed CI static audit. This physical phone has reported a successful native/JNI load; GGUF loading and real inference still need testing.'),
            style: const TextStyle(fontSize: 12, height: 1.4)),
        _detailLine(context, 'Pinned llama.cpp source commit', MarketProviderManager.localAiRuntimeCommit),
        _detailLine(context, 'Official source archive SHA-256', MarketProviderManager.localAiSourceArchiveSha256),
        _detailLine(context, 'Native target', 'Android NDK · arm64-v8a · CPU-only · JNI'),
        _referenceLink(context, 'Pinned llama.cpp source', MarketProviderManager.localAiRuntimeSource),
        _referenceLink(context, 'Upstream Android build guide', MarketProviderManager.localAiBuildDocs),
        _referenceLink(context, 'Upstream license', MarketProviderManager.localAiLicenseDocs),
        Text(context.tr('The pinned archive and APK static audit establish build inputs and packaged JNI structure, not model compatibility or successful inference. The actual GGUF bytes must still pass the phone-side size/SHA-256 check.'),
            style: const TextStyle(fontSize: 12, height: 1.4)),
      ]),
      const SizedBox(height: 10),
      _sectionCard(context, 'Model Catalog', [
        Text(context.tr('The Qwen2.5 1.5B Instruct Q4_K_M model is pinned to the immutable Qwen repository revision and Apache-2.0 license shown below. The selected file is not trusted or loaded until its exact size and SHA-256 pass verification.'),
            style: const TextStyle(fontSize: 12, height: 1.4)),
        _referenceLink(context, 'Official pinned Qwen model repository', MarketProviderManager.localAiModelsDocs),
      ]),
      const SizedBox(height: 10),
      const LocalAiModelInstallAction(),
      const SizedBox(height: 10),
      _sectionCard(context, 'Storage Management', [
        Text(context.tr('The app imports only the pinned Qwen GGUF through the file picker. Missing, inaccessible, wrong-size, or wrong-hash files stop before native load. Keep the downloaded file until the private copy is verified.'),
            style: const TextStyle(fontSize: 12, height: 1.4)),
      ]),
      const SizedBox(height: 10),
      _sectionCard(context, 'Offline Inference Test', [
        Text(context.tr('After the pinned model is verified and loaded, test offline by sending a real Chat prompt with airplane mode enabled and Wi-Fi/mobile data off. This is a manual physical-device check; failure never falls back to cloud.'),
            style: const TextStyle(fontSize: 12, height: 1.4)),
        const SizedBox(height: 8),
        LocalAiDiagnosticAction(status: manager.statusFor('local_ai')),
      ]),
    ]);
  }

  Widget _actions(BuildContext context, ManagedProviderStatus status) {
    final configured = providerId == 'cloudflare'
        ? manager.cloudflareConfigured
        : providerId == 'gemini'
            ? manager.geminiConfigured
            : false;
    const connectLabel = 'Test Connection';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: manager.isBusy
                ? null
                : () => showDialog<void>(
                      context: context,
                      builder: (_) => MarketProviderDialog(providerId: providerId, manager: manager),
                    ),
            icon: const Icon(Icons.settings_outlined),
            label: Text(context.tr(providerId == 'local_ai' ? 'Device & model status' : providerId == 'gemini' ? 'API Configuration' : 'Account Configuration')),
          ),
          if (providerId != 'local_ai')
            FilledButton.icon(
              onPressed: manager.isBusy || !configured ? null : () => _testConnection(context),
              icon: manager.isBusy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering_rounded),
              label: Text(context.tr(connectLabel)),
            ),
          if (providerId == 'cloudflare' && status == ManagedProviderStatus.connected && onOpenCloudflareDashboard != null)
            OutlinedButton.icon(
              onPressed: onOpenCloudflareDashboard,
              icon: const Icon(Icons.dashboard_outlined),
              label: Text(context.tr('Open Dashboard')),
            ),
          if ((providerId == 'cloudflare' && manager.cloudflareConfigured) || (providerId == 'gemini' && manager.geminiConfigured))
            TextButton.icon(
              onPressed: manager.isBusy ? null : () => _disconnect(context),
              icon: const Icon(Icons.link_off_outlined),
              label: Text(context.tr('Disconnect')),
            ),
        ]),
      ),
    );
  }

  Future<void> _testConnection(BuildContext context) async {
    try {
      await manager.testConnection(providerId);
    } on MarketProviderException catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(error.message))));
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Provider test failed.'))));
    }
  }

  Future<void> _disconnect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Disconnect provider?')),
        content: Text('${context.tr('This deletes the saved credential for')} $_name ${context.tr('from secure storage. Other provider configurations are not changed.')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(context.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(context.tr('Disconnect'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await manager.disconnect(providerId);
    } on MarketProviderException catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(error.message))));
    }
  }

  Widget _referenceLink(BuildContext context, String label, Uri uri) => TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: uri.toString()));
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Official documentation URL copied.'))));
        },
        icon: const Icon(Icons.content_copy_rounded, size: 16),
        label: Text(context.tr(label)),
      );

  Widget _sectionCard(BuildContext context, String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr(title), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 9),
            ...children,
          ]),
        ),
      );

  Widget _detailLine(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text('${context.tr(label)}: $value', style: const TextStyle(fontSize: 12)),
      );

  Widget _statusBadge(BuildContext context, ManagedProviderStatus status) {
    final color = _statusColor(status);
    final label = context.tr(switch (status) {
      ManagedProviderStatus.installed => 'Available',
      ManagedProviderStatus.connected => providerId == 'cloudflare' ? 'Token verified' : 'Connected',
      ManagedProviderStatus.disconnected => 'Configured · not tested',
      ManagedProviderStatus.error => 'Error · retry',
      ManagedProviderStatus.notReady => 'Not Ready — integration in progress',
    });
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: .4))),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Color _statusColor(ManagedProviderStatus status) => switch (status) {
        ManagedProviderStatus.installed => const Color(0xFF8DB7FF),
        ManagedProviderStatus.connected => const Color(0xFF73F0C2),
        ManagedProviderStatus.disconnected => Colors.orangeAccent,
        ManagedProviderStatus.error => Colors.redAccent,
        ManagedProviderStatus.notReady => Colors.orangeAccent,
      };

  String _maskedAccountId(String? accountId) {
    final value = accountId?.trim() ?? '';
    if (value.length != 32) return '—';
    return '•••• •••• •••• ${value.substring(value.length - 4)}';
  }
}
