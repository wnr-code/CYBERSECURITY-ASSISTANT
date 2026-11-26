import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/diagnostics.dart';
import '../core/local_ai_inference_runtime.dart';
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
  bool _savedLocally = false;
  String? _report;

  String _text(String english, String indonesian) =>
      AppLocalizations.of(context).locale.languageCode == 'id' ? indonesian : english;

  Future<void> _run() async {
    setState(() { _running = true; _report = null; _savedLocally = false; });
    final results = <String>[];
    final pass = _text('PASS', 'LULUS');
    final blocked = _text('BLOCKED', 'TERBLOKIR');
    Map<Object?, Object?>? capabilities;
    Map<Object?, Object?>? runtime;
    var nativeRuntimeAvailable = false;
    bool? airplaneModeEnabled;
    bool? hasInternetNetwork;
    bool? hasValidatedInternet;
    var inferenceSucceeded = false;
    var nativeInferenceEvidence = false;
    var isolationConfirmedBeforeInference = false;
    var networkModeClassification = _text('UNKNOWN / NOT PROVEN', 'TIDAK DIKETAHUI / BELUM TERBUKTI');
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
      airplaneModeEnabled = value?['airplaneModeEnabled'] as bool?;
      hasInternetNetwork = value?['hasInternetNetwork'] as bool?;
      hasValidatedInternet = value?['hasValidatedInternet'] as bool?;
      final isolationConfirmed = airplaneModeEnabled == true && hasInternetNetwork == false && hasValidatedInternet == false;
      isolationConfirmedBeforeInference = isolationConfirmed;
      networkModeClassification = isolationConfirmed
          ? _text('OFFLINE confirmed', 'OFFLINE terkonfirmasi')
          : airplaneModeEnabled == false && hasValidatedInternet == true
              ? _text('ONLINE (internet validated)', 'ONLINE (internet tervalidasi)')
              : _text('UNKNOWN / NOT PROVEN', 'TIDAK DIKETAHUI / BELUM TERBUKTI');
      results.add('${_text('Test network mode', 'Mode jaringan pengujian')}: $networkModeClassification');
      final networkDetail = isolationConfirmed
          ? _text('airplane mode is on and Android reports no internet-capable network.', 'mode pesawat aktif dan Android tidak melaporkan jaringan yang memiliki akses internet.')
          : airplaneModeEnabled == null || hasInternetNetwork == null || hasValidatedInternet == null
              ? _text('Android could not verify airplane/network status. Offline proof is unavailable.', 'Android tidak dapat memverifikasi status mode pesawat/jaringan. Bukti offline tidak tersedia.')
              : airplaneModeEnabled == true
                  ? _text('airplane mode is on, but an internet-capable network is still present.', 'mode pesawat aktif, tetapi jaringan yang memiliki akses internet masih terdeteksi.')
                  : _text('airplane mode is off. This run cannot count as an offline test.', 'mode pesawat tidak aktif. Pengujian ini tidak dihitung sebagai tes offline.');
      results.add('${_text('Offline network isolation', 'Isolasi jaringan offline')}: ${isolationConfirmed ? pass : blocked} — $networkDetail');
    } catch (error) {
      results.add('${_text('Device ABI/resources', 'ABI/sumber daya perangkat')}: $blocked — ${_text('Android capability probe failed', 'pemeriksaan kapabilitas Android gagal')} (${_safeError(error)}); ${_text('install the audited Android ARM64 APK and retry.', 'pasang APK Android ARM64 yang sudah diaudit lalu coba lagi.')}');
    }
    try {
      runtime = await _runtimeChannel.invokeMapMethod<Object?, Object?>('getDiagnosticStatus')
          .timeout(const Duration(seconds: 90));
      nativeRuntimeAvailable = runtime?['sourceCommit'] == AndroidLlamaCppInferenceRuntime.sourceCommit &&
          runtime?['runtimeLoaded'] == true && runtime?['abi'] == 'arm64-v8a' && runtime?['backend'] == 'cpu';
      final loaded = nativeRuntimeAvailable;
      results.add('${_text('Native/JNI load', 'Pemuatan Native/JNI')}: ${loaded ? pass : blocked} — ${runtime?['abi'] ?? _text('runtime status unavailable', 'status runtime tidak tersedia')}${loaded ? '' : _text('; install the source-native ARM64 APK; this APK/device did not report a loaded ARM64 JNI runtime.', '; pasang APK ARM64 dengan native hasil build sumber; APK/perangkat ini belum melaporkan runtime JNI ARM64 yang berhasil dimuat.')}');
    } catch (error) {
      results.add('${_text('Native/JNI load', 'Pemuatan Native/JNI')}: $blocked — ${_safeError(error)}; ${_text('install the source-native ARM64 APK after its CI audit passes.', 'pasang APK ARM64 native setelah audit CI lulus.')}');
    }
    final publisherMetadataVerified = runtime?['publisherMetadataVerified'] == true;
    if (runtime?['pinnedModelRevision'] is String) {
      results.add('${_text(publisherMetadataVerified ? 'Publisher metadata verified for loaded model' : 'Configured model pin (not yet verified)', publisherMetadataVerified ? 'Metadata penerbit terverifikasi untuk model yang dimuat' : 'Pin model yang dikonfigurasi (belum diverifikasi)')}: ${runtime?['pinnedModelRepository']} @ ${runtime?['pinnedModelRevision']} · ${runtime?['pinnedModelLicense']}.${publisherMetadataVerified ? '' : ' ${_text('Publisher metadata and actual GGUF bytes have not been independently verified.', 'Metadata penerbit dan byte GGUF sebenarnya belum diverifikasi secara independen.')}'}');
    }
    final name = runtime?['modelName'];
    final digest = runtime?['modelSha256'];
    const modelPin = LocalAiModelManifest.qwenQ4Km;
    final modelLoaded = publisherMetadataVerified &&
        runtime?['modelLoaded'] == true && name == modelPin.fileName && digest == modelPin.sha256Hex;
    final installedCount = capabilities?['installedModelCount'];
    final inventory = runtime?['installedModels'];
    final modelInventory = inventory is List ? inventory.whereType<Map>().toList() : <Map>[];
    final inventoryLines = modelInventory.map((item) => '${item['fileName']}: ${item['sizeBytes']} ${_text('bytes', 'byte')}, SHA-256 ${item['sha256']} (${item['trusted'] == true ? _text('trusted', 'tepercaya') : _text('UNTRUSTED', 'TIDAK TEPERCAYA')})').join('; ');
    final trustedFileInstalled = publisherMetadataVerified && modelInventory.any((item) =>
        item['fileName'] == modelPin.fileName && item['sizeBytes'] == modelPin.fileSizeBytes &&
        item['sha256'] == modelPin.sha256Hex && item['trusted'] == true);
    final noInventory = inventoryLines.isNotEmpty
        ? inventoryLines
        : '${installedCount is int ? installedCount : _text('unknown', 'tidak diketahui')} ${_text('installed model(s); no readable GGUF inventory', 'model terpasang; inventaris GGUF tidak dapat dibaca')}';
    final integrityFailure = publisherMetadataVerified
        ? _text('; no app-pinned model file passed the complete size and SHA-256 checks.', '; belum ada file model terpancang yang lulus pemeriksaan ukuran dan SHA-256 lengkap.')
        : _text('; official publisher metadata and actual GGUF bytes must pass the in-app download checks before native loading is allowed.', '; metadata penerbit resmi dan byte GGUF sebenarnya harus lulus pemeriksaan unduhan di dalam aplikasi sebelum pemuatan native diizinkan.');
    results.add('${_text('Installed GGUF integrity', 'Integritas GGUF terpasang')}: ${trustedFileInstalled ? pass : blocked} — $noInventory${trustedFileInstalled ? '' : integrityFailure}');
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
        inferenceSucceeded = reply is String && reply.trim().isNotEmpty;
        if (inferenceSucceeded) {
          try {
            runtime = await _runtimeChannel.invokeMapMethod<Object?, Object?>('getRuntimeStatus')
                .timeout(const Duration(seconds: 3));
            nativeInferenceEvidence = runtime?['inferenceSucceeded'] == true;
          } catch (_) {
            nativeInferenceEvidence = false;
          }
        }
        results.add('${_text('Local inference', 'Inferensi lokal')}: ${inferenceSucceeded ? pass : blocked} — ${inferenceSucceeded ? _text('a non-empty response was returned by the local runtime.', 'runtime lokal mengembalikan respons.') : _text('runtime returned no response; inspect the native runtime.', 'runtime tidak mengembalikan respons; periksa runtime native.')}');
        if (inferenceSucceeded) {
          results.add('${_text('Native inference evidence', 'Bukti inferensi native')}: ${nativeInferenceEvidence ? pass : blocked} — ${nativeInferenceEvidence ? _text('the runtime recorded the successful response.', 'runtime mencatat respons berhasil.') : _text('the runtime could not confirm its inference status.', 'runtime tidak dapat mengonfirmasi status inferensinya.')}');
        }
      } catch (error) {
        results.add('${_text('Local inference', 'Inferensi lokal')}: $blocked — ${_safeError(error)}; ${_text('inspect device memory, model compatibility, and native logs. No cloud fallback is attempted.', 'periksa memori perangkat, kompatibilitas model, dan log native. Tidak ada fallback ke cloud.')}');
      }
    } else {
      results.add('${_text('Local inference', 'Inferensi lokal')}: $blocked — ${_text('no publisher-verified GGUF model is loaded; approved model provenance and SHA-256 are required.', 'belum ada model GGUF terverifikasi penerbit yang dimuat; asal model dan SHA-256 harus disetujui.')}');
    }
    var isolationConfirmedAfterInference = false;
    if (inferenceSucceeded) {
      try {
        final after = await _capabilityChannel.invokeMapMethod<Object?, Object?>('getDeviceCapabilities')
            .timeout(const Duration(seconds: 3));
        airplaneModeEnabled = after?['airplaneModeEnabled'] is bool ? after!['airplaneModeEnabled'] as bool : null;
        hasInternetNetwork = after?['hasInternetNetwork'] is bool ? after!['hasInternetNetwork'] as bool : null;
        hasValidatedInternet = after?['hasValidatedInternet'] is bool ? after!['hasValidatedInternet'] as bool : null;
        isolationConfirmedAfterInference = airplaneModeEnabled == true && hasInternetNetwork == false && hasValidatedInternet == false;
      } catch (_) {
        isolationConfirmedAfterInference = false;
      }
    }
    if (inferenceSucceeded) {
      results.add('${_text('Network isolation after inference', 'Isolasi jaringan setelah inferensi')}: ${isolationConfirmedAfterInference ? pass : blocked} — ${isolationConfirmedAfterInference ? _text('airplane mode remained on with no internet-capable network.', 'mode pesawat tetap aktif tanpa jaringan internet.') : _text('airplane mode and offline network state were not verified after inference.', 'mode pesawat dan kondisi jaringan offline tidak terverifikasi setelah inferensi.')}');
    }
    final offlinePassed = modelLoaded && inferenceSucceeded && nativeInferenceEvidence && isolationConfirmedBeforeInference &&
        isolationConfirmedAfterInference && runtime?['offlineInferenceSucceeded'] == true;
    final readyAfterEvidence = nativeRuntimeAvailable && modelLoaded && inferenceSucceeded && nativeInferenceEvidence && offlinePassed;
    final offlineStatus = offlinePassed
        ? '${_text('PASS', 'LULUS')} — ${_text('a real local prompt returned a response while airplane mode was on and Android reported no internet-capable network.', 'prompt lokal nyata menghasilkan respons saat mode pesawat aktif dan Android melaporkan tidak ada jaringan internet.')}'
        : !modelLoaded
            ? '$blocked — ${_text('no verified model was loaded, so offline inference was not run.', 'model terverifikasi belum dimuat, jadi inferensi offline tidak dijalankan.')}'
            : !inferenceSucceeded
                ? '$blocked — ${_text('the local prompt did not return a response while network isolation was checked.', 'prompt lokal tidak menghasilkan respons saat isolasi jaringan diperiksa.')}'
                : !isolationConfirmedBeforeInference || !isolationConfirmedAfterInference
                    ? '$blocked — ${_text('this run did not confirm airplane mode plus no internet network before and after inference; rerun Diagnostics after enabling airplane mode and disabling Wi-Fi/mobile data.', 'mode pesawat dan tidak adanya jaringan internet belum terkonfirmasi sebelum dan sesudah inferensi; jalankan ulang Diagnostik setelah mengaktifkan mode pesawat dan mematikan Wi-Fi/data seluler.')}'
                    : '$blocked — ${_text('the native runtime did not record a verified offline inference result; inspect the native status and retry.', 'runtime native tidak mencatat hasil inferensi offline terverifikasi; periksa status native lalu coba lagi.')}';
    results.add('${_text('Offline inference/no-cloud-fallback', 'Inferensi offline/tanpa fallback cloud')}: $offlineStatus');
    final reportTitle = _text('Local AI physical-device diagnostic', 'Diagnostik Local AI di perangkat fisik');
    final readiness = readyAfterEvidence
        ? _text('Readiness: READY (real local inference and airplane-mode inference passed)', 'Kesiapan: SIAP (inferensi lokal nyata dan uji mode pesawat lulus)')
        : _text('Readiness: NOT READY (real inference and airplane-mode evidence are required)', 'Kesiapan: BELUM SIAP (bukti inferensi nyata dan mode pesawat diperlukan)');
    final report = '$reportTitle\nUTC: ${DateTime.now().toUtc().toIso8601String()}\n$readiness\n\n${results.join('\n')}';
    final localSummary = '$reportTitle · $readiness · ${_text('Network mode', 'Mode jaringan')}: $networkModeClassification · ${_text('Offline test', 'Tes offline')}: $offlineStatus · ${_text('Local inference', 'Inferensi lokal')}: ${inferenceSucceeded ? pass : blocked} · ${_text('Model load', 'Pemuatan model')}: ${modelLoaded ? pass : blocked} · ${_text('Publisher metadata', 'Metadata penerbit')}: ${publisherMetadataVerified ? pass : blocked}';
    var savedLocally = false;
    try {
      final reporter = DiagnosticReporter.active;
      if (reporter != null) {
        final saved = await reporter.record(
          StateError('Local AI physical-device diagnostic'),
          category: DiagnosticCategory.native,
          message: localSummary,
          component: 'local_ai_device_diagnostic',
          runtimeStatus: offlinePassed ? 'offline_test_passed' : 'not_ready',
          reproductionSteps: 'Opt-in Local AI diagnostic details: ${results.join(' | ')}. No user prompts or model contents are included. Review locally before any sharing.',
          requireManualReview: true,
        );
        savedLocally = reporter.storageWarning == null && reporter.reports.any((row) => row.id == saved.id);
      }
    } catch (_) {
      // The on-screen report remains available even if local diagnostic storage fails.
    }
    if (mounted) setState(() { _report = report; _running = false; _savedLocally = savedLocally; });
  }

  String _safeError(Object error) => sanitizeDiagnosticText(error.toString(), maxLength: 240);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('Local AI Diagnostic Test')),
        content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('Runs staged checks and reports blocked stages with remediation. It does not mark Local AI Ready or use cloud fallback. Offline proof requires the manual airplane-mode check on your phone.')),
          const SizedBox(height: 12),
          if (_running) const LinearProgressIndicator(),
          if (_report != null) ...[
            Text(context.tr(_savedLocally
                ? 'Saved locally in Diagnostics. Nothing is sent unless you review and approve it.'
                : 'Local saving was unavailable. The report is still shown here; nothing was sent.')),
            const SizedBox(height: 8),
            SelectableText(_report!),
          ],
        ]))),
        actions: [
          TextButton(onPressed: _running ? null : () => Navigator.of(context).pop(), child: Text(context.tr('Close'))),
          if (_report != null) TextButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: _report!)); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Diagnostic report copied. Share it only if you choose.')))); }, icon: const Icon(Icons.copy), label: Text(context.tr('Copy report'))),
          FilledButton(onPressed: _running ? null : _run, child: Text(context.tr(_report == null ? 'Run diagnostic' : 'Run again'))),
        ],
      );
}
