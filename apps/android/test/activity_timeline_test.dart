import 'package:cybersecurity_assistant/core/activity_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

ActivityEvent _event({
  required String id,
  required DateTime startedAt,
  String target = 'example.com',
  ActivityKind kind = ActivityKind.tool,
  String? toolId = 'dns_lookup',
  ActivityStatus status = ActivityStatus.completed,
}) => ActivityEvent(
      eventId: id,
      kind: kind,
      toolId: kind == ActivityKind.tool ? toolId : null,
      target: target,
      status: status,
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(seconds: 2)),
      summary: 'Fixture activity',
    );

void main() {
  test('upserting lifecycle transitions updates one event instead of duplicating it', () async {
    final store = MemoryActivityHistoryStore();
    final started = _event(id: 'tool-1', startedAt: DateTime.utc(2026, 11, 23), status: ActivityStatus.started);
    await store.upsertActivity(started);
    await store.upsertActivity(started.copyWith(status: ActivityStatus.running));
    await store.upsertActivity(started.copyWith(
      status: ActivityStatus.completed,
      finishedAt: DateTime.utc(2026, 11, 23, 0, 1),
      summary: 'Resolved one address.',
      findingCount: 0,
    ));

    final events = await store.loadActivities();
    expect(events, hasLength(1));
    expect(events.single.status, ActivityStatus.completed);
    expect(events.single.summary, 'Resolved one address.');
    expect(events.single.findingCount, 0);
  });

  test('loads chronologically and filters by date, target, activity kind, tool and status', () async {
    final store = MemoryActivityHistoryStore();
    await store.upsertActivity(_event(
      id: 'assessment-1',
      startedAt: DateTime.utc(2026, 11, 20),
      target: 'alpha.example',
      kind: ActivityKind.assessment,
      status: ActivityStatus.completed,
    ));
    await store.upsertActivity(_event(
      id: 'tls-1',
      startedAt: DateTime.utc(2026, 11, 22),
      target: 'alpha.example',
      toolId: 'tls_inspector',
      status: ActivityStatus.failed,
    ));
    await store.upsertActivity(_event(
      id: 'http-1',
      startedAt: DateTime.utc(2026, 11, 23),
      target: 'beta.example',
      toolId: 'http_headers',
      status: ActivityStatus.completed,
    ));

    expect((await store.loadActivities()).map((event) => event.eventId), ['http-1', 'tls-1', 'assessment-1']);
    final filtered = await store.loadActivities(
      from: DateTime.utc(2026, 11, 21),
      to: DateTime.utc(2026, 11, 23),
      target: 'ALPHA',
      kind: ActivityKind.tool,
      toolId: 'tls_inspector',
      status: ActivityStatus.failed,
    );
    expect(filtered.map((event) => event.eventId), ['tls-1']);
  });

  test('activity summaries redact secrets, credentials and control characters before storage', () {
    final summary = sanitizeActivitySummary('Loaded https://alice:secret@example.com/api with api_key=abc123 and Bearer eyJhbGci.\nDone.');
    expect(summary, isNot(contains('alice')));
    expect(summary, isNot(contains('secret')));
    expect(summary, isNot(contains('abc123')));
    expect(summary, isNot(contains('eyJhbGci')));
    expect(summary, isNot(contains('\n')));
    expect(summary, contains('[redacted]'));
  });

  test('timestamps use fixed-width UTC microseconds so lexical SQLite ordering is chronological', () {
    final earlier = DateTime.utc(2026, 11, 23, 12, 0, 0, 0, 1);
    final later = DateTime.utc(2026, 11, 23, 12, 0, 0, 1);
    expect(activityTimestamp(earlier), '2026-11-23T12:00:00.000001Z');
    expect(activityTimestamp(later), '2026-11-23T12:00:00.001000Z');
    expect(activityTimestamp(earlier).compareTo(activityTimestamp(later)), lessThan(0));
  });

  test('target sanitizer removes credentials, path, query and fragment', () {
    expect(
      sanitizeActivityTarget('https://alice:secret@example.com/private/path?token=hidden#section'),
      'example.com',
    );
    expect(sanitizeActivityTarget('https://example.com:8443/api?key=hidden'), 'example.com:8443');
    expect(sanitizeActivityTarget('https://[2001:db8::1]:8443/private'), '[2001:db8::1]:8443');
    expect(sanitizeActivityTarget(''), 'target unavailable');
  });

  test('storage boundary sanitizes raw targets and truncates oversized summaries', () async {
    final store = MemoryActivityHistoryStore();
    await store.upsertActivity(_event(
      id: 'safe-boundary',
      startedAt: DateTime.utc(2026),
      target: 'https://alice:secret@example.com/private?token=hidden',
    ).copyWith(summary: 's' * 500));
    final stored = (await store.loadActivities()).single;
    expect(stored.target, 'example.com');
    expect(stored.summary, hasLength(240));
    expect(stored.summary, isNot(contains('secret')));
  });

  test('rejects out-of-range finding counts', () async {
    final store = MemoryActivityHistoryStore();
    await expectLater(
      store.upsertActivity(_event(id: 'x', startedAt: DateTime.utc(2026)).copyWith(findingCount: 129)),
      throwsFormatException,
    );
  });
}
