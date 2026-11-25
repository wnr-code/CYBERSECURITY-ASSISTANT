import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

const _edgePanelMint = Color(0xFF73F0C2);

/// Slide-over shortcuts for app features. Cloudflare opens a read-only dashboard
/// shell after token verification; service operations remain disabled until
/// permission-specific adapters are implemented and checked.
class EdgePanel extends StatelessWidget {
  const EdgePanel({
    super.key,
    required this.cloudflareConnected,
    required this.geminiConnected,
    required this.onOpenCloudflareDashboard,
    required this.onOpenGeminiDetails,
    required this.onClose,
    required this.onOpenTerminal,
    required this.onOpenAssessment,
  });

  final bool cloudflareConnected;
  final bool geminiConnected;
  final VoidCallback onOpenCloudflareDashboard;
  final VoidCallback onOpenGeminiDetails;
  final VoidCallback onClose;
  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenAssessment;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF10192B),
        elevation: 18,
        child: SafeArea(
          child: SizedBox(
            width: math.min(328.0, math.max(0.0, MediaQuery.sizeOf(context).width - 24)),
            child: ListView(padding: EdgeInsets.zero, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
                child: Row(children: [
                  const Icon(Icons.bolt_rounded, color: _edgePanelMint),
                  const SizedBox(width: 9),
                  Expanded(child: Text(context.tr('Edge Panel'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  IconButton(tooltip: context.tr('Tutup'), onPressed: onClose, icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 7),
                child: Text(context.tr('ACTIVE PROVIDER ACTIONS'),
                    style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .7)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Text(
                  context.tr(cloudflareConnected
                      ? 'Cloudflare token verified. Account and zone read access must be checked separately in the Dashboard; DNS records, Workers, and write operations remain unavailable.'
                      : geminiConnected
                          ? 'Gemini connection is verified. Prompts and approved tool results still require explicit data-sharing approval in Assistant.'
                          : 'No provider is connected yet. Market setup and local assessment tools remain available.'),
                  style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12, height: 1.4),
                ),
              ),
              if (cloudflareConnected)
                ListTile(
                  leading: const Icon(Icons.cloud_rounded, color: Color(0xFFF38020)),
                  title: Text(context.tr('Cloudflare Dashboard')),
                  subtitle: Text(context.tr('Read-only accounts and zones · no write actions')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onOpenCloudflareDashboard,
                ),
              if (geminiConnected)
                ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF9A8BFF)),
                  title: Text(context.tr('Gemini Details')),
                  subtitle: Text(context.tr('Provider-scoped sharing consent · tool actions still need separate review')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onOpenGeminiDetails,
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 7),
                child: Text(context.tr('AVAILABLE FEATURES'),
                    style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .7)),
              ),
              ListTile(
                leading: const Icon(Icons.terminal_rounded, color: _edgePanelMint),
                title: Text(context.tr('Floating Terminal')),
                subtitle: Text(context.tr('Built-in safe commands · not Termux or a system shell')),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: onOpenTerminal,
              ),
              ListTile(leading: const Icon(Icons.radar_rounded), title: Text(context.tr('Assessment')), onTap: onOpenAssessment),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(context.tr('The terminal accepts registered commands only; it is not a system shell.'),
                    style: TextStyle(color: Colors.white.withValues(alpha: .52), fontSize: 11, height: 1.4)),
              ),
            ]),
          ),
        ),
      );
}
