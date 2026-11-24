/// Read-only presentation snapshot of one AssessmentRunner invocation.
/// `runId` remains attached to terminal snapshots so an owner can reject stale
/// completion/cancellation callbacks from superseded runs.
class AssessmentProgressSnapshot {
  const AssessmentProgressSnapshot({
    required this.runId,
    required this.isRunning,
    required this.selectedCount,
    required this.completedCount,
    required this.failedCount,
    required this.skippedCount,
    required this.cancelledCount,
  });

  final String runId;
  final bool isRunning;
  final int selectedCount;
  final int completedCount;
  final int failedCount;
  final int skippedCount;
  final int cancelledCount;

  int get processedCount => completedCount + failedCount + skippedCount + cancelledCount;

  double get fraction => selectedCount == 0 ? 0 : (processedCount / selectedCount).clamp(0, 1).toDouble();
}

/// MainShell-owned arbiter for the one Assessment progress state shown by the
/// Dashboard. A newer run supersedes the previous run; snapshots and terminal
/// events are accepted only from the current run ID.
class AssessmentProgressCoordinator {
  int _sequence = 0;
  String? _activeRunId;
  AssessmentProgressSnapshot? _current;

  AssessmentProgressSnapshot? get current => _current;

  AssessmentProgressSnapshot beginRun({required int selectedCount}) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final runId = 'assessment-$timestamp-${++_sequence}';
    _activeRunId = runId;
    final initial = AssessmentProgressSnapshot(
      runId: runId,
      isRunning: true,
      selectedCount: selectedCount,
      completedCount: 0,
      failedCount: 0,
      skippedCount: 0,
      cancelledCount: 0,
    );
    _current = selectedCount == 0 ? null : initial;
    return initial;
  }

  /// Returns false for late updates or completion events from older runs.
  bool accept(AssessmentProgressSnapshot snapshot) {
    if (_activeRunId != snapshot.runId) return false;
    if (!snapshot.isRunning) {
      _activeRunId = null;
      _current = null;
      return true;
    }
    _current = snapshot;
    return true;
  }
}
