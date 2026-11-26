import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/local_ai_model_installer.dart';
import '../core/market_provider_manager.dart';
import '../l10n/app_localizations.dart';

/// An opt-in, staged diagnostic. It reports missing capabilities instead of
/// changing provider readiness or attempting any cloud fallback.
class LocalAiDiagnosticAction extends StatelessWidget {
  const LocalAiDiagnosticAction({super.key, required this.status});

  final ManagedProviderStatus status;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${context.tr('Diagnostic Test')} · ${context.tr(status.name)}',
        button: true,
        child: OutlinedButton.icon(
          key: const ValueKey('local-ai-diagnostic-test'),
          // Intentionally independent of provider readiness: diagnostics remain
          // available to explain exactly why Local AI is blocked.
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const _LocalAiDiagnosticDialog(),
          ),
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(context.tr('Diagnostic Test')),
        ),
      );
}

class _LocalAiDiagnosticDialog extends StatefulWidget {
  const _LocalAiDiagnosticDialog();

  @override
  State<_LocalAiDiagnosticDialog> createState() => _LocalAiDiagnosticDialogState();
}

class _LocalAiDiagnosticDialogState extends State<_LocalAiDiagnosticDialog> {
  static const _capabilityChannel = MethodChannel('org.cybersecurityassistant/local_ai_capabilities');
  static const _runtimeChannel = MethodChannel('org.cybersecurityassistant/local_ai_runtime');
  bool _running = false;
  String? _report;

  String _text(String english, String indonesian) =>
      AppLocalizations.of(context).locale.languageCode == 'id' ? indonesian : english;

  Future<void> _run() async {
    setState(() { _running = true; _report = null; });
    final results = <String>[];
    final pass = _text('PASS', 'LULUS');
    final blocked = _text('BLOCKED', 'TERBLOKIR');
    Map<Object?, Object?>? capabilities;
    Map<Object?, Object?>? runtime;
    try {
      final value = await _capabilityChannel.invokeMapMethod<Object?, Object?>('getDeviceCapabilities')
          .timeout(const Duration(seconds: 3));
      capabilities = value;
      final abis = value?['supportedAbis'];
      final arm64 = abis is List && abis.contains('arm64-v8a');
      results.add('${_text('Device ABI', 'ABI perangkat')}: ${arm64 ? pass : blocked} — ${abis is List ? abis.join(', ') : _text('probe unavailable', 'pemeriksaan tidak tersedia')}${arm64 ? '' : _text('; install the audited arm64-v8a APK on a compatible ARM64 phone.', '; pasang APK arm64-v8a yang sudah diaudit pada ponsel ARM64 yang kompatibel.')}');
      final ram = value?['availableRamBytes'];
      final storage = value?['availableStorageBytes'];
      final resourcesAvailable = ram is int && ram > 0 && storage is int && storage > 0;
      results.add('${_text('Resource telemetry', 'Telemetri sumber daya')}: ${resourcesAvailable ? pass : blocked} — ${_text('available RAM', 'RAM tersedia')}: ${ram is int ? '$ram ${_text('bytes', 'byte')}' : _text('unknown', 'tidak diketahui')}; ${_text('available storage', 'penyimpanan tersedia')}: ${storage is int ? '$storage ${_text('bytes', 'byte')}' : _text('unknown', 'tidak diketahui')}${resourcesAvailable ? '' : _text('; Android capability probe did not return positive RAM and storage values. Check device permissions/storage and retry.', '; pemeriksaan Android tidak mengembalikan nilai RAM dan penyimpanan yang valid. Periksa izin/penyimpanan perangkat lalu coba lagi.')}');
    } catch (error) {
      results.add('${_text('Device ABI/resources', 'ABI/sumber daya perangkat')}: $blocked — ${_text('Android capability probe failed', 'pemeriksaan kapabilitas Android gagal')} (${_safeError(error)}); ${_text('install the audited Android ARM64 APK and retry.', 'pasang APK Android ARM64 yang sudah diaudit lalu coba lagi.')}');
    }
    try {
      runtime = await _runtimeChannel.invokeMapMethod<Object?, Object?>('getDiagnosticStatus')
          .timeout(const Duration(seconds: 90));
      final loaded = runtime?['runtimeLoaded'] == true && runtime?['abi'] == 'arm64-v8a';
      results.add('${_text('Native/JNI load', 'Pemuatan Native/JNI')}: ${loaded ? pass : blocked} — ${runtime?['abi'] ?? _text('runtime status unavailable', 'status runtime tidak tersedia')}${loaded ? '' : _text('; install the source-native ARM64 APK; this APK/device did not report a loaded ARM64 JNI runtime.', '; pasang APK ARM64 dengan native hasil build sumber; APK/perangkat ini belum melaporkan runtime JNI ARM64 yang berhasil dimuat.')}');
    } catch (error) {
      results.add('${_text('Native/JNI load', 'Pemuatan Native/JNI')}: $blocked — ${_safeError(error)}; ${_text('install the source-native ARM64 APK after its CI audit passes.', 'pasang APK ARM64 native setelah audit CI lulus.')}');
    }
    if (runtime?['pinnedModelRevision'] is String) {
      results.add('${_text('Configured model pin (not independently verified)', 'Pin model yang dikonfigurasi (belum diverifikasi independen)')}: ${runtime?['pinnedModelRepository']} @ ${runtime?['pinnedModelRevision']} · ${runtime?['pinnedModelLicense']}. ${_text('Publisher metadata and actual GGUF bytes have not been independently verified.', 'Metadata penerbit dan byte GGUF sebenarnya belum diverifikasi secara independen.')}');
    }
    final name = runtime?['modelName'];
    final digest = runtime?['modelSha256'];
    const modelPin = LocalAiModelManifest.qwenQ4Km;
    final modelLoaded = LocalAiModelManifest.qwenArtifactIndependentlyVerified &&
        runtime?['modelLoaded'] == true && name == modelPin.fileName && digest == modelPin.sha256Hex;
    final installedCount = capabilities?['installedModelCount'];
    final inventory = runtime?['installedModels'];
    final modelInventory = inventory is List ? inventory.whereType<Map>().toList() : <Map>[];
    final inventoryLines = modelInventory.map((item) => '${item['fileName']}: ${item['sizeBytes']} ${_text('bytes', 'byte')}, SHA-256 ${item['sha256']} (${item['trusted'] == true ? _text('trusted', 'tepercaya') : _text('UNTRUSTED', 'TIDAK TEPERCAYA')})').join('; ');
    final trustedFileInstalled = LocalAiModelManifest.qwenArtifactIndependentlyVerified && modelInventory.any((item) =>
        item['fileName'] == modelPin.fileName && item['sizeBytes'] == modelPin.fileSizeBytes &&
        item['sha256'] == modelPin.sha256Hex && item['trusted'] == true);
    final noInventory = inventoryLines.isNotEmpty
        ? inventoryLines
        : '${installedCount is int ? installedCount : _text('unknown', 'tidak diketahui')} ${_text('installed model(s); no readable GGUF inventory', 'model terpasang; inventaris GGUF tidak dapat dibaca')}';
    results.add('${_text('Installed GGUF integrity', 'Integritas GGUF terpasang')}: ${trustedFileInstalled ? pass : blocked} — $noInventory${trustedFileInstalled ? '' : _text('; publisher metadata and the actual GGUF bytes have not been independently verified, so import and native loading remain disabled.', '; metadata penerbit dan byte GGUF sebenarnya belum diverifikasi secara independen, jadi impor dan pemuatan native tetap dinonaktifkan.')}');
    final loadDetail = modelLoaded
        ? _text('verified model is loaded in the runtime.', 'model terverifikasi sudah dimuat ke runtime.')
        : trustedFileInstalled
            ? _text('the verified file is installed but native model load has not completed.', 'file terverifikasi sudah terpasang tetapi belum dimuat ke runtime native.')
            : _text('a compatible model with an app-approved publisher digest is not loaded; model loading correctly fails closed.', 'model kompatibel dengan digest penerbit yang disetujui aplikasi belum dimuat; pemuatan model ditolak secara aman.');
    results.add('${_text('Model load', 'Pemuatan model')}: ${modelLoaded ? pass : blocked} — $loadDetail');
    if (modelLoaded) {
      try {
        final reply = await _runtimeChannel.invokeMethod<Object?>('complete', {
          'messages': [{'role': 'user', 'content': 'Reply with the word local.'}],
          'maxTokens': 16,
        }).timeout(const Duration(minutes: 2));
        final succeeded = reply is String && reply.trim().isNotEmpty;
        results.add('${_text('Local inference', 'Inferensi lokal')}: ${succeeded ? pass : blocked} — ${succeeded ? _text('non-empty response returned by the local runtime.', 'runtime lokal mengembalikan respons.') : _text('runtime returned no response; inspect the native runtime.', 'runtime tidak mengembalikan respons; periksa runtime native.')}');
      } catch (error) {
        results.add('${_text('Local inference', 'Inferensi lokal')}: $blocked — ${_safeError(error)}; ${_text('inspect device memory, model compatibility, and native logs. No cloud fallback is attempted.', 'periksa memori perangkat, kompatibilitas model, dan log native. Tidak ada fallback ke cloud.')}');
      }
    } else {
      results.add('${_text('Local inference', 'Inferensi lokal')}: $blocked — ${_text('no publisher-verified GGUF model is loaded; approved model provenance and SHA-256 are required.', 'belum ada model GGUF terverifikasi penerbit yang dimuat; asal model dan SHA-256 harus disetujui.')}');
    }
    results.add('${_text('Offline/no-cloud-fallback', 'Offline/tanpa fallback cloud')}: ${_text('MANUAL', 'MANUAL')} — ${_text('enable airplane mode, verify Wi-Fi and mobile data are off, then repeat a local inference test when a verified model is available. This diagnostic makes no network request and does not prove offline inference.', 'aktifkan mode pesawat, pastikan Wi-Fi dan data seluler mati, lalu ulangi uji inferensi lokal setelah model terverifikasi tersedia. Diagnostik ini tidak membuat permintaan jaringan dan belum membuktikan inferensi offline.')}');
    if (mounted) {
      final reportTitle = _text('Local AI physical-device diagnostic', 'Diagnostik Local AI di perangkat fisik');
      final readiness = _text('Readiness: NOT READY (diagnostics never change readiness)', 'Kesiapan: BELUM SIAP (diagnostik tidak mengubah status kesiapan)');
      setState(() { _report = '$reportTitle\nUTC: ${DateTime.now().toUtc().toIso8601String()}\n$readiness\n\n${results.join('\n')}'; _running = false; });
    }
  }

  String _safeError(Object error) {
    final normalized = error.toString().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.substring(0, normalized.length.clamp(0, 240).toInt());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('Local AI Diagnostic Test')),
        content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('Runs staged checks and reports blocked stages with remediation. It does not mark Local AI Ready or use cloud fallback. Offline proof requires the manual airplane-mode check on your phone.')),
          const SizedBox(height: 12),
          if (_running) const LinearProgressIndicator(),
          if (_report != null) SelectableText(_report!),
        ]))),
        actions: [
          TextButton(onPressed: _running ? null : () => Navigator.of(context).pop(), child: Text(context.tr('Close'))),
          if (_report != null) TextButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: _report!)); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Diagnostic report copied. Share it only if you choose.')))); }, icon: const Icon(Icons.copy), label: Text(context.tr('Copy report'))),
          FilledButton(onPressed: _running ? null : _run, child: Text(context.tr(_report == null ? 'Run diagnostic' : 'Run again'))),
        ],
      );
}
