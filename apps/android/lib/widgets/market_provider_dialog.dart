import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/ai_provider_manager.dart';
import '../core/market_provider_manager.dart';
import '../l10n/app_localizations.dart';

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
            helperText: context.tr('Token secret stays masked and is saved only in Android secure storage.'),
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
            helperText: context.tr('Only this app/device secure store receives the key; saving it sends no request.'),
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
    final gib = 1024 * 1024 * 1024;
    String size(int? value) => value == null ? context.tr('Unavailable') : '${(value / gib).toStringAsFixed(2)} GiB';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.tr('On-device AI Provider · Local only'), style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Text(context.tr('Status stays Not Ready: no LiteRT-LM runtime, model downloader, model storage manager, or installed model is integrated in this app. No request is sent to a cloud provider and no hidden fallback exists.')),
      const SizedBox(height: 12),
      Text(context.tr('Device capability (reported by Android)'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      Text(capabilities == null
          ? context.tr('Android capability probe is unavailable in this build or platform. RAM, free storage, and supported ABI have not been detected.')
          : '${context.tr('Supported ABIs')}: ${capabilities.supportedAbis.join(', ')}\n'
              '${context.tr('Total RAM')}: ${size(capabilities.totalRamBytes)} · ${context.tr('Available RAM')}: ${size(capabilities.availableRamBytes)}\n'
              '${context.tr('Internal storage free')}: ${size(capabilities.availableStorageBytes)} of ${size(capabilities.totalStorageBytes)}\n'
              '${context.tr('Installed local models')}: ${capabilities.installedModelCount} · ${context.tr('Inference runtime')}: ${capabilities.runtimeAvailable ? context.tr('Detected') : context.tr('Not installed')}',
          style: const TextStyle(fontSize: 12, height: 1.5)),
      const SizedBox(height: 10),
      Text(context.tr('Official Android inference runtime'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      _officialLink(context, MarketProviderManager.localAiDocs),
      const SizedBox(height: 5),
      Text(context.tr('Gemma model and memory reference'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      _officialLink(context, MarketProviderManager.localAiModelsDocs),
      const SizedBox(height: 8),
      Text(context.tr('Additional model discovery catalogs (reference only)'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(context.tr('Hugging Face and Kaggle are model discovery sources, not connected providers in this app. No catalog query, download, install, or model execution is implemented.'),
          style: const TextStyle(fontSize: 12, height: 1.4)),
      _officialLink(context, MarketProviderManager.localAiHuggingFaceModelsDocs),
      _officialLink(context, MarketProviderManager.localAiKaggleModelsDocs),
      const SizedBox(height: 8),
      Text(context.tr('Model candidates from Google documentation (not installed or offered for download here): Gemma 4 E2B mobile is listed at about 1.1 GB inference memory; E4B at about 2.5 GB. Quantization, runtime overhead, free storage, and device thermals affect compatibility. Exact model artifact storage sizes must be verified from the publisher before downloading.'),
          style: const TextStyle(fontSize: 12, height: 1.4)),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(context.tr('Test Inference · unavailable until runtime/model exist')),
      ),
      Text(context.tr('Model download, selection, deletion, and inference are unavailable rather than simulated.'),
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
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not save configuration in secure storage.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
