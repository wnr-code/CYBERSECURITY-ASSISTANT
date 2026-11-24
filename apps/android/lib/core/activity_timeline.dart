import 'dart:convert';

import 'package:crypto/crypto.dart';

enum ActivityKind { assessment, tool }
enum ActivityStatus { started, running, completed, failed, cancelled }

class ActivityEvent {
  const ActivityEvent({
    required this.eventId,
    required this.kind,
    required this.target,
    required this.status,
    required this.startedAt,
    this.parentEventId,
    this.toolId,
    this.finishedAt,
    this.summary,
    this.findingCount,
    this.sourceResultKey,
  });

  final String eventId;
  final ActivityKind kind;
  final String? parentEventId;
  final String? toolId;
  /// Host and non-default port only. Paths, query strings and user info are never stored.
  final String target;
  final ActivityStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? summary;
  final int? findingCount;
  final String? sourceResultKey;

  ActivityEvent copyWith({
    String? target,
    ActivityStatus? status,
    DateTime? finishedAt,
    String? summary,
    int? findingCount,
    String? sourceResultKey,
  }) => ActivityEvent(
        eventId: eventId,
        kind: kind,
        parentEventId: parentEventId,
        toolId: toolId,
        target: target ?? this.target,
        status: status ?? this.status,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        summary: summary ?? this.summary,
        findingCount: findingCount ?? this.findingCount,
        sourceResultKey: sourceResultKey ?? this.sourceResultKey,
      );

  ActivityEvent sanitizedForStorage() => copyWith(
        target: sanitizeActivityTarget(target),
        summary: summary == null ? null : sanitizeActivitySummary(summary!),
      );

  ActivityEvent validated() {
    if (eventId.isEmpty || eventId.length > 128 || target.isEmpty || target.length > 260) {
      throw const FormatException('Activity event identity or target is invalid.');
    }
    if (parentEventId != null && parentEventId!.length > 128 || toolId != null && toolId!.length > 64) {
      throw const FormatException('Activity event linkage is invalid.');
    }
    if (findingCount != null && (findingCount! < 0 || findingCount! > 128)) {
      throw const FormatException('Activity finding count is invalid.');
    }
    if (summary != null && summary!.length > 240) {
      throw const FormatException('Activity summary exceeds the storage limit.');
    }
    if (sourceResultKey != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceResultKey!)) {
      throw const FormatException('Activity source report key is invalid.');
    }
    return this;
  }
}

abstract interface class ActivityHistoryStore {
  Future<void> upsertActivity(ActivityEvent event);
  Future<List<ActivityEvent>> loadActivities({
    int limit = 500,
    DateTime? from,
    DateTime? to,
    String? target,
    ActivityKind? kind,
    String? toolId,
    ActivityStatus? status,
  });
  Future<void> clearActivities();
}

class MemoryActivityHistoryStore implements ActivityHistoryStore {
  MemoryActivityHistoryStore({this.maxRecords = 500}) {
    if (maxRecords < 1 || maxRecords > 5000) throw ArgumentError.value(maxRecords, 'maxRecords', 'Must be between 1 and 5000.');
  }

  final int maxRecords;
  final Map<String, ActivityEvent> _events = {};

  @override
  Future<void> upsertActivity(ActivityEvent event) async {
    final validated = event.sanitizedForStorage().validated();
    _events[validated.eventId] = validated;
    if (_events.length > maxRecords) {
      final ordered = _events.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      _events
        ..clear()
        ..addEntries(ordered.take(maxRecords).map((entry) => MapEntry(entry.eventId, entry)));
    }
  }

  @override
  Future<List<ActivityEvent>> loadActivities({
    int limit = 500,
    DateTime? from,
    DateTime? to,
    String? target,
    ActivityKind? kind,
    String? toolId,
    ActivityStatus? status,
  }) async {
    final safeLimit = limit.clamp(1, maxRecords).toInt();
    final normalizedTarget = target?.trim().toLowerCase();
    final filtered = _events.values.where((event) {
      final started = event.startedAt.toUtc();
      if (from != null && started.isBefore(from.toUtc())) return false;
      if (to != null && started.isAfter(to.toUtc())) return false;
      if (normalizedTarget != null && normalizedTarget.isNotEmpty && !event.target.toLowerCase().contains(normalizedTarget)) return false;
      if (kind != null && event.kind != kind) return false;
      if (toolId != null && toolId.isNotEmpty && event.toolId != toolId) return false;
      if (status != null && event.status != status) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List.unmodifiable(filtered.take(safeLimit));
  }

  @override
  Future<void> clearActivities() async => _events.clear();
}

String sanitizeActivityTarget(String input) {
  final value = input.trim();
  if (value.isEmpty || value.length > 2048) return 'target unavailable';
  final candidate = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  if (candidate == null || candidate.host.isEmpty) return 'target unavailable';
  final host = candidate.host.toLowerCase();
  final displayHost = host.startsWith('[') ? host : host.contains(':') ? '[$host]' : host;
  final port = candidate.hasPort && candidate.port != 443 ? ':${candidate.port}' : '';
  return '$displayHost$port';
}

String sanitizeActivitySummary(String input) {
  final redacted = input
      .replaceAll(RegExp(r'https?://[^\s/?#@]+@', caseSensitive: false), 'https://[redacted]@')
      .replaceAll(RegExp(r'(https?://[^\s?#]+)\?[^\s#]*', caseSensitive: false), r'$1?[redacted]')
      .replaceAll(RegExp(r'(https?://[^\s?#]+)#[^\s]*', caseSensitive: false), r'$1')
      .replaceAll(
        RegExp(r'\b(api[_-]?key|access[_-]?token|refresh[_-]?token|token|password|passwd|secret|authorization)\s*[:=]\s*[^\s,;]+', caseSensitive: false),
        '[redacted]',
      )
      .replaceAll(RegExp(r'\bBearer\s+\S+', caseSensitive: false), 'Bearer [redacted]')
      .replaceAll(RegExp(r'[\r\n\u0000-\u001f]+'), ' ')
      .trim();
  return redacted.length > 240 ? '${redacted.substring(0, 239)}…' : redacted;
}

String activityTimestamp(DateTime value) {
  final utc = value.toUtc();
  final year = utc.year.toString().padLeft(4, '0');
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  final second = utc.second.toString().padLeft(2, '0');
  final fraction = (utc.millisecond * 1000 + utc.microsecond).toString().padLeft(6, '0');
  return '$year-$month-${day}T$hour:$minute:$second.${fraction}Z';
}

String activityResultKey(String toolId, String target, DateTime completedAt) =>
    sha256.convert(utf8.encode('$toolId|$target|${completedAt.toUtc().microsecondsSinceEpoch}')).toString();
