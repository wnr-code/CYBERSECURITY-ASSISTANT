import 'package:cybersecurity_assistant/core/assessment_progress.dart';
import 'package:flutter_test/flutter_test.dart';

AssessmentProgressSnapshot _snapshot(
  String runId, {
  bool isRunning = true,
  int selectedCount = 3,
  int completedCount = 0,
  int failedCount = 0,
  int skippedCount = 0,
  int cancelledCount = 0,
}) => AssessmentProgressSnapshot(
      runId: runId,
      isRunning: isRunning,
      selectedCount: selectedCount,
      completedCount: completedCount,
      failedCount: failedCount,
      skippedCount: skippedCount,
      cancelledCount: cancelledCount,
    );

void main() {
  test('run IDs are unique and the owner begins with an actual selected count', () {
    final owner = AssessmentProgressCoordinator();
    final first = owner.beginRun(selectedCount: 2);
    final second = owner.beginRun(selectedCount: 1);

    expect(first.runId, isNotEmpty);
    expect(second.runId, isNot(first.runId));
    expect(second.selectedCount, 1);
    expect(owner.current?.runId, second.runId);
    expect(owner.current?.processedCount, 0);
  });

  test('late progress and completion from Run A cannot replace or clear Run B', () {
    final owner = AssessmentProgressCoordinator();
    final runA = owner.beginRun(selectedCount: 3);
    expect(owner.accept(_snapshot(runA.runId, completedCount: 1)), isTrue);

    final runB = owner.beginRun(selectedCount: 2);
    expect(owner.accept(_snapshot(runB.runId, completedCount: 1)), isTrue);

    expect(owner.accept(_snapshot(runA.runId, completedCount: 2)), isFalse, reason: 'Late Run A progress must be ignored.');
    expect(owner.accept(_snapshot(runA.runId, isRunning: false, completedCount: 3)), isFalse,
        reason: 'Run A completion must not clear Run B.');
    expect(owner.current?.runId, runB.runId);
    expect(owner.current?.completedCount, 1);
  });

  test('cancellation only clears the run that owns the active snapshot', () {
    final owner = AssessmentProgressCoordinator();
    final runA = owner.beginRun(selectedCount: 2);
    final runB = owner.beginRun(selectedCount: 4);

    expect(owner.accept(_snapshot(runA.runId, isRunning: false, cancelledCount: 1)), isFalse);
    expect(owner.current?.runId, runB.runId);
    expect(owner.accept(_snapshot(runB.runId, isRunning: false, cancelledCount: 1)), isTrue);
    expect(owner.current, isNull);
  });

  test('a terminal snapshot cannot be followed by stale progress that revives its run', () {
    final owner = AssessmentProgressCoordinator();
    final run = owner.beginRun(selectedCount: 1);

    expect(owner.accept(_snapshot(run.runId, isRunning: false, completedCount: 1)), isTrue);
    expect(owner.current, isNull);
    expect(owner.accept(_snapshot(run.runId, completedCount: 0)), isFalse);
    expect(owner.current, isNull);
  });

  test('progress fractions count processed selected checks and remain bounded', () {
    const progress = AssessmentProgressSnapshot(
      runId: 'test-run',
      isRunning: true,
      selectedCount: 4,
      completedCount: 1,
      failedCount: 1,
      skippedCount: 0,
      cancelledCount: 0,
    );
    expect(progress.processedCount, 2);
    expect(progress.fraction, .5);

    const completed = AssessmentProgressSnapshot(
      runId: 'completed-run',
      isRunning: false,
      selectedCount: 1,
      completedCount: 2,
      failedCount: 0,
      skippedCount: 0,
      cancelledCount: 0,
    );
    expect(completed.fraction, 1);
  });
}
