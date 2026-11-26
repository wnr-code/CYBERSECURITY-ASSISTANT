import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/ai_provider_manager.dart';
import '../core/market_provider_manager.dart';
import '../l10n/app_localizations.dart';
import 'local_ai_diagnostic_test.dart';
import 'local_ai_model_install_action.dart';

class MarketProviderDialog extends StatefulWidget {
  const MarketProviderDialog({super.key, required this.providerId, required this.manager});
  final String providerId;
  final MarketProviderManager manager;

  @override
  State<MarketProviderDialog> createState() => _MarketProviderDialogState();
}

class _MarketProviderDialogState extends State<MarketProviderDialog> {
  final _secretController = TextEditingController();
  final _accountController = TextEditingController();
  bool _hideSecret = true;
  String? _message;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _accountController.text = widget.manager.cloudflareAccountId ?? '';
  }

  @override
  void dispose() {
    _secretController.clear();
    _secretController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.providerId) {
      'cloudflare' => 'Cloudflare configuration',
      'gemini' => 'Gemini configuration',
      _ => 'Local AI device status',
    };
    return AlertDialog(
      title: Text(context.tr(title)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (widget.providerId == 'cloudflare') _cloudflareContent(context),
            if (widget.providerId == 'gemini') _geminiContent(context),
            if (widget.providerId == 'local_ai') _localAiContent(context),
            if (widget.providerId != 'local_ai') ...[
              const SizedBox(height: 10),
              Text(context.tr('The secure-storage integration has not been verified on a real Android device in this workspace. Do not enter production secrets until device testing succeeds.'),
                  style: TextStyle(color: Colors.orangeAccent.withValues(alpha: .9), fontSize: 11, height: 1.4)),
            ],
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(context.tr(_message!), style: const TextStyle(color: Colors.orangeAccent)),
            ],
            if (_saving) const LinearProgressIndicator(),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: Text(context.tr('Close'))),
        if (widget.providerId == 'cloudflare' || widget.providerId == 'gemini')
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(context.tr('Save securely')),
          ),
      ],
    );
  }

  Widget _cloudflareContent(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('Cloud Infrastructure Provider · Cloudflare'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(context.tr('Create a dedicated API token in Cloudflare Dashboard → My Profile → API Tokens. Give it a clear name, scope resource access narrowly, set an expiry/IP filter where appropriate, review the summary, and copy the secret once.')),
        const SizedBox(height: 8),
        _officialLink(context, MarketProviderManager.cloudflareDocs),
        Text(context.tr('Cloudflare permission reference'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        _officialLink(context, MarketProviderManager.cloudflarePermissionsDocs),
        const SizedBox(height: 12),
        TextField(
          controller: _secretController,
          obscureText: _hideSecret,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 8192,
          decoration: InputDecoration(
            labelText: context.tr('Cloudflare API Token'),
            helperText: context.tr('Required: paste only the raw Cloudflare API token, without “Bearer ”. Account ID below is optional and does not replace the token.'),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hideSecret = !_hideSecret),
              icon: Icon(_hideSecret ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
          ),
        ),
        TextField(
          controller: _accountController,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 32,
          decoration: InputDecoration(
            labelText: context.tr('Account ID (optional)'),
            helperText: context.tr('Used only to filter the read-only zone listing. No write operation is available.'),
          ),
        ),
        const SizedBox(height: 4),
        Text(context.tr('Supported read-only capability: GET /user/tokens/verify, GET /accounts, GET /zones, and GET /zones/{zone_id}. Zone listing requires Zone Zone Read; access is tested separately from token verification.'),
            style: const TextStyle(fontSize: 12, height: 1.4)),
        const SizedBox(height: 8),
        _officialLink(context, MarketProviderManager.cloudflareAccountsApiDocs),
        _officialLink(context, MarketProviderManager.cloudflareZonesApiDocs),
        const SizedBox(height: 8),
        Text(context.tr('Least privilege: zone listing requires Zone → Zone → Read. The Account ID, when entered, only filters zone reads. DNS records and Workers APIs are not called; DNS changes and all other write operations are unsupported. Do not grant Edit permissions for this read-only feature.'),
            style: const TextStyle(fontSize: 12, height: 1.4)),
      ]);

  Widget _geminiContent(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('Cloud AI Provider · Google Gemini'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(context.tr('Create a Gemini API key in Google AI Studio. Restrict standard keys to the Gemini API when applicable; new AI Studio keys may use authorization-key controls. Never paste the key into a report or support message.')),
        const SizedBox(height: 8),
        Text(context.tr('Google AI Studio getting started'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        _officialLink(context, MarketProviderManager.geminiStudioGettingStartedDocs),
        _officialLink(context, MarketProviderManager.geminiKeyDocs),
        Text(context.tr('AI Studio documentation index (for AI/documentation tools)'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        _officialLink(context, MarketProviderManager.geminiAiStudioDocsIndex),
        const SizedBox(height: 10),
        TextField(
          controller: _secretController,
          obscureText: _hideSecret,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 512,
          decoration: InputDecoration(
            labelText: context.tr('Gemini API Key'),
            helperText: context.tr('Required: paste only the raw Gemini API key, not a URL or “Bearer ” value. It is saved on this device; saving sends no request.'),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hideSecret = !_hideSecret),
              icon: Icon(_hideSecret ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
          ),
        ),
        _infoLink(context, 'Configured model', '${GeminiAiProviderAdapter.modelId} · fixed by the existing Gemini adapter', MarketProviderManager.geminiModelsDocs),
        _infoLink(context, 'Pricing and quotas', 'Usage may be billed by model, input/output tokens, and optional tools. Check current rates and project billing before use.', MarketProviderManager.geminiPricingDocs),
        _infoLink(context, 'Data use', 'Google terms distinguish unpaid and paid services. Unpaid-service content may be used to improve Google products and may be reviewed by humans; paid-service prompts are not used for product improvement but may be logged for safety/legal purposes. Avoid sensitive, confidential, or personal data.', MarketProviderManager.geminiTermsDocs),
        const SizedBox(height: 8),
        Text(context.tr('Google warns that keys embedded in mobile/client applications can be extracted and abused. Secure storage reduces casual exposure but cannot make a user-owned client key impossible to extract. Each Assistant prompt and approved tool result still requires the existing explicit data-sharing confirmation; the connection test sends no prompt.'),
            style: const TextStyle(fontSize: 12, height: 1.4)),
        const SizedBox(height: 8),
        Text(context.tr('Google API terms describe Gemini API and AI Studio as developer services for professional or business use, not consumer use. Review the current terms and supported-region conditions for your use case before enabling it.'),
            style: const TextStyle(fontSize: 12, height: 1.4)),
      ]);

  Widget _localAiContent(BuildContext context) {
    final capabilities = widget.manager.localAiCapabilities;
    const gib = 1024 * 1024 * 1024;
    String size(int? value) => value == null ? context.tr('Unknown') : '${(value / gib).toStringAsFixed(2)} GiB';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.tr('On-device AI Provider · Local only'), style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Text(context.tr('Not Ready — the pinned model must first pass official Hugging Face metadata and complete on-device size/SHA-256 checks. Then test real local Chat and airplane-mode inference on this phone; no cloud fallback is used.')),
      const SizedBox(height: 12),
      Text(context.tr('Device capability (reported by Android)'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      Text(capabilities == null
          ? context.tr('Android capability probe is unavailable in this build or platform. RAM, free storage, and supported ABI have not been detected.')
          : '${context.tr('Supported ABIs')}: ${capabilities.supportedAbis.isEmpty ? context.tr('Unknown') : capabilities.supportedAbis.join(', ')}\n'
              '${context.tr('Total RAM')}: ${size(capabilities.totalRamBytes)} · ${context.tr('Available RAM')}: ${size(capabilities.availableRamBytes)}\n'
              '${context.tr('Internal storage free')}: ${size(capabilities.availableStorageBytes)} of ${size(capabilities.totalStorageBytes)}',
          style: const TextStyle(fontSize: 12, height: 1.5)),
      const SizedBox(height: 10),
      Text(context.tr('Pinned llama.cpp source commit: ea722948146befb23c9529c1ec7f59fb2f34911f. Source archive SHA-256: 05b362e97564f2e449440f13878c43991a13b6029214dbcb0d1b116b20365ec2.'),
          style: const TextStyle(fontSize: 12, height: 1.4)),
      _officialLink(context, MarketProviderManager.localAiRuntimeSource),
      _officialLink(context, MarketProviderManager.localAiBuildDocs),
      _officialLink(context, MarketProviderManager.localAiLicenseDocs),
      const SizedBox(height: 8),
      Text(context.tr('The pinned Qwen2.5 1.5B Instruct Q4_K_M candidate is expected to use Apache-2.0. Before native load, the app checks official repository metadata, revision, license, exact size, publisher SHA-256, and the complete downloaded file. Matching bytes do not guarantee freedom from all model risks.'),
          style: const TextStyle(fontSize: 12, height: 1.4)),
      _officialLink(context, MarketProviderManager.localAiModelsDocs),
      const SizedBox(height: 10),
      const LocalAiModelInstallAction(),
      const SizedBox(height: 10),
      LocalAiDiagnosticAction(status: widget.manager.statusFor('local_ai')),
      Text(context.tr('Unknown or insufficient ABI, RAM, storage, or model-integrity results remain blocked. Loading a verified model enables the requested Chat test but does not change the Local AI Not Ready status; offline inference still requires a physical airplane-mode check.'),
          style: const TextStyle(fontSize: 11, height: 1.4)),
    ]);
  }

  Widget _officialLink(BuildContext context, Uri uri) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: uri.toString()));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Official documentation URL copied.'))));
          },
          icon: const Icon(Icons.content_copy, size: 16),
          label: Text(uri.toString(), textAlign: TextAlign.left),
        ),
      );

  Widget _infoLink(BuildContext context, String title, String detail, Uri uri) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${context.tr(title)}: ${context.tr(detail)}', style: const TextStyle(fontSize: 12, height: 1.4)),
          _officialLink(context, uri),
        ]),
      );

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      if (widget.providerId == 'cloudflare') {
        await widget.manager.saveCloudflareConfiguration(token: _secretController.text, accountId: _accountController.text);
      } else {
        await widget.manager.saveGeminiApiKey(_secretController.text);
      }
      _secretController.clear();
      if (mounted) setState(() => _message = 'Credential saved securely. No provider request was made.');
    } on MarketProviderException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _message = '${context.tr('Secure storage failed')} (${error.code}). ${context.tr('The key was not sent to the provider.')}');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not save configuration in secure storage.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
