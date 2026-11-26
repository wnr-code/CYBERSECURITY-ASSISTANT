import 'dart:io';

import 'package:cybersecurity_assistant/core/dart_security_tools_runtime.dart';
import 'package:cybersecurity_assistant/core/package_manager.dart';
import 'package:cybersecurity_assistant/core/runtime_manager.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:cybersecurity_assistant/core/tool_orchestrator.dart';
import 'package:cybersecurity_assistant/core/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory support;
  late RuntimeManager runtimeManager;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('tool-registry-test-');
    runtimeManager = RuntimeManager(
      environment: const RuntimeEnvironment(
        platform: 'Android',
        abi: 'arm64-v8a',
        deviceAbis: ['arm64-v8a'],
        androidApiLevel: 35,
        availableCapabilities: {RuntimeCapability.filesystemRead, RuntimeCapability.filesystemWrite, RuntimeCapability.network},
      ),
      store: MemoryRuntimeStateStore(),
      adapters: [DartSecurityToolsRuntime(tools: SecurityTools())],
      supportDirectoryProvider: () async => support,
    );
  });

  tearDown(() async {
    runtimeManager.dispose();
    if (await support.exists()) await support.delete(recursive: true);
  });

  test('only a registered, installed and healthy bundled adapter resolves ready', () async {
    final registry = ToolRegistry();
    final availability = await registry.resolve('dns_lookup', runtimeManager: runtimeManager);
    expect(availability.status, ToolStatus.ready);
    expect(runtimeManager.registered.single.license, isNull);
    expect(bundledMarketCatalog.first.license, isNull);
    expect(availability.adapterRegistered, isTrue);
    expect(availability.installed, isTrue);
    expect(registry.adapterFor('dns_lookup')?.runtimeId, DartSecurityToolsRuntime.runtimeId);
    expect((await registry.resolve('not_a_tool', runtimeManager: runtimeManager)).status, ToolStatus.unsupported);
  });

  test('an unverified Android ABI is not promoted to ready', () async {
    final incompatible = RuntimeManager(
      environment: const RuntimeEnvironment(
        platform: 'Android',
        abi: 'x86',
        deviceAbis: ['x86'],
        androidApiLevel: 35,
        availableCapabilities: {RuntimeCapability.filesystemRead, RuntimeCapability.filesystemWrite, RuntimeCapability.network},
      ),
      store: MemoryRuntimeStateStore(),
      adapters: [DartSecurityToolsRuntime(tools: SecurityTools())],
      supportDirectoryProvider: () async => support,
    );
    addTearDown(incompatible.dispose);
    final availability = await ToolRegistry().resolve('dns_lookup', runtimeManager: incompatible);
    expect(availability.status, ToolStatus.unsupported);
    expect(availability.installed, isFalse);
    expect(availability.ready, isFalse);
    expect(availability.reason, contains('device ABIs'));
  });

  test('Market metadata is linked declaratively without granting executable code', () async {
    final registry = ToolRegistry();
    final manager = MarketPackageManager(
      catalog: bundledMarketCatalog,
      environment: const CompatibilityEnvironment(platform: 'Android'),
      downloader: BundledAndHttpPackageDownloader(trustedDownloadHosts: const {}),
      supportDirectoryProvider: () async => support,
    );
    final availability = await registry.resolve(
      'dns_lookup',
      runtimeManager: runtimeManager,
      packageManager: manager,
    );
    expect(registry.marketPackageFor('dns_lookup')?.id, 'tool.dns-lookup');
    expect(availability.marketPackageStatus, PackageStatus.installed);
    expect(availability.ready, isTrue);
    expect(manager.canInstall(registry.marketPackageFor('dns_lookup')!), isFalse);
    await manager.initialize();
    expect(manager.canInstall(bundledMarketCatalog.first), isFalse);
    manager.dispose();
  });

  test('an unreviewed descriptor cannot register adapters in the registry', () {
    final registry = ToolRegistry();
    final descriptor = DartSecurityToolsRuntime(tools: SecurityTools()).descriptor;
    registry.synchronizeAdapters([descriptor], executableToolIds: const {});
    expect(registry.adapterFor('dns_lookup'), isNull);
  });

  test('assessment records unavailable selected checks as skipped partial outcomes', () async {
    final unavailableManager = RuntimeManager(
      environment: const RuntimeEnvironment(
        platform: 'Android',
        abi: 'arm64-v8a',
        deviceAbis: ['arm64-v8a'],
        androidApiLevel: 35,
        availableCapabilities: {RuntimeCapability.filesystemRead, RuntimeCapability.filesystemWrite, RuntimeCapability.network},
      ),
      store: MemoryRuntimeStateStore(),
      supportDirectoryProvider: () async => support,
    );
    addTearDown(unavailableManager.dispose);
    final execution = await ToolOrchestrator(runtimeManager: unavailableManager).runAssessment(
      target: 'example.com',
      toolIds: const ['dns_lookup'],
      authorized: true,
    );
    expect(execution.completedCount, 0);
    expect(execution.outcomes.single.status, AssessmentCheckStatus.skipped);
    expect(execution.outcomes.single.error, contains('not registered'));
  });

  test('invalid and duplicate metadata links are rejected', () {
    final registry = ToolRegistry();
    expect(
      () => registry.synchronizeMarketPackages([
        bundledMarketCatalog.first,
        bundledMarketCatalog.first,
      ]),
      throwsFormatException,
    );
  });
}
