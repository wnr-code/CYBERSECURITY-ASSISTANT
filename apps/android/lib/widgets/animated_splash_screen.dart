import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/startup_trace.dart';
import '../l10n/app_localizations.dart';

const _splashNavy = Color(0xFF030817);
const _electricBlue = Color(0xFF168DFF);
const _cyan = Color(0xFF36D9FF);
const _brandWhite = Color(0xFFEAF8FF);

/// Animated Flutter handoff shown after the native Android launch splash.
/// Motion is vector/canvas based; loading is indeterminate because startup has
/// no measurable percentage, and the dashboard does not wait for SQLite.
class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen> with TickerProviderStateMixin {
  late final AnimationController _motion;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    StartupTrace.mark('animated-splash-init');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StartupTrace.mark('animated-splash-first-frame');
    });
    _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
    _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 760));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _motion
        ..stop()
        ..value = .22;
      _entrance
        ..stop()
        ..value = 1;
      return;
    }
    if (!_motion.isAnimating) _motion.repeat();
    if (!_entrance.isAnimating && _entrance.value == 0) _entrance.forward();
  }

  @override
  void dispose() {
    StartupTrace.mark('animated-splash-disposed');
    _motion.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Animation<double> _reveal(double start, double end) => CurvedAnimation(
        parent: _entrance,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );

  @override
  Widget build(BuildContext context) {
    final titleReveal = _reveal(0, .52);
    final taglineReveal = _reveal(.08, .58);
    final subtitleReveal = _reveal(.16, .66);
    final featuresReveal = _reveal(.22, .72);
    final loadingReveal = _reveal(.30, .78);

    return Scaffold(
      backgroundColor: _splashNavy,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -.08),
                    radius: 1.02,
                    colors: [Color(0xFF102652), Color(0xFF07132C), _splashNavy],
                    stops: [0, .58, 1],
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  key: const ValueKey('splash-digital-world-and-circuits'),
                  painter: _CyberGridPainter(_motion),
                ),
              ),
              SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _AnimatedShield(animation: _motion),
                        const SizedBox(height: 4),
                        Column(
                          children: [
                            _Reveal(animation: titleReveal, child: Text(
                              'CYBERSECURITY',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.4,
                                    height: 1.08,
                                  ),
                            )),
                            _Reveal(animation: titleReveal, child: Text(
                              'ASSISTANT',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    color: _cyan,
                                    fontWeight: FontWeight.w900,
                                    fontStyle: FontStyle.italic,
                                    letterSpacing: 2.2,
                                    height: 1.08,
                                    shadows: const [Shadow(color: _electricBlue, blurRadius: 18)],
                                  ),
                            )),
                            const SizedBox(height: 7),
                            _Reveal(
                              animation: taglineReveal,
                              child: Text(
                                context.tr('ANALYZE · PROTECT · IMPROVE'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white.withValues(alpha: .88), fontSize: 12, letterSpacing: .7),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _Reveal(
                              animation: subtitleReveal,
                              child: Text(
                                context.tr('A cybersecurity assistant for your digital world.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 12, height: 1.35),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _Reveal(
                          animation: featuresReveal,
                          child: _FeatureStrip(animation: _motion),
                        ),
                        const SizedBox(height: 4),
                        _Reveal(
                          animation: loadingReveal,
                          child: _StartupIndicator(animation: _motion),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, .14), end: Offset.zero).animate(animation),
          child: child,
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
            key: const ValueKey('splash-animated-shield'),
            width: 196,
            height: 174,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 142 + pulse * 12,
                  height: 142 + pulse * 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _electricBlue.withValues(alpha: .10 + pulse * .1)),
                    boxShadow: [
                      BoxShadow(color: _electricBlue.withValues(alpha: .18 + pulse * .16), blurRadius: 28 + pulse * 16),
                      BoxShadow(color: _cyan.withValues(alpha: .06 + pulse * .08), blurRadius: 50),
                    ],
                  ),
                ),
                Transform.rotate(
                  angle: animation.value * math.pi * 2,
                  child: Container(
                    width: 182,
                    height: 58,
                    decoration: BoxDecoration(
                      border: Border.all(color: _cyan.withValues(alpha: .52 + pulse * .28), width: 1.7),
                      borderRadius: const BorderRadius.all(Radius.elliptical(120, 42)),
                      boxShadow: [BoxShadow(color: _cyan.withValues(alpha: .16 + pulse * .12), blurRadius: 14)],
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: -animation.value * math.pi * 2 * .58,
                  child: Container(
                    width: 160,
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(color: _electricBlue.withValues(alpha: .42), width: 1.2),
                      borderRadius: const BorderRadius.all(Radius.elliptical(100, 36)),
                    ),
                  ),
                ),
                Icon(Icons.shield_rounded, size: 122, color: _electricBlue.withValues(alpha: .78 + pulse * .2)),
                Icon(Icons.lock_rounded, size: 48, color: _brandWhite.withValues(alpha: .88 + pulse * .12)),
                Positioned(
                  top: 20 + pulse * 5,
                  right: 31,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _cyan,
                      boxShadow: [BoxShadow(color: _cyan.withValues(alpha: .8), blurRadius: 11 + pulse * 5)],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _FeatureStrip extends StatelessWidget {
  const _FeatureStrip({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: _FeatureBadge(animation: animation, phase: 0, icon: Icons.security_rounded, label: context.tr('Integrated security'))),
          Expanded(child: _FeatureBadge(animation: animation, phase: .22, icon: Icons.auto_awesome_rounded, label: context.tr('AI Expert'))),
          Expanded(child: _FeatureBadge(animation: animation, phase: .48, icon: Icons.grid_view_rounded, label: context.tr('Complete tools'))),
          Expanded(child: _FeatureBadge(animation: animation, phase: .72, icon: Icons.analytics_rounded, label: context.tr('Deep analysis'))),
        ],
      );
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({required this.animation, required this.phase, required this.icon, required this.label});

  final Animation<double> animation;
  final double phase;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final pulse = (math.sin((animation.value + phase) * math.pi * 2) + 1) / 2;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _electricBlue.withValues(alpha: .08 + pulse * .08),
                    shape: BoxShape.circle,
                    border: Border.all(color: _cyan.withValues(alpha: .15 + pulse * .24)),
                    boxShadow: [BoxShadow(color: _electricBlue.withValues(alpha: .08 + pulse * .12), blurRadius: 13)],
                  ),
                  child: Icon(icon, size: 20, color: _cyan.withValues(alpha: .78 + pulse * .22)),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 9, height: 1.1, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        },
      );
}

class _StartupIndicator extends StatelessWidget {
  const _StartupIndicator({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: animation,
            builder: (context, _) => Transform.rotate(
              angle: animation.value * math.pi * 2,
              child: SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  value: null,
                  color: _cyan,
                  backgroundColor: _electricBlue.withValues(alpha: .14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('Loading app...'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('LOCAL FIRST · YOUR DATA STAYS ON DEVICE'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _cyan.withValues(alpha: .72), fontSize: 9, letterSpacing: 1),
          ),
        ],
      );
}

class _CyberGridPainter extends CustomPainter {
  _CyberGridPainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;

  static final List<Offset> _mapDots = _buildMapDots();

  static const List<List<Offset>> _continentShapes = [
    [Offset(.09, .12), Offset(.31, .10), Offset(.39, .26), Offset(.32, .44), Offset(.22, .46), Offset(.17, .35), Offset(.08, .31)],
    [Offset(.27, .45), Offset(.38, .48), Offset(.39, .66), Offset(.34, .91), Offset(.28, .78), Offset(.25, .60)],
    [Offset(.43, .22), Offset(.58, .17), Offset(.77, .20), Offset(.90, .30), Offset(.82, .42), Offset(.66, .39), Offset(.58, .48), Offset(.47, .39)],
    [Offset(.46, .42), Offset(.58, .43), Offset(.62, .59), Offset(.56, .82), Offset(.49, .73), Offset(.44, .54)],
    [Offset(.75, .59), Offset(.87, .60), Offset(.91, .72), Offset(.84, .81), Offset(.75, .76)],
    [Offset(.31, .04), Offset(.41, .03), Offset(.42, .12), Offset(.35, .16), Offset(.30, .11)],
  ];

  static List<Offset> _buildMapDots() {
    final dots = <Offset>[];
    const columns = 42;
    const rows = 27;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final point = Offset(column / (columns - 1), row / (rows - 1));
        if (_continentShapes.any((shape) => _insidePolygon(point, shape))) {
          // Tiny deterministic jitter gives the map a digital, particle-like edge.
          final jitterX = (((column * 17 + row * 11) % 7) - 3).toDouble() * .0012;
          final jitterY = (((column * 13 + row * 19) % 7) - 3).toDouble() * .0012;
          dots.add(Offset(point.dx + jitterX, point.dy + jitterY));
        }
      }
    }
    return dots;
  }

  static bool _insidePolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (var current = 0, previous = polygon.length - 1; current < polygon.length; previous = current++) {
      final a = polygon[current];
      final b = polygon[previous];
      final crosses = (a.dy > point.dy) != (b.dy > point.dy) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) / ((b.dy - a.dy).abs() < .00001 ? .00001 : b.dy - a.dy) + a.dx;
      if (crosses) inside = !inside;
    }
    return inside;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintDigitalMap(canvas, size);
    _paintCircuits(canvas, size);
    _paintPlatform(canvas, size);
  }

  void _paintDigitalMap(Canvas canvas, Size size) {
    final mapWidth = size.width * .72;
    final mapHeight = size.height * .40;
    final origin = Offset((size.width - mapWidth) / 2, size.height * .27);
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < _mapDots.length; index++) {
      final point = _mapDots[index];
      final flicker = (math.sin((animation.value * math.pi * 2) + index * .41) + 1) / 2;
      dotPaint.color = _cyan.withValues(alpha: .045 + flicker * .18);
      final radius = index % 9 == 0 ? 1.35 : .78;
      canvas.drawCircle(Offset(origin.dx + point.dx * mapWidth, origin.dy + point.dy * mapHeight), radius, dotPaint);
    }
    final markerPaint = Paint()..color = _cyan.withValues(alpha: .28);
    for (var index = 0; index < 5; index++) {
      final phase = (animation.value + index * .197) % 1;
      final point = _mapDots[(index * 23) % _mapDots.length];
      final center = Offset(origin.dx + point.dx * mapWidth, origin.dy + point.dy * mapHeight);
      canvas.drawCircle(center, 2 + phase * 5, markerPaint..color = _cyan.withValues(alpha: .12 * (1 - phase)));
      canvas.drawCircle(center, 1.3, markerPaint..color = _brandWhite.withValues(alpha: .68));
    }
  }

  void _paintCircuits(Canvas canvas, Size size) {
    final trace = Paint()
      ..color = _electricBlue.withValues(alpha: .22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final quietTrace = Paint()
      ..color = _electricBlue.withValues(alpha: .10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    final nodePaint = Paint()..color = _cyan.withValues(alpha: .32);
    final photons = Paint()..color = _cyan;
    final centerX = size.width / 2;

    for (var side = 0; side < 2; side++) {
      final fromLeft = side == 0;
      for (var index = 0; index < 6; index++) {
        final y = size.height * (.12 + index * .125);
        final edge = fromLeft ? 0.0 : size.width;
        final inward = fromLeft ? size.width * (.13 + (index % 2) * .055) : size.width * (.87 - (index % 2) * .055);
        final inner = centerX + (fromLeft ? -1 : 1) * size.width * (.22 + (index % 3) * .035);
        final path = Path()
          ..moveTo(edge, y)
          ..lineTo(inward, y)
          ..lineTo(inward, y + size.height * .025)
          ..lineTo(inner, y + size.height * .025);
        canvas.drawPath(path, index.isEven ? trace : quietTrace);
        canvas.drawCircle(Offset(inward, y), 2, nodePaint);

        final metric = path.computeMetrics().first;
        final photonPhase = (animation.value * (fromLeft ? 1 : -1) + index * .167 + (fromLeft ? 0 : 1)) % 1;
        final tangent = metric.getTangentForOffset(metric.length * photonPhase.abs());
        if (tangent != null) {
          canvas.drawCircle(tangent.position, 4, Paint()..color = _cyan.withValues(alpha: .16));
          canvas.drawCircle(tangent.position, 1.6, photons..color = _brandWhite.withValues(alpha: .9));
        }
      }
    }
  }

  void _paintPlatform(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .955);
    final pulse = (math.sin(animation.value * math.pi * 2) + 1) / 2;
    for (var ring = 0; ring < 4; ring++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(animation.value * math.pi * (ring.isEven ? 2 : -1.4) + ring * .32);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: size.width * (.48 + ring * .13), height: 12 + ring * 8),
        Paint()
          ..color = _electricBlue.withValues(alpha: .10 + (ring == 0 ? pulse * .16 : 0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring == 0 ? 1.4 : .8,
      );
      canvas.restore();
    }

    final halo = Paint()..color = _cyan.withValues(alpha: .55);
    for (var particle = 0; particle < 7; particle++) {
      final angle = animation.value * math.pi * 2 + particle * math.pi * 2 / 7;
      final radiusX = size.width * (.22 + (particle % 3) * .035);
      final radiusY = 9 + (particle % 3) * 4;
      canvas.drawCircle(Offset(center.dx + math.cos(angle) * radiusX, center.dy + math.sin(angle) * radiusY), 1.2 + (particle % 2) * .45, halo);
    }
    final glowRect = Rect.fromCenter(center: center, width: size.width * .46, height: 2);
    canvas.drawRect(glowRect, Paint()..color = _electricBlue.withValues(alpha: .08 + pulse * .08));
  }

  @override
  bool shouldRepaint(covariant _CyberGridPainter oldDelegate) => oldDelegate.animation != animation;
}
