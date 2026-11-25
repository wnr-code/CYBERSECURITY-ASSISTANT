/// App-level, non-configurable boundary between APK code and user/Market data.
/// This is a runtime authorization layer; Android's Package Manager remains the
/// authority for APK signature checks and signed-update replacement.
class AppSelfProtectionException implements Exception {
  const AppSelfProtectionException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AppSelfProtectionPolicy {
  const AppSelfProtectionPolicy();

  static const _toolExecutionCapabilities = {'network'};

  static const _forbiddenCapabilities = {
    'filesystemRead',
    'filesystemWrite',
    'processExecution',
    'nativeCode',
  };

  /// Tool execution is capability-deny-by-default. This invariant rejects
  /// file, process, native-code, and unknown capabilities independently of UI
  /// consent; PolicyEngine separately decides which tool IDs may run.
  void authorizeToolExecution({required String toolId, required Set<String> requestedCapabilities}) {
    if (toolId.trim().isEmpty || requestedCapabilities.any(_forbiddenCapabilities.contains)) {
      throw const AppSelfProtectionException(
        'Tool execution cannot read or write app files, start processes, or load native code.',
      );
    }
    if (!_toolExecutionCapabilities.containsAll(requestedCapabilities)) {
      throw const AppSelfProtectionException('Tool requested an unknown runtime capability.');
    }
  }

  /// Market may store declarative bytes only; a package never becomes executable
  /// code, a plugin, a runtime, or an app-source update.
  void authorizeMarketPayload({required String payloadType, required bool dataOnly}) {
    if (!dataOnly || (payloadType != 'jsonData' && payloadType != 'opaqueData')) {
      throw const AppSelfProtectionException('Market payload is not permitted to enter the executable app.');
    }
  }

  /// APK source, security policy, and bundled runtime code are immutable from
  /// Terminal, AI, tools, and Market. Changes require a developer-signed APK
  /// update verified by Android Package Manager.
  Never denyAppCodeMutation({required String actor}) {
    if (actor.trim().isEmpty) throw const AppSelfProtectionException('App code mutation actor is invalid.');
    throw const AppSelfProtectionException(
      'APK code and security configuration are immutable; use a developer-signed app update.',
    );
  }
}
