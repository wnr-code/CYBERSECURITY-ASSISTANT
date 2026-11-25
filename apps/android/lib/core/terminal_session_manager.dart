import 'dart:math';

import 'package:flutter/foundation.dart';

import 'activity_timeline.dart';
import 'diagnostics.dart';

/// A terminal is an app-owned workspace session, not an operating-system shell.
enum TerminalSessionStatus { ready, running, exited }
enum TerminalEntryStatus { running, completed, failed, cancelled }

class TerminalHistoryEntry {
  const TerminalHistoryEntry({
    required this.id,
    required this.command,
    required this.output,
    required this.startedAt,
    required this.status,
    this.finishedAt,
  });

  final String id;
  final String command;
  final String output;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final TerminalEntryStatus status;

  TerminalHistoryEntry copyWith({String? output, DateTime? finishedAt, TerminalEntryStatus? status}) => TerminalHistoryEntry(
        id: id,
        command: command,
        output: output ?? this.output,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        status: status ?? this.status,
      );
}

class TerminalExecutionResult {
  const TerminalExecutionResult.completed(this.output, {this.executionId, this.executionData})
      : succeeded = true,
        cancelled = false;
  const TerminalExecutionResult.failed(this.output, {this.executionId, this.executionData})
      : succeeded = false,
        cancelled = false;
  const TerminalExecutionResult.cancelled(this.output, {this.executionId, this.executionData})
      : succeeded = false,
        cancelled = true;

  final String output;
  final bool succeeded;
  final bool cancelled;
  /// Present only when returned by the Runtime Manager; never locally fabricated.
  final String? executionId;
  /// Bounded, structured output from the actual tool runtime (not shell streams).
  final Map<String, Object?>? executionData;
}

/// Owns the in-memory command/output history for one explicit terminal session.
/// It survives tab changes because MainShell owns this notifier for its lifetime.
class TerminalSessionManager extends ChangeNotifier {
  TerminalSessionManager({ActivityHistoryStore? activityStore, void Function(ActivityEvent)? onActivity})
      : this._(activityStore, onActivity);

  TerminalSessionManager._(this._activityStore, this._onActivity) {
    _startNewSession();
  }

  static const maxEntries = 200;
  static final Random _random = Random.secure();
  final ActivityHistoryStore? _activityStore;
  final void Function(ActivityEvent)? _onActivity;
  final List<TerminalHistoryEntry> _entries = [];
  TerminalSessionStatus _status = TerminalSessionStatus.ready;
  DateTime _startedAt = DateTime.now().toUtc();
  String _sessionId = '';
  int _entrySequence = 0;
  bool _disposed = false;
  bool _auditWriteFailed = false;

  List<TerminalHistoryEntry> get entries => List.unmodifiable(_entries);
  bool get auditPersistenceAvailable => _activityStore != null && !_auditWriteFailed;
  TerminalSessionStatus get status => _status;
  DateTime get startedAt => _startedAt;
  String get sessionId => _sessionId;
  bool get isExited => _status == TerminalSessionStatus.exited;

  void startNewSession() {
    if (!isExited) return;
    _entries.clear();
    _startNewSession();
    _notifyListeners();
  }

  void _startNewSession() {
    _sessionId = 'terminal-${DateTime.now().toUtc().microsecondsSinceEpoch}-${_random.nextInt(1 << 32).toRadixString(16)}';
    _entrySequence = 0;
    _startedAt = DateTime.now().toUtc();
    _status = TerminalSessionStatus.ready;
  }

  Future<void> submit(
    String command, {
    required Future<TerminalExecutionResult> Function(String command) execute,
    required String auditLabel,
    required String Function(String source) translate,
  }) async {
    if (isExited) throw StateError('The terminal session has exited.');
    final normalized = command.trim();
    if (normalized.isEmpty) return;
    if (_status == TerminalSessionStatus.running) return;

    final now = DateTime.now().toUtc();
    final entry = TerminalHistoryEntry(
      id: '$sessionId-${++_entrySequence}-${now.microsecondsSinceEpoch}',
      command: normalized.length <= 256 ? normalized : normalized.substring(0, 256),
      output: '',
      startedAt: now,
      status: TerminalEntryStatus.running,
    );
    _append(entry);
    _status = TerminalSessionStatus.running;
    _notifyListeners();
    await _recordActivity(auditLabel, ActivityStatus.started, now, entry.id);

    try {
      final result = auditLabel == 'run' && !auditPersistenceAvailable
          ? TerminalExecutionResult.failed(translate('Terminal audit storage is unavailable; tool execution is disabled.'))
          : await execute(entry.command);
      _replace(entry.copyWith(
        output: result.output,
        status: result.succeeded
            ? TerminalEntryStatus.completed
            : result.cancelled
                ? TerminalEntryStatus.cancelled
                : TerminalEntryStatus.failed,
        finishedAt: DateTime.now().toUtc(),
      ));
      await _recordActivity(
        auditLabel,
        result.succeeded
            ? ActivityStatus.completed
            : result.cancelled
                ? ActivityStatus.cancelled
                : ActivityStatus.failed,
        now,
        entry.id,
      );
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(
        error,
        stackTrace: stack,
        category: DiagnosticCategory.terminal,
        reportType: DiagnosticReportType.terminalError,
        severity: DiagnosticSeverity.high,
        component: 'terminal_session',
        runtimeStatus: 'failed',
      );
      _replace(entry.copyWith(
        output: translate('Terminal command failed. Sensitive details were omitted.'),
        status: TerminalEntryStatus.failed,
        finishedAt: DateTime.now().toUtc(),
      ));
      await _recordActivity(auditLabel, ActivityStatus.failed, now, entry.id);
    } finally {
      if (!isExited) _status = TerminalSessionStatus.ready;
      _notifyListeners();
    }
  }

  Future<void> exit() async {
    if (isExited || _status == TerminalSessionStatus.running) return;
    _status = TerminalSessionStatus.exited;
    _notifyListeners();
    final exitedAt = DateTime.now().toUtc();
    await _recordActivity('session_exit', ActivityStatus.completed, exitedAt, '$_sessionId-exit');
  }

  void _append(TerminalHistoryEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxEntries) _entries.removeRange(0, _entries.length - maxEntries);
  }

  void _replace(TerminalHistoryEntry entry) {
    final index = _entries.indexWhere((candidate) => candidate.id == entry.id);
    if (index >= 0) _entries[index] = entry;
  }

  void _notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _recordActivity(String action, ActivityStatus status, DateTime startedAt, String recordId) async {
    final event = ActivityEvent(
      eventId: '$recordId-audit',
      kind: ActivityKind.tool,
      toolId: 'terminal_workspace',
      target: 'terminal.local',
      status: status,
      startedAt: startedAt,
      finishedAt: status == ActivityStatus.started ? null : DateTime.now().toUtc(),
      summary: 'Terminal session action: $action.',
    );
    final store = _activityStore;
    if (store == null) {
      _auditWriteFailed = true;
      _notifyListeners();
      return;
    }
    try {
      await store.upsertActivity(event);
    } catch (_) {
      _auditWriteFailed = true;
      _notifyListeners();
      return;
    }
    try {
      _onActivity?.call(event);
    } catch (_) {
      // The audit has been persisted; a presentation callback failure does not
      // invalidate the activity record.
    }
  }
}
