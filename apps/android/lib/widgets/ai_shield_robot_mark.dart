import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Small animated robot-in-shield mark for the secondary AI navigation action.
/// The parent controls a finite entrance/tap animation so the idle dashboard
/// does not keep a ticker alive indefinitely.
class AiShieldRobotMark extends StatelessWidget {
  const AiShieldRobotMark({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size.square(30),
        painter: _AiShieldRobotPainter(progress: progress.clamp(0, 1).toDouble()),
      );
}

class _AiShieldRobotPainter extends CustomPainter {
  const _AiShieldRobotPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    final bob = -math.sin(progress * math.pi) * 1.15;
    final scale = .88 + progress * .12;
    canvas.translate(12, 12 + bob);
    canvas.scale(scale);
    canvas.translate(-12, -12);

    final shield = Path()
      ..moveTo(12, 1.4)
      ..lineTo(21, 4.6)
      ..lineTo(20.6, 11.2)
      ..cubicTo(20.3, 16.5, 16.4, 20.4, 12, 22.6)
      ..cubicTo(7.6, 20.4, 3.7, 16.5, 3.4, 11.2)
      ..lineTo(3, 4.6)
      ..close();
    const shieldBounds = Rect.fromLTWH(3, 1.4, 18, 21.2);
    canvas.drawPath(
      shield,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E77B9), Color(0xFF10284A), Color(0xFF07162D)],
        ).createShader(shieldBounds),
    );
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Color.lerp(const Color(0xFF65BFFF), const Color(0xFF9BEAFF), progress)!,
    );

    final antennaPaint = Paint()
      ..color = const Color(0xFF9BEAFF)
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(12, 5.8), const Offset(12, 7.5), antennaPaint);
    canvas.drawCircle(const Offset(12, 4.6), 1.05, Paint()..color = const Color(0xFF8BE3FF));

    final face = RRect.fromRectAndRadius(const Rect.fromLTWH(6.2, 7.1, 11.6, 9.7), const Radius.circular(2.7));
    canvas.drawRRect(face, Paint()..color = const Color(0xFF081A31));
    canvas.drawRRect(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .95
        ..color = const Color(0xFF8BE3FF),
    );
    canvas.drawLine(const Offset(5.2, 10.4), const Offset(6.1, 10.4), antennaPaint);
    canvas.drawLine(const Offset(17.9, 10.4), const Offset(18.8, 10.4), antennaPaint);

    final eyeBrightness = .7 + progress * .3;
    final eyePaint = Paint()..color = Color.lerp(const Color(0xFF61C7FF), const Color(0xFFE1FAFF), eyeBrightness)!;
    canvas.drawCircle(const Offset(9.4, 11), 1.1, eyePaint);
    canvas.drawCircle(const Offset(14.6, 11), 1.1, eyePaint);
    canvas.drawLine(
      const Offset(9.8, 14.1),
      const Offset(14.2, 14.1),
      Paint()
        ..color = const Color(0xFF73F0C2)
        ..strokeWidth = 1.05
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AiShieldRobotPainter oldDelegate) => oldDelegate.progress != progress;
}
