import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'activity_timeline.dart';
import 'security_tools.dart';

enum FindingStatus { open, inProgress, resolved, accepted, falsePositive }

class FindingRecord {
  const FindingRecord({
    required this.findingId,
    required this.fingerprint,
    required this.title,
    required this.category,
    required this.target,
    required this.severity,
    required this.confidence,
    required this.status,
    required this.description,
    required this.evidence,
    required this.sourceReportKeys,
    required this.recommendation,
    required this.firstSeen,
    required this.lastSeen,
    required this.createdAt,
    required this.updatedAt,
    required this.sourceTool,
    required this.assessmentId,
  });

  final String findingId;
  final String fingerprint;
  final String title;
  final String category;
  final String target;
  final FindingSeverity severity;
  final FindingConfidence confidence;
  final FindingStatus status;
  final String description;
  final List<String> evidence;
  final List<String> sourceReportKeys;
  final String recommendation;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sourceTool;
  final String? assessmentId;

  FindingRecord copyWith({
    FindingStatus? status,
    DateTime? lastSeen,
    DateTime? updatedAt,
    List<String>? sourceReportKeys,
    String? sourceTool,
    String? assessmentId,
    String? title,
    String? category,
    String? target,
    FindingSeverity? severity,
    FindingConfidence? confidence,
    String? description,
    List<String>? evidence,
    String? recommendation,
  }) => FindingRecord(
        findingId: findingId,
        fingerprint: fingerprint,
        title: title ?? this.title,
        category: category ?? this.category,
        target: target ?? this.target,
        severity: severity ?? this.severity,
        confidence: confidence ?? this.confidence,
        status: status ?? this.status,
        description: description ?? this.description,
        evidence: evidence ?? this.evidence,
        sourceReportKeys: sourceReportKeys ?? this.sourceReportKeys,
        recommendation: recommendation ?? this.recommendation,
        firstSeen: firstSeen,
        lastSeen: lastSeen ?? this.lastSeen,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        sourceTool: sourceTool ?? this.sourceTool,
        assessmentId: assessmentId ?? this.assessmentId,
      );

  FindingRecord sanitized() => copyWith(
        title: sanitizeFindingText(title, maxLength: 240),
        category: sanitizeFindingText(category, maxLength: 80),
        target: sanitizeActivityTarget(target),
        description: sanitizeFindingText(description, maxLength: 3000),
        evidence: sanitizeFindingList(evidence, maxItems: 20, maxLength: 500),
        sourceReportKeys: sourceReportKeys.where((key) => RegExp(r'^[0-9a-f]{64}$').hasMatch(key)).toSet().take(50).toList(),
        recommendation: sanitizeFindingText(recommendation, maxLength: 2000),
      );

  FindingRecord validated() {
    if (findingId.isEmpty || findingId.length > 128 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
      throw const FormatException('Finding identity is invalid.');
    }
    if (title.isEmpty || title.length > 240 || category.isEmpty || category.length > 80 || target.isEmpty || target.length > 260) {
      throw const FormatException('Finding title, category, or target is invalid.');
    }
    if (description.length > 3000 || recommendation.length > 2000 || evidence.length > 20 || evidence.any((item) => item.length > 500)) {
      throw const FormatException('Finding detail exceeds storage limits.');
    }
    if (sourceReportKeys.length > 50 || sourceReportKeys.any((key) => !RegExp(r'^[0-9a-f]{64}$').hasMatch(key))) {
      throw const FormatException('Finding source report references are invalid.');
    }
    if (sourceTool != null && sourceTool!.length > 64 || assessmentId != null && assessmentId!.length > 128) {
      throw const FormatException('Finding source linkage is invalid.');
    }
    return this;
  }
}

abstract interface class FindingRepository {
  Future<List<FindingRecord>> loadFindings({
    int limit = 500,
    FindingSeverity? severity,
    FindingStatus? status,
    String? category,
    String? target,
    String? query,
  });
  Future<List<FindingRecord>> saveObservedFindings(Iterable<FindingRecord> findings);
  Future<FindingRecord> updateFindingStatus(String findingId, FindingStatus status);
  Future<void> clearFindings();
}

class MemoryFindingRepository implements FindingRepository {
  final Map<String, FindingRecord> _findings = {};

  @override
  Future<List<FindingRecord>> loadFindings({
    int limit = 500,
    FindingSeverity? severity,
    FindingStatus? status,
    String? category,
    String? target,
    String? query,
  }) async {
    final normalizedCategory = category?.trim().toLowerCase();
    final normalizedTarget = target?.trim().toLowerCase();
    final normalizedQuery = query?.trim().toLowerCase();
    final found = _findings.values.where((record) {
      if (severity != null && record.severity != severity) return false;
      if (status != null && record.status != status) return false;
      if (normalizedCategory != null && normalizedCategory.isNotEmpty && !record.category.toLowerCase().contains(normalizedCategory)) return false;
      if (normalizedTarget != null && normalizedTarget.isNotEmpty && !record.target.toLowerCase().contains(normalizedTarget)) return false;
      if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
        final haystack = '${record.title} ${record.category} ${record.description} ${record.target} ${record.recommendation} ${record.evidence.join(' ')}'.toLowerCase();
        if (!haystack.contains(normalizedQuery)) return false;
      }
      return true;
    }).toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return List.unmodifiable(found.take(limit.clamp(1, 5000).toInt()));
  }

  @override
  Future<List<FindingRecord>> saveObservedFindings(Iterable<FindingRecord> findings) async {
    final saved = <FindingRecord>[];
    for (final raw in findings) {
      final incoming = raw.sanitized().validated();
      final existing = _findings[incoming.fingerprint];
      final record = existing == null
          ? incoming
          : existing.copyWith(
              lastSeen: incoming.lastSeen.isAfter(existing.lastSeen) ? incoming.lastSeen : existing.lastSeen,
              updatedAt: incoming.updatedAt.isAfter(existing.updatedAt) ? incoming.updatedAt : existing.updatedAt,
              sourceReportKeys: {...existing.sourceReportKeys, ...incoming.sourceReportKeys}.take(50).toList(),
              sourceTool: incoming.sourceTool ?? existing.sourceTool,
              assessmentId: incoming.assessmentId ?? existing.assessmentId,
              title: incoming.title,
              category: incoming.category,
              target: incoming.target,
              severity: incoming.severity,
              confidence: incoming.confidence,
              description: incoming.description,
              evidence: incoming.evidence,
              recommendation: incoming.recommendation,
            );
      _findings[record.fingerprint] = record;
      saved.add(record);
    }
    return List.unmodifiable(saved);
  }

  @override
  Future<FindingRecord> updateFindingStatus(String findingId, FindingStatus status) async {
    String? fingerprint;
    for (final entry in _findings.entries) {
      if (entry.value.findingId == findingId) {
        fingerprint = entry.key;
        break;
      }
    }
    if (fingerprint == null) throw StateError('Finding was not found.');
    final existing = _findings[fingerprint]!;
    final updated = existing.copyWith(status: status, updatedAt: DateTime.now().toUtc());
    _findings[fingerprint] = updated;
    return updated;
  }

  @override
  Future<void> clearFindings() async => _findings.clear();
}

FindingRecord findingRecordFromTool({
  required SecurityFinding finding,
  required ToolRunResult result,
  required String sourceReportKey,
  String? assessmentId,
}) {
  final safeTarget = sanitizeActivityTarget(result.target);
  final safeCategory = sanitizeFindingText(finding.category, maxLength: 80);
  final safeTitle = sanitizeFindingText(finding.title, maxLength: 240);
  final safeEvidence = sanitizeFindingList(finding.evidence, maxItems: 20, maxLength: 500);
  final canonicalEvidence = [...safeEvidence]..sort();
  final canonical = jsonEncode([
    safeTarget.toLowerCase(),
    safeCategory.toLowerCase(),
    normalizeFindingIdentity(finding.riskIdentity ?? safeTitle),
    canonicalEvidence,
  ]);
  final fingerprint = sha256.convert(utf8.encode(canonical)).toString();
  final findingId = sha256.convert(utf8.encode('finding-record:$fingerprint')).toString();
  final observedAt = result.completedAt.toUtc();
  return FindingRecord(
    findingId: findingId,
    fingerprint: fingerprint,
    title: safeTitle,
    category: safeCategory.isEmpty ? 'General' : safeCategory,
    target: safeTarget,
    severity: finding.severity,
    confidence: finding.confidence,
    status: FindingStatus.open,
    description: sanitizeFindingText(finding.description.isEmpty ? finding.title : finding.description, maxLength: 3000),
    evidence: safeEvidence,
    sourceReportKeys: [sourceReportKey],
    recommendation: sanitizeFindingText(finding.recommendation, maxLength: 2000),
    firstSeen: observedAt,
    lastSeen: observedAt,
    createdAt: observedAt,
    updatedAt: observedAt,
    sourceTool: result.toolId,
    assessmentId: assessmentId,
  ).sanitized().validated();
}

String normalizeFindingIdentity(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String sanitizeFindingText(String input, {required int maxLength}) {
  final safe = input
      .replaceAll(RegExp(r'https?://[^\s/?#@]+@', caseSensitive: false), 'https://[redacted]@')
      .replaceAll(RegExp(r'(https?://[^\s?#]+)\?[^\s#]*', caseSensitive: false), r'$1?[redacted]')
      .replaceAll(RegExp(r'(https?://[^\s?#]+)#[^\s]*', caseSensitive: false), r'$1')
      .replaceAll(
        RegExp(r'\b(api[_-]?key|access[_-]?token|refresh[_-]?token|token|password|passwd|secret|authorization)\s*[:=]\s*[^\s,;]+', caseSensitive: false),
        '[redacted]',
      )
      .replaceAll(RegExp(r'\bBearer\s+\S+', caseSensitive: false), 'Bearer [redacted]')
      .replaceAll(RegExp(r'[\u0000-\u001f]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return safe.length > maxLength ? safe.substring(0, maxLength) : safe;
}

List<String> sanitizeFindingList(Iterable<String> values, {required int maxItems, required int maxLength}) => [
      for (final value in values.take(maxItems))
        if (sanitizeFindingText(value, maxLength: maxLength).isNotEmpty) sanitizeFindingText(value, maxLength: maxLength),
    ];
