import 'security_tools.dart';
import 'tool_registry.dart';

class ToolInvocation {
  const ToolInvocation({
    required this.toolId,
    required this.target,
    required this.authorized,
    this.priorResults = const [],
  });

  final String toolId;
  final String target;
  final bool authorized;
  final List<ToolRunResult> priorResults;
}

class ToolOrchestrationException implements Exception {
  const ToolOrchestrationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The only dispatch boundary for model- or UI-originated tool requests.
/// It accepts typed registry IDs only: no free-form shell or executable input.
class ToolOrchestrator {
  ToolOrchestrator({SecurityTools? tools}) : _tools = tools ?? SecurityTools();
  final SecurityTools _tools;

  Future<ToolRunResult> execute(ToolInvocation invocation) async {
    final definition = toolById(invocation.toolId);
    if (definition == null || definition.status != ToolStatus.available) {
      throw const ToolOrchestrationException('Requested tool is not available in the local registry.');
    }

    switch (definition.id) {
      case 'dns_lookup':
        return await _tools.runDnsLookup(invocation.target, authorized: invocation.authorized);
      case 'tls_inspector':
        return await _tools.inspectTls(invocation.target, authorized: invocation.authorized);
      case 'http_headers':
        return await _tools.checkHttpHeaders(invocation.target, authorized: invocation.authorized);
      case 'response_analyzer':
        return _analyze(invocation);
    }
    throw const ToolOrchestrationException('Registry entry has no execution adapter.');
  }

  ToolRunResult _analyze(ToolInvocation invocation) {
    final checks = invocation.priorResults.where((result) => result.toolId != 'response_analyzer').toList();
    if (checks.isEmpty) {
      throw const ToolOrchestrationException('Run and save at least one local check before analysis.');
    }
    final target = invocation.target.isNotEmpty ? invocation.target : checks.first.target;
    final scopedResults = checks.where((result) => result.target == target).toList();
    if (scopedResults.isEmpty) {
      throw const ToolOrchestrationException('No saved results match the requested target.');
    }
    return _tools.analyze(scopedResults, target: target);
  }
}
