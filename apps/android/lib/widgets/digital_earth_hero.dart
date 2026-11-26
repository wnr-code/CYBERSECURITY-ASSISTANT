import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

const _earthCyan = Color(0xFF36D9FF);
const _earthMint = Color(0xFF73F0C2);
const _earthPanel = Color(0xFF111D32);

/// Lightweight illustrative globe. It deliberately contains no live topology,
/// nodes, connection lines, attack markers, or telemetry.
class DigitalEarthHero extends StatefulWidget {
  const DigitalEarthHero({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  State<DigitalEarthHero> createState() => _DigitalEarthHeroState();
}

class _DigitalEarthHeroState extends State<DigitalEarthHero> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 96),
  );
  bool _appIsResumed = true;

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

  void _syncMotionPreference() {
    final shouldAnimate = _appIsResumed && !MediaQuery.of(context).disableAnimations && TickerMode.valuesOf(context).enabled;
    if (!shouldAnimate) {
      _rotation.stop();
    } else if (!_rotation.isAnimating) {
      _rotation.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('digital-earth-hero'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 276,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_earthPanel, Color(0xFF10182A), Color(0xFF142238)],
              ),
              border: Border.all(color: _earthCyan.withValues(alpha: .18)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      context.tr('DIGITAL EARTH'),
                      style: const TextStyle(color: _earthCyan, fontWeight: FontWeight.w800, letterSpacing: .6),
                    ),
                  ),
                  Text(
                    context.tr('IDLE'),
                    style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ]),
                const SizedBox(height: 4),
                Expanded(
                  child: Center(
                    child: Semantics(
                      image: true,
                      label: context.tr('Illustrative globe; network topology is unavailable; no nodes or connections are shown.'),
                      child: RepaintBoundary(
                        child: RotationTransition(
                          turns: _rotation,
                          child: const SizedBox(
                            width: 208,
                            height: 208,
                            child: CustomPaint(painter: _DigitalEarthPainter()),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  context.tr('Illustrative · no nodes or connection data'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: .66), fontSize: 11, letterSpacing: .2),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _DigitalEarthPainter extends CustomPainter {
  const _DigitalEarthPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = side * .43;
    final globe = Rect.fromCircle(center: center, radius: radius);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [_earthCyan.withValues(alpha: .14), _earthCyan.withValues(alpha: .025), Colors.transparent],
        stops: const [0, .62, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.38));
    canvas.drawCircle(center, radius * 1.38, glowPaint);

    canvas.save();
    canvas.clipPath(Path()..addOval(globe));
    final fill = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-.32, -.38),
        radius: 1.05,
        colors: [Color(0xFF16314E), Color(0xFF101B30), Color(0xFF0D1728)],
      ).createShader(globe);
    canvas.drawCircle(center, radius, fill);

    final grid = Paint()
      ..color = _earthCyan.withValues(alpha: .46)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;
    final latitude = Paint()
      ..color = _earthMint.withValues(alpha: .38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    canvas.drawOval(Rect.fromCenter(center: center, width: radius * 2, height: radius * .58), latitude);
    canvas.drawOval(Rect.fromCenter(center: center, width: radius * 2, height: radius * 1.18), grid);
    canvas.drawOval(Rect.fromCenter(center: center, width: radius * .82, height: radius * 2), grid);
    canvas.drawOval(Rect.fromCenter(center: center, width: radius * 1.48, height: radius * 2), grid);
    canvas.drawOval(Rect.fromCenter(center: center, width: radius * 2, height: radius * 2), Paint()
      ..color = _earthCyan.withValues(alpha: .94)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DigitalEarthPainter oldDelegate) => false;
}
