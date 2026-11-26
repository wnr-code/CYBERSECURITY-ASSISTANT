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
  bool _checkingInstalled = true;
  bool _installed = false;
  bool _partialDownload = false;
  bool _modelLoaded = false;
  String? _message;
  bool? _verified;
  LocalAiInstallProgress? _progress;
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _refreshInstallState();
  }

  Future<void> _refreshInstallState({bool preserveMessage = false}) async {
    try {
      final restored = await _installer.restoreVerifiedInstalledModel();
      final installed = await _installer.hasInstalledModelFile();
      final partial = await _installer.hasPartialDownload();
      if (!mounted) return;
      setState(() {
        _checkingInstalled = false;
        _installed = installed;
        _partialDownload = partial;
        _modelLoaded = restored != null;
        if (!preserveMessage) {
          if (restored != null) {
            _verified = true;
            _message = context.tr('A previously verified model was rechecked and restored from this phone.');
          } else if (installed) {
            _verified = null;
            _message = context.tr('An installed model file was found. Re-verify its official metadata and bytes to load it; the file will not be downloaded again if it matches.');
          } else if (partial) {
            _verified = null;
            _message = context.tr('An interrupted download checkpoint is saved. Retry will resume from the last received byte.');
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() { _checkingInstalled = false; });
    }
  }

  Future<void> _downloadVerifyAndLoad() async {
    setState(() { _busy = true; _message = null; _verified = null; _progress = null; });
    try {
      final restored = await _installer.restoreVerifiedInstalledModel();
      final model = restored ?? await _installer.downloadVerifyAndLoad(onProgress: (progress) {
        if (!mounted) return;
        final now = DateTime.now();
        if (progress.phase != LocalAiInstallPhase.downloading || now.difference(_lastPaint) >= const Duration(milliseconds: 250) || progress.fraction == 1) {
          _lastPaint = now;
          setState(() => _progress = progress);
        }
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _verified = true;
        _progress = const LocalAiInstallProgress(phase: LocalAiInstallPhase.complete);
        _installed = true;
        _partialDownload = false;
        _modelLoaded = true;
        _message = '${context.tr(restored != null ? 'Previously verified model restored from this phone' : 'Publisher metadata and downloaded GGUF verified and model loaded')}: ${model.fileName} · ${model.sizeBytes} ${context.tr('bytes')} · SHA-256 ${model.sha256Hex}. ${context.tr('You can now test a real prompt in Chat; no cloud fallback is used.')}';
      });
    } on LocalAiModelInstallException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _verified = false;
          _progress = const LocalAiInstallProgress(phase: LocalAiInstallPhase.failed);
          _message = '${context.tr('Download or installation failed safely. Check connection and storage, then retry. No unverified model was loaded.')}\n${context.tr('Technical detail')}: ${error.message}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _verified = false;
          _progress = const LocalAiInstallProgress(phase: LocalAiInstallPhase.failed);
          _message = context.tr('Download or installation failed safely. Check connection and storage, then retry. No unverified model was loaded.');
        });
      }
    }
    if (mounted) {
      final installed = await _installer.hasInstalledModelFile();
      final partial = await _installer.hasPartialDownload();
      if (mounted) setState(() { _installed = installed; _partialDownload = partial; });
    }
  }

  Future<void> _deleteModel() async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('Delete Local AI model?')),
        content: Text(dialogContext.tr('Remove the pinned model and any resumable partial download from this app on this phone?')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.tr('Delete model'))),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    setState(() { _busy = true; _message = null; });
    try {
      final removed = await _installer.deleteInstalledModel();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _installed = false;
        _partialDownload = false;
        _modelLoaded = false;
        _verified = null;
        _progress = null;
        _message = context.tr(removed ? 'Pinned model and partial download removed from this phone.' : 'No pinned model files were found on this phone.');
      });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _verified = false; _message = context.tr('Could not remove the pinned model from this phone.'); });
    }
  }

  String _phaseLabel(BuildContext context, LocalAiInstallPhase? phase) => switch (phase) {
        LocalAiInstallPhase.checkingPublisher => context.tr('Checking official publisher metadata…'),
        LocalAiInstallPhase.downloading => context.tr('Downloading pinned GGUF…'),
        LocalAiInstallPhase.verifying => context.tr('Verifying complete file size and SHA-256…'),
        LocalAiInstallPhase.loading => context.tr('Loading verified model into native runtime…'),
        LocalAiInstallPhase.complete => context.tr('Model verification and loading complete'),
        LocalAiInstallPhase.failed => context.tr('Operation failed safely. You can retry.'),
        null => context.tr('Ready to download the pinned model on this phone.'),
      };

  @override
  Widget build(BuildContext context) {
    const manifest = LocalAiModelManifest.qwenQ4Km;
    final progress = _progress;
    final fraction = progress?.fraction;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('Install pinned GGUF model'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(context.tr('The app first checks the official Hugging Face repository, publisher, immutable revision, license, exact file size, and publisher SHA-256. It then downloads only this model, hashes every byte saved on this phone, and loads it only if all checks match. A matching digest verifies identity, not every possible model risk.'), style: const TextStyle(fontSize: 12, height: 1.45)),
          const SizedBox(height: 8),
          SelectableText('${manifest.repository}\n${manifest.fileName}\n${manifest.license} · ${manifest.fileSizeBytes} ${context.tr('bytes')}\n${context.tr('Revision')} ${manifest.revision}\nSHA-256 ${manifest.sha256Hex}', style: const TextStyle(fontSize: 11, height: 1.45)),
          const SizedBox(height: 8),
          Text(_checkingInstalled ? context.tr('Checking for an installed verified model…') : _phaseLabel(context, progress?.phase), style: const TextStyle(fontSize: 12, height: 1.4)),
          if (_installed && _modelLoaded)
            Text(context.tr('This model is already verified, installed, and loaded. It stays available after reopening the app; no download is needed.'), style: const TextStyle(fontSize: 12, height: 1.4)),
          if (_installed && !_modelLoaded)
            Text(context.tr('An installed model file is present. Verify its pinned metadata and bytes before it can be loaded.'), style: const TextStyle(fontSize: 12, height: 1.4)),
          if (_partialDownload && !_installed)
            Text(context.tr('The partial download is kept privately. Resume continues from the last saved byte.'), style: const TextStyle(fontSize: 12, height: 1.4)),
          if (_busy) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: fraction),
            if (progress?.phase == LocalAiInstallPhase.downloading && progress!.totalBytes > 0) ...[
              const SizedBox(height: 5),
              Text('${progress.bytesReceived} / ${progress.totalBytes} ${context.tr('bytes')} (${((fraction ?? 0) * 100).toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 11)),
            ],
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('local-ai-install-model'),
            onPressed: _busy || _checkingInstalled || (_installed && _modelLoaded && _verified == true) ? null : _downloadVerifyAndLoad,
            icon: _busy || _checkingInstalled
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_installed && _modelLoaded ? Icons.verified_outlined : _partialDownload ? Icons.restart_alt_rounded : Icons.download_for_offline_outlined),
            label: Text(context.tr(
              _busy ? 'Working…' : _checkingInstalled ? 'Checking installed model…' :
              _installed && _modelLoaded ? 'Model already installed and loaded' :
              _installed ? 'Re-verify and load installed model' :
              _partialDownload ? 'Resume interrupted download' : 'Download, verify, and load on this phone',
            )),
          ),
          if (_installed || _partialDownload) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              key: const ValueKey('local-ai-delete-model'),
              onPressed: _busy ? null : _deleteModel,
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(context.tr('Delete installed model and partial download')),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            SelectableText(_message!, style: TextStyle(fontSize: 12, height: 1.45, color: _verified == false ? Theme.of(context).colorScheme.error : null)),
            if (_verified == false)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _message!));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Error details copied. Paste them into Diagnostics if you want help.'))));
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
