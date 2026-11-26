import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

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

  Future<void> _run() async {
    setState(() { _running = true; _report = null; });
    final results = <String>[];
    Map<Object?, Object?>? capabilities;
    Map<Object?, Object?>? runtime;
    try {
      final value = await _capabilityChannel.invokeMapMethod<Object?, Object?>('getDeviceCapabilities')
          .timeout(const Duration(seconds: 3));
      capabilities = value;
      final abis = value?['supportedAbis'];
      final arm64 = abis is List && abis.contains('arm64-v8a');
      results.add('Device ABI: ${arm64 ? 'PASS' : 'BLOCKED'} — ${abis is List ? abis.join(', ') : 'probe unavailable'}${arm64 ? '' : '; install the audited arm64-v8a APK on a compatible ARM64 phone.'}');
      final ram = value?['availableRamBytes'];
      final storage = value?['availableStorageBytes'];
      final resourcesAvailable = ram is int && ram > 0 && storage is int && storage > 0;
      results.add('Resource telemetry: ${resourcesAvailable ? 'PASS' : 'BLOCKED'} — available RAM: ${ram is int ? '$ram bytes' : 'unknown'}; available storage: ${storage is int ? '$storage bytes' : 'unknown'}${resourcesAvailable ? '' : '; Android capability probe did not return positive RAM and storage values. Check device permissions/storage and retry.'}');
    } catch (error) {
      results.add('Device ABI/resources: BLOCKED — Android capability probe failed (${_safeError(error)}); install the audited Android ARM64 APK and retry.');
    }
    try {
      runtime = await _runtimeChannel.invokeMapMethod<Object?, Object?>('getDiagnosticStatus')
          .timeout(const Duration(seconds: 90));
      final loaded = runtime?['runtimeLoaded'] == true && runtime?['abi'] == 'arm64-v8a';
      results.add('Native/JNI load: ${loaded ? 'PASS' : 'BLOCKED'} — ${runtime?['abi'] ?? 'runtime status unavailable'}${loaded ? '' : '; install the source-native ARM64 APK; this APK/device did not report a loaded ARM64 JNI runtime.'}');
    } catch (error) {
      results.add('Native/JNI load: BLOCKED — ${_safeError(error)}; install the source-native ARM64 APK after its CI audit passes.');
    }
    final name = runtime?['modelName'];
    final digest = runtime?['modelSha256'];
    final modelLoaded = runtime?['modelLoaded'] == true && name is String && digest is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(digest);
    final installedCount = capabilities?['installedModelCount'];
    final inventory = runtime?['installedModels'];
    final inventoryLines = inventory is List
        ? inventory.whereType<Map>().map((item) => '${item['fileName']}: ${item['sizeBytes']} bytes, SHA-256 ${item['sha256']} (${item['trusted'] == true ? 'trusted' : 'UNTRUSTED'})').join('; ')
        : '';
    results.add('Installed GGUF integrity: ${modelLoaded ? 'PASS' : 'BLOCKED'} — ${inventoryLines.isNotEmpty ? inventoryLines : '${installedCount is int ? installedCount : 'unknown'} installed model(s); no readable GGUF inventory'}; loaded model: ${modelLoaded ? '$name SHA-256 $digest' : 'none'}${modelLoaded ? '' : '; no publisher-approved digest is configured, so model loading is fail-closed. Do not use an unverified model.'}');
    results.add('Model load: ${modelLoaded ? 'PASS' : 'BLOCKED'} — ${modelLoaded ? 'verified model is loaded in the runtime.' : 'a compatible model with an app-approved publisher digest is not loaded; model loading correctly fails closed.'}');
    if (modelLoaded) {
      try {
        final reply = await _runtimeChannel.invokeMethod<Object?>('complete', {
          'messages': [{'role': 'user', 'content': 'Reply with the word local.'}],
          'maxTokens': 16,
        }).timeout(const Duration(minutes: 2));
        results.add('Local inference: ${reply is String && reply.trim().isNotEmpty ? 'PASS' : 'BLOCKED'} — ${reply is String && reply.trim().isNotEmpty ? 'non-empty response returned by the local runtime.' : 'runtime returned no response; inspect the native runtime.'}');
      } catch (error) {
        results.add('Local inference: BLOCKED — ${_safeError(error)}; inspect device memory, model compatibility, and native logs. No cloud fallback is attempted.');
      }
    } else {
      results.add('Local inference: BLOCKED — no publisher-verified GGUF model is loaded; approved model provenance and SHA-256 are required.');
    }
    results.add('Offline/no-cloud-fallback: MANUAL — enable airplane mode, verify Wi-Fi and mobile data are off, then repeat a local inference test when a verified model is available. This diagnostic makes no network request and does not prove offline inference.');
    if (mounted) setState(() { _report = 'Local AI physical-device diagnostic\nUTC: ${DateTime.now().toUtc().toIso8601String()}\nReadiness: NOT READY (diagnostics never change readiness)\n\n${results.join('\n')}'; _running = false; });
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
