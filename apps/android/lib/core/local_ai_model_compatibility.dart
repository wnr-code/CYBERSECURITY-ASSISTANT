/// Fail-closed compatibility checks for a verified, installed local model.
/// This policy does not inspect files or infer support from a filename: the
/// Android runtime adapter must supply trustworthy metadata and runtime facts.
enum LocalAiCompatibilityState { compatible, incompatible, unknown }

enum LocalAiCompatibilityIssue {
  runtimeUnavailable,
  publisherMetadataUnverified,
  artifactDigestUnverified,
  artifactDigestUnknown,
  malformedArtifactDigest,
  bundleFormatUnknown,
  bundleFormatUnsupported,
  architectureUnknown,
  architectureUnsupported,
  tokenizerUnknown,
  tokenizerUnsupported,
  runtimeVersionUnknown,
  runtimeVersionUnsupported,
  deviceAbisUnknown,
  runtimeAbisUnknown,
  noCommonAbi,
  memoryRequirementUnknown,
  insufficientMemory,
  storageRequirementUnknown,
  insufficientStorage,
}

class LocalAiModelCompatibilityMetadata {
  const LocalAiModelCompatibilityMetadata({
    required this.bundleFormat,
    required this.architecture,
    required this.tokenizer,
    required this.minimumRuntimeVersion,
    required this.peakMemoryBytes,
    required this.installStorageBytes,
    required this.sha256,
    required this.publisherMetadataVerified,
    required this.artifactDigestVerified,
  });

  /// Exact container format reported by an authoritative artifact inspector.
  final String? bundleFormat;
  /// Model architecture/family as recognized by the runtime, not a filename guess.
  final String? architecture;
  /// Tokenizer and chat-template family required to prepare prompts correctly.
  final String? tokenizer;
  final String? minimumRuntimeVersion;
  /// Conservative peak RAM requirement, including runtime overhead.
  final int? peakMemoryBytes;
  /// Space required during install, including staging where applicable.
  final int? installStorageBytes;
  final String? sha256;
  /// True only after publisher metadata was authenticated/allowlisted.
  final bool publisherMetadataVerified;
  /// True only after the installed artifact matched the trusted digest.
  final bool artifactDigestVerified;
}

class LocalAiRuntimeCompatibilityProfile {
  const LocalAiRuntimeCompatibilityProfile({
    required this.available,
    required this.version,
    required this.bundleFormats,
    required this.architectures,
    required this.tokenizers,
    required this.supportedAbis,
  });

  final bool available;
  final String? version;
  final Set<String>? bundleFormats;
  final Set<String>? architectures;
  final Set<String>? tokenizers;
  final Set<String>? supportedAbis;
}

class LocalAiDeviceCompatibilityProfile {
  const LocalAiDeviceCompatibilityProfile({
    required this.supportedAbis,
    required this.availableRamBytes,
    required this.memoryHeadroomBytes,
    required this.availableStorageBytes,
  });

  final List<String>? supportedAbis;
  final int? availableRamBytes;
  /// RAM reserved for Android, the app, and uncertainty in runtime estimates.
  final int? memoryHeadroomBytes;
  final int? availableStorageBytes;
}

class LocalAiCompatibilityReport {
  LocalAiCompatibilityReport(this.state, Iterable<LocalAiCompatibilityIssue> issues)
      : issues = Set.unmodifiable(issues);

  final LocalAiCompatibilityState state;
  final Set<LocalAiCompatibilityIssue> issues;

  bool get isCompatible => state == LocalAiCompatibilityState.compatible;
}

class LocalAiModelCompatibilityChecker {
  const LocalAiModelCompatibilityChecker._();

  static LocalAiCompatibilityReport evaluate({
    required LocalAiModelCompatibilityMetadata model,
    required LocalAiRuntimeCompatibilityProfile runtime,
    required LocalAiDeviceCompatibilityProfile device,
  }) {
    final issues = <LocalAiCompatibilityIssue>{};
    if (!runtime.available) issues.add(LocalAiCompatibilityIssue.runtimeUnavailable);
    if (!model.publisherMetadataVerified) issues.add(LocalAiCompatibilityIssue.publisherMetadataUnverified);
    if (!model.artifactDigestVerified) issues.add(LocalAiCompatibilityIssue.artifactDigestUnverified);
    final digest = model.sha256?.trim();
    if (digest == null || digest.isEmpty) {
      issues.add(LocalAiCompatibilityIssue.artifactDigestUnknown);
    } else if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(digest)) {
      issues.add(LocalAiCompatibilityIssue.malformedArtifactDigest);
    }

    _checkCapability(
      value: model.bundleFormat,
      supported: runtime.bundleFormats,
      unknownIssue: LocalAiCompatibilityIssue.bundleFormatUnknown,
      unsupportedIssue: LocalAiCompatibilityIssue.bundleFormatUnsupported,
      issues: issues,
    );
    _checkCapability(
      value: model.architecture,
      supported: runtime.architectures,
      unknownIssue: LocalAiCompatibilityIssue.architectureUnknown,
      unsupportedIssue: LocalAiCompatibilityIssue.architectureUnsupported,
      issues: issues,
    );
    _checkCapability(
      value: model.tokenizer,
      supported: runtime.tokenizers,
      unknownIssue: LocalAiCompatibilityIssue.tokenizerUnknown,
      unsupportedIssue: LocalAiCompatibilityIssue.tokenizerUnsupported,
      issues: issues,
    );

    final minVersion = _parseVersion(model.minimumRuntimeVersion);
    final runtimeVersion = _parseVersion(runtime.version);
    if (minVersion == null || runtimeVersion == null) {
      issues.add(LocalAiCompatibilityIssue.runtimeVersionUnknown);
    } else if (_compareVersions(runtimeVersion, minVersion) < 0) {
      issues.add(LocalAiCompatibilityIssue.runtimeVersionUnsupported);
    }

    final deviceAbis = device.supportedAbis;
    final runtimeAbis = runtime.supportedAbis;
    if (deviceAbis == null || deviceAbis.isEmpty) issues.add(LocalAiCompatibilityIssue.deviceAbisUnknown);
    if (runtimeAbis == null || runtimeAbis.isEmpty) issues.add(LocalAiCompatibilityIssue.runtimeAbisUnknown);
    if (deviceAbis != null && deviceAbis.isNotEmpty && runtimeAbis != null && runtimeAbis.isNotEmpty &&
        deviceAbis.toSet().intersection(runtimeAbis).isEmpty) {
      issues.add(LocalAiCompatibilityIssue.noCommonAbi);
    }

    final peakMemory = model.peakMemoryBytes;
    final availableMemory = device.availableRamBytes;
    final headroom = device.memoryHeadroomBytes;
    if (peakMemory == null || peakMemory <= 0 || availableMemory == null || availableMemory < 0 || headroom == null || headroom < 0) {
      issues.add(LocalAiCompatibilityIssue.memoryRequirementUnknown);
    } else if (availableMemory <= headroom || availableMemory - headroom < peakMemory) {
      issues.add(LocalAiCompatibilityIssue.insufficientMemory);
    }

    final installBytes = model.installStorageBytes;
    final availableStorage = device.availableStorageBytes;
    if (installBytes == null || installBytes <= 0 || availableStorage == null || availableStorage < 0) {
      issues.add(LocalAiCompatibilityIssue.storageRequirementUnknown);
    } else if (availableStorage < installBytes) {
      issues.add(LocalAiCompatibilityIssue.insufficientStorage);
    }

    final hasHardFailure = issues.any(_isIncompatibility);
    final state = hasHardFailure
        ? LocalAiCompatibilityState.incompatible
        : issues.isNotEmpty
            ? LocalAiCompatibilityState.unknown
            : LocalAiCompatibilityState.compatible;
    return LocalAiCompatibilityReport(state, issues);
  }

  static void _checkCapability({
    required String? value,
    required Set<String>? supported,
    required LocalAiCompatibilityIssue unknownIssue,
    required LocalAiCompatibilityIssue unsupportedIssue,
    required Set<LocalAiCompatibilityIssue> issues,
  }) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty || supported == null) {
      issues.add(unknownIssue);
      return;
    }
    if (!supported.map((item) => item.trim().toLowerCase()).contains(normalized)) {
      issues.add(unsupportedIssue);
    }
  }

  static List<int>? _parseVersion(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(value.trim());
    if (match == null) return null;
    final parts = <int>[];
    for (var index = 1; index <= 3; index++) {
      final part = int.tryParse(match.group(index)!);
      if (part == null) return null;
      parts.add(part);
    }
    return parts;
  }

  static int _compareVersions(List<int> left, List<int> right) {
    for (var index = 0; index < 3; index++) {
      final compared = left[index].compareTo(right[index]);
      if (compared != 0) return compared;
    }
    return 0;
  }

  static bool _isIncompatibility(LocalAiCompatibilityIssue issue) => switch (issue) {
        LocalAiCompatibilityIssue.runtimeUnavailable ||
        LocalAiCompatibilityIssue.malformedArtifactDigest ||
        LocalAiCompatibilityIssue.bundleFormatUnsupported ||
        LocalAiCompatibilityIssue.architectureUnsupported ||
        LocalAiCompatibilityIssue.tokenizerUnsupported ||
        LocalAiCompatibilityIssue.runtimeVersionUnsupported ||
        LocalAiCompatibilityIssue.noCommonAbi ||
        LocalAiCompatibilityIssue.insufficientMemory ||
        LocalAiCompatibilityIssue.insufficientStorage => true,
        _ => false,
      };
}
