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
  LocalAiModelManifest _selectedModel = LocalAiModelManifest.qwenQ4Km;
  LocalAiModelInstaller get _installer => LocalAiModelInstaller(manifest: _selectedModel);
  bool _busy = false;
  bool _checkingInstalled = true;
  bool _installed = false;
  bool _partialDownload = false;
  bool _modelLoaded = false;
  bool _userActionStarted = false;
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
      if (!mounted || _userActionStarted) return;
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
    _userActionStarted = true;
    setState(() { _busy = true; _checkingInstalled = false; _message = null; _verified = null; _progress = null; });
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
    _userActionStarted = true;
    setState(() { _busy = true; _checkingInstalled = false; _message = null; });
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

  Future<void> _showGuidance() => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.tr('Panduan & Informasi')),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(dialogContext.tr('Pilih satu model sesuai ruang penyimpanan dan kemampuan perangkat. Unduhan berjalan di latar depan dengan satu progres keseluruhan; Android menampilkan notifikasi dan menyediakan tindakan pembatalan. Model hanya dapat dimuat setelah revisi dan lisensi sumber resmi, ukuran file, serta SHA-256 seluruh file cocok. Setelah terputus, buka Local AI dan tap Download Model lagi; checkpoint dipakai bila server mendukung byte range, sedangkan server non-range memulai ulang transfer berurutan dengan aman. Pemeriksaan ini membuktikan identitas file, bukan keamanan perilaku model. Inferensi lokal tetap memerlukan pengujian langsung di perangkat.')),
              const SizedBox(height: 12),
              SelectableText('https://huggingface.co/${_selectedModel.repository}/tree/${_selectedModel.revision}', style: const TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () async {
              await Clipboard.setData(ClipboardData(text: 'https://huggingface.co/${_selectedModel.repository}/tree/${_selectedModel.revision}'));
              if (dialogContext.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Official source link copied.'))));
            }, child: Text(dialogContext.tr('Copy source link'))),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(dialogContext.tr('Close'))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final manifest = _selectedModel;
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
          DropdownButtonFormField<LocalAiModelManifest>(
            key: const ValueKey('local-ai-model-choice'),
            value: manifest,
            decoration: InputDecoration(labelText: context.tr('Model')),
            items: LocalAiModelManifest.candidates.map((candidate) => DropdownMenuItem(
              value: candidate,
              child: Text(candidate.displayName, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: _busy ? null : (candidate) {
              if (candidate == null) return;
              setState(() {
                _selectedModel = candidate;
                _installed = false;
                _partialDownload = false;
                _modelLoaded = false;
                _message = null;
                _verified = null;
                _progress = null;
                _checkingInstalled = true;
                _userActionStarted = false;
              });
              _refreshInstallState();
            },
          ),
          const SizedBox(height: 6),
          SelectableText('${manifest.repository}\n${manifest.fileName}\n${manifest.license} · ${manifest.fileSizeBytes} ${context.tr('bytes')}\n${context.tr('Revision')} ${manifest.revision}\nSHA-256 ${manifest.sha256Hex}', style: const TextStyle(fontSize: 11, height: 1.45)),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: _showGuidance,
            icon: const Icon(Icons.info_outline_rounded),
            label: Text(context.tr('Panduan & Informasi')),
          )),
          const SizedBox(height: 8),
          Text(_checkingInstalled ? context.tr('Checking for an installed verified model…') : _phaseLabel(context, progress?.phase), style: const TextStyle(fontSize: 12, height: 1.4)),
          if (_installed && _modelLoaded)
            Text(context.tr('This model is already verified, installed, and loaded. It stays available after reopening the app; no download is needed.'), style: const TextStyle(fontSize: 12, height: 1.4)),
          if (_installed && !_modelLoaded)
            Text(context.tr('An installed model file is present. Verify its pinned metadata and bytes before it can be loaded.'), style: const TextStyle(fontSize: 12, height: 1.4)),
          if (_partialDownload && !_installed)
            Text(context.tr('Partial data stays in private storage. Supported range downloads resume from saved checkpoints; non-range transfers restart safely.'), style: const TextStyle(fontSize: 12, height: 1.4)),
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
            onPressed: _busy || (_installed && _modelLoaded && _verified == true) ? null : _downloadVerifyAndLoad,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_installed && _modelLoaded ? Icons.verified_outlined : _partialDownload ? Icons.restart_alt_rounded : Icons.download_for_offline_outlined),
            label: Text(context.tr(_busy ? 'Working…' : 'Download Model')),
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
