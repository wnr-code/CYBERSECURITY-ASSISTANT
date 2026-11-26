import 'package:material_ui/material_ui.dart';

/// Uses recognizable brand marks for providers represented as brands in Market.
/// Local AI is a capability label, not a third-party brand, so it keeps a
/// neutral on-device icon instead of borrowing another company's identity.
class MarketBrandMark extends StatelessWidget {
  const MarketBrandMark({super.key, required this.providerId, this.diameter = 42});

  final String providerId;
  final double diameter;

  String? get _assetPath => switch (providerId) {
        'cloudflare' => 'assets/brands/cloudflare.png',
        'gemini' => 'assets/brands/googlegemini.png',
        _ => null,
      };

  Color get _brandColor => switch (providerId) {
        'cloudflare' => const Color(0xFFF38020),
        'gemini' => const Color(0xFF9B72CB),
        _ => const Color(0xFF20C8FF),
      };

  IconData get _fallbackIcon => switch (providerId) {
        'local_ai' => Icons.memory_rounded,
        _ => Icons.device_hub_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final assetPath = _assetPath;
    return Semantics(
      image: true,
      label: switch (providerId) {
        'cloudflare' => 'Cloudflare',
        'gemini' => 'Google Gemini',
        _ => 'Local AI',
      },
      child: CircleAvatar(
        radius: diameter / 2,
        backgroundColor: _brandColor.withValues(alpha: .12),
        child: assetPath == null
            ? Icon(_fallbackIcon, color: _brandColor, size: diameter * .56)
            : Padding(
                padding: EdgeInsets.all(diameter * .22),
                child: Image.asset(
                  assetPath,
                  width: diameter * .56,
                  height: diameter * .56,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
              ),
      ),
    );
  }
}
