import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'ai_shield_robot_mark.dart';

/// Animated assistant identity mark used beside assistant copy in Chat AI.
/// A green check is shown only after the provider's explicit connection test
/// succeeds; it says nothing about the correctness of generated responses.
class AiAssistantAvatar extends StatefulWidget {
  const AiAssistantAvatar({super.key, this.diameter = 40, this.connectionVerified = false});

  final double diameter;
  final bool connectionVerified;

  @override
  State<AiAssistantAvatar> createState() => _AiAssistantAvatarState();
}

class _AiAssistantAvatarState extends State<AiAssistantAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _motion.value = 1;
    } else if (_motion.value == 0) {
      _motion.forward();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: context.tr(widget.connectionVerified
            ? 'AI provider connection test succeeded.'
            : 'AI provider connection has not been verified.'),
        child: SizedBox(
          width: widget.diameter,
          height: widget.diameter,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF164A88), Color(0xFF07162D)],
                ),
                border: Border.all(color: const Color(0xFF168DFF).withValues(alpha: .82)),
                boxShadow: [BoxShadow(color: const Color(0xFF168DFF).withValues(alpha: .24), blurRadius: 12)],
              ),
            ),
            AnimatedBuilder(
              animation: _motion,
              builder: (context, _) {
                final progress = _motion.value;
                return Transform.translate(
                  offset: Offset(0, -math.sin(progress * math.pi) * 1.1),
                  child: AiShieldRobotMark(progress: progress),
                );
              },
            ),
            if (widget.connectionVerified)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: widget.diameter * .38,
                  height: widget.diameter * .38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF73F0C2),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0B1020), width: 1.5),
                    boxShadow: [BoxShadow(color: const Color(0xFF73F0C2).withValues(alpha: .35), blurRadius: 5)],
                  ),
                  child: Icon(Icons.check_rounded, size: widget.diameter * .27, color: const Color(0xFF0B1020)),
                ),
              ),
          ]),
        ),
      );
}
