import 'package:flutter/foundation.dart';

/// Lightweight startup timing breadcrumbs for debug builds and cold-start audits.
/// No startup work is gated on this timer; release builds emit no log output.
class StartupTrace {
  StartupTrace._();

  static final Stopwatch _clock = Stopwatch();
  static bool _started = false;

  static void begin() {
    if (!kDebugMode) return;
    _clock
      ..reset()
      ..start();
    _started = true;
    mark('dart-main');
  }

  static void mark(String event) {
    if (!kDebugMode) return;
    if (!_started) begin();
    debugPrint('[APP_STARTUP] $event +${_clock.elapsedMilliseconds}ms');
  }
}
