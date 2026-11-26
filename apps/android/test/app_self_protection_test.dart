import 'package:cybersecurity_assistant/core/app_self_protection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = AppSelfProtectionPolicy();

  test('tool execution permits only declared network capability and denies app/process access', () {
    policy.authorizeToolExecution(toolId: 'dns_lookup', requestedCapabilities: const {'network'});
    policy.authorizeToolExecution(toolId: 'response_analyzer', requestedCapabilities: const {});

    for (final denied in ['filesystemRead', 'filesystemWrite', 'processExecution', 'nativeCode', 'unknownCapability']) {
      expect(
        () => policy.authorizeToolExecution(toolId: 'dns_lookup', requestedCapabilities: {'network', denied}),
        throwsA(isA<AppSelfProtectionException>()),
        reason: 'Must deny capability $denied even when a UI caller asks for it.',
      );
    }
    expect(
      () => policy.authorizeToolExecution(toolId: '', requestedCapabilities: const {}),
      throwsA(isA<AppSelfProtectionException>()),
    );
  });

  test('Market accepts data packages only and cannot install runtime code or archives', () {
    policy.authorizeMarketPayload(payloadType: 'jsonData', dataOnly: true);
    policy.authorizeMarketPayload(payloadType: 'opaqueData', dataOnly: true);
    for (final type in ['archive', 'nativeExecutable', 'runtime', 'plugin', 'sourceCode']) {
      expect(
        () => policy.authorizeMarketPayload(payloadType: type, dataOnly: false),
        throwsA(isA<AppSelfProtectionException>()),
        reason: 'Must reject executable/source-like payload $type.',
      );
    }
  });

  test('APK source and security configuration mutation always requires a signed app update', () {
    expect(
      () => policy.denyAppCodeMutation(actor: 'Terminal'),
      throwsA(isA<AppSelfProtectionException>()),
    );
    expect(
      () => policy.denyAppCodeMutation(actor: 'AI provider'),
      throwsA(isA<AppSelfProtectionException>()),
    );
    expect(
      () => policy.denyAppCodeMutation(actor: 'Market'),
      throwsA(isA<AppSelfProtectionException>()),
    );
  });
}
