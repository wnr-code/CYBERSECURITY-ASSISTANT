import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/activity_timeline.dart';
import '../core/assessment_progress.dart';
import '../core/security_tools.dart';
import '../l10n/activity_localization.dart';
import '../l10n/app_localizations.dart';

const _securityCyan = Color(0xFF36D9FF);
const _securityMint = Color(0xFF73F0C2);
const _securityPanel = Color(0xFF111D32);

/// A security-status visual, not a network map. Its labels and progress are
/// derived only from the active Assessment and locally loaded records.
class SecurityStatusHero extends StatefulWidget {
  const SecurityStatusHero({
    super.key,
    required this.assessmentProgress,
    required this.activeAssessmentTarget,
    required this.latestAssessment,
    required this.activityLoaded,
    required this.activityBusy,
    required this.activityError,
    required this.findingsCount,
    required this.findingsBySeverity,
    required this.findingsLoaded,
    required this.findingsBusy,
    required this.findingsError,
    this.onTap,
  });

  final AssessmentProgressSnapshot? assessmentProgress;
  final String? activeAssessmentTarget;
  final ActivityEvent? latestAssessment;
  final bool activityLoaded;
  final bool activityBusy;
  final String? activityError;
  final int findingsCount;
  final Map<FindingSeverity, int> findingsBySeverity;
  final bool findingsLoaded;
  final bool findingsBusy;
  final String? findingsError;
  final VoidCallback? onTap;

  @override
  State<SecurityStatusHero> createState() => _SecurityStatusHeroState();
}

class _SecurityStatusHeroState extends State<SecurityStatusHero>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  bool _appIsResumed = true;

  bool get _isRunning => widget.assessmentProgress?.isRunning == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsResumed = state == AppLifecycleState.resumed;
    if (mounted) _syncMotionPreference();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionPreference();
  }

  @override
  void didUpdateWidget(covariant SecurityStatusHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assessmentProgress?.isRunning != widget.assessmentProgress?.isRunning) {
      _syncMotionPreference();
    }
  }

  void _syncMotionPreference() {
    final shouldAnimate = _appIsResumed &&
        !MediaQuery.of(context).disableAnimations &&
        TickerMode.valuesOf(context).enabled;
    final duration = Duration(milliseconds: _isRunning ? 2200 : 14000);
    if (!shouldAnimate) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating || _pulse.duration != duration) {
      _pulse
        ..duration = duration
        ..repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.assessmentProgress;
    final active = progress?.isRunning == true;
    final status = widget.latestAssessment?.status;
    final statusColor = active
        ? _securityCyan
        : switch (status) {
            ActivityStatus.completed => _securityMint,
            ActivityStatus.failed => Colors.orangeAccent,
            ActivityStatus.cancelled => Colors.white60,
            ActivityStatus.started || ActivityStatus.running => _securityCyan,
            null => const Color(0xFF8FA1B9),
          };
    final highestFindingSeverity = widget.findingsLoaded ? _highestFindingSeverity(widget.findingsBySeverity) : null;
    final orbColor = active || status == ActivityStatus.failed || highestFindingSeverity == null
        ? statusColor
        : _severityColor(highestFindingSeverity);
    final statusLabel = active
        ? context.tr('Assessment running')
        : status == null
            ? widget.activityError != null
                ? context.tr('Activity data unavailable')
                : widget.activityBusy || !widget.activityLoaded
                    ? context.tr('Loading assessment data…')
                    : context.tr('No saved assessment')
            : _statusLabel(status, context);
    final centerProgress = active ? progress!.fraction : 0.0;

    return Card(
      key: const ValueKey('security-status-hero'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
          height: 276,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_securityPanel, Color(0xFF10182A), Color(0xFF142238)],
            ),
            border: Border.all(color: orbColor.withValues(alpha: .24)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: Text(
                    context.tr('ASSESSMENT STATUS'),
                    style: const TextStyle(color: _securityCyan, fontWeight: FontWeight.w800, letterSpacing: .6),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: .35)),
                  ),
                  child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ]),
              Expanded(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => CustomPaint(
                    painter: _SecurityGridPainter(
                      color: orbColor,
                      isRunning: active,
                      pulse: _pulse.value,
                      progress: centerProgress,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 148,
                        height: 148,
                        child: Stack(alignment: Alignment.center, children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: centerProgress),
                            duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 420),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) => CircularProgressIndicator(
                              value: active ? value : 0.0,
                              strokeWidth: active ? 3.2 : 1.6,
                              backgroundColor: orbColor.withValues(alpha: active ? .14 : .12),
                              color: orbColor.withValues(alpha: active ? 1.0 : .55),
                            ),
                          ),
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            TweenAnimationBuilder<Color?>(
                              tween: ColorTween(end: orbColor),
                              duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 320),
                              builder: (context, color, _) => Icon(Icons.shield_moon_outlined, size: 57, color: color ?? orbColor),
                            ),
                            if (active) ...[
                              const SizedBox(height: 1),
                              Text('${(centerProgress * 100).round()}%', style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w800)),
                            ],
                          ]),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
              _statusDetails(context, active, progress),
              const SizedBox(height: 4),
              Text(
                context.tr('The orb shows operational status only; grid and particles are decorative, not network topology or security score.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: .52), fontSize: 9, height: 1.25),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _statusDetails(BuildContext context, bool active, AssessmentProgressSnapshot? progress) {
    final assessment = widget.latestAssessment;
    final String assessmentLine;
    if (active && progress != null) {
      final target = widget.activeAssessmentTarget ?? assessment?.target;
      final progressLabel = '${progress.processedCount} / ${progress.selectedCount} ${context.tr('checks')}';
      assessmentLine = target == null ? progressLabel : '$target · $progressLabel';
    } else if (assessment != null) {
      final time = _timeLabel(assessment.startedAt);
      final resultSummary = activitySummaryText(assessment, context).trim();
      assessmentLine = resultSummary.isEmpty
          ? '${assessment.target} · $time'
          : '${assessment.target} · $time · $resultSummary';
    } else if (widget.activityError != null) {
      assessmentLine = context.tr('Could not load saved assessment history.');
    } else if (widget.activityBusy || !widget.activityLoaded) {
      assessmentLine = context.tr('Loading saved assessment history…');
    } else {
      assessmentLine = context.tr('Run an authorized Assessment to show its real status here.');
    }

    final String findingsLine;
    if (widget.findingsError != null && !widget.findingsLoaded) {
      findingsLine = context.tr('Saved Findings unavailable');
    } else if (widget.findingsBusy && !widget.findingsLoaded) {
      findingsLine = context.tr('Loading saved Findings…');
    } else if (widget.findingsLoaded) {
      final highestSeverity = _highestFindingSeverity(widget.findingsBySeverity);
      final severitySummary = highestSeverity == null ? '' : ' · ${context.tr('Highest severity')}: ${_severityLabel(highestSeverity, context)}';
      findingsLine = '${context.tr('Loaded Findings')}: ${widget.findingsCount}$severitySummary';
    } else {
      findingsLine = context.tr('Findings count not loaded');
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(
        assessmentLine,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 3),
      Text(findingsLine, style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 10)),
    ]);
  }
}

class _SecurityGridPainter extends CustomPainter {
  const _SecurityGridPainter({
    required this.color,
    required this.isRunning,
    required this.pulse,
    required this.progress,
  });

  final Color color;
  final bool isRunning;
  final double pulse;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = color.withValues(alpha: isRunning ? .11 + progress * .08 : .055)
      ..strokeWidth = .65;
    const cell = 22.0;
    for (var x = 0.0; x <= size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width * .18, size.height * .37);
    final haloPaint = Paint()
      ..color = color.withValues(alpha: isRunning ? .09 + .07 * math.sin(pulse * math.pi * 2).abs() : .05);
    canvas.drawCircle(center, radius * 1.48, haloPaint);

    final orbBounds = Rect.fromCircle(center: center, radius: radius);
    final orbPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.34, -.4),
        colors: [color.withValues(alpha: .35), const Color(0xFF12334D).withValues(alpha: .92), const Color(0xFF0A1528)],
        stops: const [0, .5, 1],
      ).createShader(orbBounds);
    canvas.drawCircle(center, radius, orbPaint);

    canvas.save();
    canvas.clipPath(Path()..addOval(orbBounds));
    final sphereLine = Paint()
      ..color = color.withValues(alpha: isRunning ? .42 : .26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    canvas.drawOval(Rect.fromCenter(center: center, width: radius * 2, height: radius * .65), sphereLine);
    canvas.drawOval(Rect.fromCenter(center: center, width: radius * 1.05, height: radius * 2), sphereLine);
    canvas.drawOval(Rect.fromCenter(center: center, width: radius * 1.62, height: radius * 2), sphereLine);
    if (isRunning) {
      final sweepY = center.dy - radius + radius * 2 * ((pulse + progress * .35) % 1);
      final sweepRect = Rect.fromLTWH(center.dx - radius, sweepY - 6, radius * 2, 12);
      final sweepPaint = Paint()
        ..shader = LinearGradient(
          colors: [Colors.transparent, color.withValues(alpha: .5), Colors.transparent],
        ).createShader(sweepRect);
      canvas.drawRect(sweepRect, sweepPaint);
    }
    canvas.restore();

    final orbitPaint = Paint()
      ..color = color.withValues(alpha: isRunning ? .74 : .45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05;
    final orbitRotation = pulse * math.pi * 2 * (isRunning ? 0.8 : 0.12);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(orbitRotation);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: radius * 3.05, height: radius * .86), orbitPaint);
    canvas.rotate(-orbitRotation * 1.7);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: radius * 2.62, height: radius * .72), orbitPaint..color = color.withValues(alpha: .3));
    canvas.restore();

    final particleAngle = pulse * math.pi * 2 * (isRunning ? 1 : .16);
    final particle = Offset(
      center.dx + math.cos(particleAngle) * radius * 1.52,
      center.dy + math.sin(particleAngle) * radius * .43,
    );
    canvas.drawCircle(particle, 2.2, Paint()..color = color.withValues(alpha: .95));
    final secondParticle = Offset(
      center.dx - math.cos(particleAngle * .73) * radius * 1.3,
      center.dy + math.sin(particleAngle * .73) * radius * .36,
    );
    canvas.drawCircle(secondParticle, 1.4, Paint()..color = const Color(0xFFB7FFF1).withValues(alpha: .72));

    final tracePaint = Paint()
      ..color = color.withValues(alpha: isRunning ? .18 + progress * .22 : .10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final trace = Path()
      ..moveTo(0, size.height * .27)
      ..lineTo(size.width * .22, size.height * .27)
      ..lineTo(size.width * .31, size.height * .39)
      ..moveTo(size.width, size.height * .72)
      ..lineTo(size.width * .78, size.height * .72)
      ..lineTo(size.width * .68, size.height * .61)
      ..moveTo(size.width * .5, 0)
      ..lineTo(size.width * .5, size.height * .12)
      ..moveTo(size.width * .5, size.height * .88)
      ..lineTo(size.width * .5, size.height);
    canvas.drawPath(trace, tracePaint);
  }

  @override
  bool shouldRepaint(covariant _SecurityGridPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.isRunning != isRunning ||
      oldDelegate.pulse != pulse ||
      oldDelegate.progress != progress;
}

FindingSeverity? _highestFindingSeverity(Map<FindingSeverity, int> counts) {
  for (final severity in FindingSeverity.values) {
    if ((counts[severity] ?? 0) > 0) return severity;
  }
  return null;
}

String _severityLabel(FindingSeverity severity, BuildContext context) => switch (severity) {
      FindingSeverity.critical => context.tr('Critical'),
      FindingSeverity.high => context.tr('High'),
      FindingSeverity.medium => context.tr('Medium'),
      FindingSeverity.low => context.tr('Low'),
      FindingSeverity.info => context.tr('Informational'),
    };

Color _severityColor(FindingSeverity severity) => switch (severity) {
      FindingSeverity.critical => const Color(0xFFFF3B5C),
      FindingSeverity.high => const Color(0xFFFF7070),
      FindingSeverity.medium => Colors.orangeAccent,
      FindingSeverity.low => const Color(0xFF71B7FF),
      FindingSeverity.info => _securityMint,
    };

String _statusLabel(ActivityStatus status, BuildContext context) => switch (status) {
      ActivityStatus.started => context.tr('Started'),
      ActivityStatus.running => context.tr('Running'),
      ActivityStatus.completed => context.tr('Completed'),
      ActivityStatus.failed => context.tr('Failed'),
      ActivityStatus.cancelled => context.tr('Cancelled'),
    };

String _timeLabel(DateTime time) {
  final local = time.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
