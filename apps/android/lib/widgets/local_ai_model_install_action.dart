import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/local_ai_model_installer.dart';
import '../l10n/app_localizations.dart';

class LocalAiModelInstallAction extends StatefulWidget {
  const LocalAiModelInstallAction({super.key});

  @override
  State<LocalAiModelInstallAction> createState() => _LocalAiModelInstallActionState();
}

class _LocalAiModelInstallActionState extends State<LocalAiModelInstallAction> {
  final _installer = LocalAiModelInstaller();
  bool _busy = false;
  String? _message;
  bool? _verified;

  Future<void> _chooseAndInstall() async {
    setState(() { _busy = true; _message = null; _verified = null; });
    try {
      final model = await _installer.chooseVerifyAndLoad();
      if (!mounted) return;
      if (model == null) {
        setState(() { _busy = false; _message = 'Model selection cancelled; nothing was installed.'; });
        return;
      }
      setState(() {
        _busy = false;
        _verified = true;
        _message = 'Model file verified and loaded: ${model.fileName} · ${model.sizeBytes} bytes · SHA-256 ${model.sha256Hex}. You can now select Local AI in Chat for a physical inference test.';
      });
    } on LocalAiModelInstallException catch (error) {
      if (mounted) setState(() { _busy = false; _verified = false; _message = error.message; });
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _verified = false;
          final safe = error.toString().replaceAll(RegExp(r'\s+'), ' ');
          _message = 'Model was not installed or loaded: ${safe.substring(0, safe.length.clamp(0, 240).toInt())}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const manifest = LocalAiModelManifest.qwenQ4Km;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('Install pinned GGUF model'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(context.tr('Download this exact file in your phone browser, then select it below. The app streams it into private storage and checks its exact byte count and SHA-256 before attempting native load. A matching digest checks identity only; it does not guarantee the model is free of all security or quality risks.'), style: const TextStyle(fontSize: 12, height: 1.45)),
          const SizedBox(height: 8),
          SelectableText('${manifest.repository}\n${manifest.fileName}\n${manifest.license} · ${manifest.fileSizeBytes} bytes\nRevision ${manifest.revision}\nSHA-256 ${manifest.sha256Hex}', style: const TextStyle(fontSize: 11, height: 1.45)),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: manifest.downloadUrl));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Pinned official download URL copied. Open it in your browser.'))));
            },
            icon: const Icon(Icons.content_copy, size: 16),
            label: Text(context.tr('Copy pinned download URL')),
          ),
          OutlinedButton.icon(
            key: const ValueKey('local-ai-install-model'),
            onPressed: _busy ? null : _chooseAndInstall,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.verified_outlined),
            label: Text(context.tr(_busy ? 'Verifying and loading model…' : 'Choose GGUF, verify, and load')),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            SelectableText(_message!, style: TextStyle(fontSize: 12, height: 1.45, color: _verified == false ? Theme.of(context).colorScheme.error : null)),
            if (_verified == false)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _message!));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Error details copied. Paste them into your support message if you want help.'))));
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(context.tr('Copy error details')),
              ),
          ],
        ]),
      ),
    );
  }
}
