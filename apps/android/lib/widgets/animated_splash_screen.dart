import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

const _splashNavy = Color(0xFF030817);
const _electricBlue = Color(0xFF168DFF);
const _cyan = Color(0xFF36D9FF);

/// Animated visual shell for the real startup work (local history initialization).
/// Its progress indicator is intentionally indeterminate: no fake percentage is shown.
class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _motion.stop();
      _motion.value = .28;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _splashNavy,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(fit: StackFit.expand, children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(.0, -.06),
                    radius: 1.02,
                    colors: [Color(0xFF0B1E43), Color(0xFF050D20), _splashNavy],
                    stops: [0, .58, 1],
                  ),
                ),
              ),
              Positioned.fill(child: CustomPaint(painter: _CircuitPainter(_motion))),
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _AnimatedShield(animation: _motion),
                        const SizedBox(height: 10),
                        Column(children: [
                          Text(
                            'CYBERSECURITY',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.8,
                                  height: 1.1,
                                ),
                          ),
                          Text(
                            'ASSISTANT',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  color: _cyan,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: 2.4,
                                  height: 1.12,
                                  shadows: [const Shadow(color: _electricBlue, blurRadius: 18)],
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('ANALYZE · PROTECT · STAY IN CONTROL'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 14, letterSpacing: .5),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: 200,
                            height: 2,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Colors.transparent, _electricBlue, _cyan, _electricBlue, Colors.transparent]),
                              boxShadow: [BoxShadow(color: _electricBlue.withValues(alpha: .5), blurRadius: 8)],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.tr('A local-first cybersecurity assistant for your digital world.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 14, height: 1.4),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        const _StartupCapabilities(),
                        const SizedBox(height: 10),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: _cyan,
                              backgroundColor: _electricBlue.withValues(alpha: .14),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.tr('Initializing local history…'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.tr('LOCAL FIRST · YOUR DATA STAYS ON DEVICE'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _cyan.withValues(alpha: .76), fontSize: 10, letterSpacing: 1.2),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _AnimatedShield extends StatelessWidget {
  const _AnimatedShield({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final pulse = (math.sin(animation.value * math.pi * 2) + 1) / 2;
          return SizedBox(
            width: 220,
            height: 198,
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: 176 + pulse * 8,
                height: 176 + pulse * 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _electricBlue.withValues(alpha: .12 + pulse * .1)),
                  boxShadow: [BoxShadow(color: _electricBlue.withValues(alpha: .13 + pulse * .1), blurRadius: 42 + pulse * 12)],
                ),
              ),
              Transform.rotate(
                angle: animation.value * math.pi * 2,
                child: Container(
                  width: 205,
                  height: 64,
                  decoration: BoxDecoration(
                    border: Border.all(color: _cyan.withValues(alpha: .72), width: 2),
                    borderRadius: const BorderRadius.all(Radius.elliptical(120, 42)),
                    boxShadow: [BoxShadow(color: _cyan.withValues(alpha: .28), blurRadius: 16)],
                  ),
                ),
              ),
              Icon(Icons.shield_outlined, size: 154, color: _electricBlue.withValues(alpha: .82 + pulse * .15)),
              const Icon(Icons.lock_outline_rounded, size: 58, color: Color(0xFFEAF8FF)),
              Positioned(
                top: 24,
                right: 30,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _cyan, boxShadow: [BoxShadow(color: _cyan.withValues(alpha: .8), blurRadius: 12)]),
                ),
              ),
            ]),
          );
        },
      );
}

class _StartupCapabilities extends StatelessWidget {
  const _StartupCapabilities();

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: _Capability(icon: Icons.verified_user_outlined, label: context.tr('Local'), detail: context.tr('Security'))),
        _capabilityDivider,
        Expanded(child: _Capability(icon: Icons.grid_view_rounded, label: context.tr('Tools'), detail: context.tr('Built-in'))),
        _capabilityDivider,
        Expanded(child: _Capability(icon: Icons.storage_outlined, label: 'SQLite', detail: context.tr('History'))),
        _capabilityDivider,
        Expanded(child: _Capability(icon: Icons.auto_awesome_outlined, label: context.tr('AI optional'), detail: context.tr('Not connected'))),
      ]);

  static const _capabilityDivider = Padding(
    padding: EdgeInsets.symmetric(horizontal: 5),
    child: SizedBox(height: 46, child: VerticalDivider(width: 1, color: Color(0x5536D9FF))),
  );
}

class _Capability extends StatelessWidget {
  const _Capability({required this.icon, required this.label, required this.detail});
  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 27, color: _cyan),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(detail, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 9)),
      ]);
}

class _CircuitPainter extends CustomPainter {
  _CircuitPainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final trace = Paint()
      ..color = _electricBlue.withValues(alpha: .19)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final quietTrace = Paint()
      ..color = _electricBlue.withValues(alpha: .1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    final nodePaint = Paint()..color = _cyan.withValues(alpha: .5);
    final centerX = size.width / 2;

    for (var side = 0; side < 2; side++) {
      final fromLeft = side == 0;
      for (var index = 0; index < 5; index++) {
        final y = size.height * (.1 + index * .16);
        final edge = fromLeft ? 0.0 : size.width;
        final inward = fromLeft ? size.width * (.13 + (index % 2) * .07) : size.width * (.87 - (index % 2) * .07);
        final path = Path()
          ..moveTo(edge, y)
          ..lineTo(inward, y)
          ..lineTo(inward, y + size.height * .025)
          ..lineTo(centerX + (fromLeft ? -1 : 1) * size.width * (.13 + (index % 3) * .025), y + size.height * .025);
        canvas.drawPath(path, index.isEven ? trace : quietTrace);
        canvas.drawCircle(Offset(inward, y), 2.2, nodePaint);
      }
    }

    final ringPaint = Paint()
      ..color = _electricBlue.withValues(alpha: .15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var ring = 0; ring < 3; ring++) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(centerX, size.height * .955), width: size.width * (.65 + ring * .17), height: 18 + ring * 11),
        ringPaint,
      );
    }

    final pulseX = size.width * animation.value;
    final pulseY = size.height * (.13 + .68 * ((animation.value * 1.7) % 1));
    canvas.drawCircle(Offset(pulseX, pulseY), 4, Paint()..color = _cyan.withValues(alpha: .16));
    canvas.drawCircle(Offset(pulseX, pulseY), 1.8, Paint()..color = _cyan.withValues(alpha: .8));
  }

  @override
  bool shouldRepaint(covariant _CircuitPainter oldDelegate) => oldDelegate.animation != animation;
}
