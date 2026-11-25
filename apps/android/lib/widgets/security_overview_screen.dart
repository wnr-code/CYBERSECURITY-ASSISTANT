import 'package:material_ui/material_ui.dart';

import '../core/activity_timeline.dart';
import '../core/assessment_progress.dart';
import '../core/security_findings.dart';
import '../core/security_tools.dart';
import '../l10n/app_localizations.dart';
import 'security_status_hero.dart';

const _overviewMint = Color(0xFF73F0C2);
const _overviewBlue = Color(0xFF36D9FF);

class SecurityOverviewScreen extends StatelessWidget {
  const SecurityOverviewScreen({
    super.key,
    required this.assessmentProgress,
    required this.activeAssessmentTarget,
    required this.latestAssessment,
    required this.findings,
    required this.findingsLoaded,
    required this.findingsBusy,
    required this.findingsError,
    required this.activityEvents,
    required this.activityLoaded,
    required this.activityBusy,
    required this.activityError,
    required this.onOpenAssessment,
    required this.onOpenFindings,
    required this.onOpenReports,
    required this.onOpenActivity,
  });

  final AssessmentProgressSnapshot? assessmentProgress;
  final String? activeAssessmentTarget;
  final ActivityEvent? latestAssessment;
  final List<FindingRecord> findings;
  final bool findingsLoaded;
  final bool findingsBusy;
  final String? findingsError;
  final List<ActivityEvent> activityEvents;
  final bool activityLoaded;
  final bool activityBusy;
  final String? activityError;
  final VoidCallback onOpenAssessment;
  final ValueChanged<FindingSeverity?> onOpenFindings;
  final VoidCallback onOpenReports;
  final ValueChanged<ActivityEvent> onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 360 ? 14.0 : 20.0;
    final findingsBySeverity = <FindingSeverity, int>{
      for (final severity in FindingSeverity.values)
        severity: findings.where((finding) => finding.severity == severity).length,
    };
    final recentEvents = activityEvents.take(5).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Security Overview')),
        leading: IconButton(
          tooltip: context.tr('Back'),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: EdgeInsets.fromLTRB(padding, 14, padding, 28),
            children: [
              SecurityStatusHero(
                assessmentProgress: assessmentProgress,
                activeAssessmentTarget: activeAssessmentTarget,
                latestAssessment: latestAssessment,
                activityLoaded: activityLoaded,
                activityBusy: activityBusy,
                activityError: activityError,
                findingsCount: findings.length,
                findingsBySeverity: findingsBySeverity,
                findingsLoaded: findingsLoaded,
                findingsBusy: findingsBusy,
                findingsError: findingsError,
              ),
              const SizedBox(height: 16),
              _OverviewSectionTitle(title: context.tr('Findings by severity'), icon: Icons.rule_folder_outlined),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: findingsBusy && !findingsLoaded
                      ? _OverviewState(icon: Icons.hourglass_top_rounded, text: context.tr('Loading local findings…'))
                      : findingsError != null && !findingsLoaded
                          ? _OverviewState(icon: Icons.error_outline_rounded, text: context.tr('Could not load local security findings.'))
                          : !findingsLoaded
                              ? _OverviewState(icon: Icons.hourglass_top_rounded, text: context.tr('Local findings are not available yet.'))
                              : findings.isEmpty
                                  ? _OverviewState(
                                      icon: Icons.rule_folder_outlined,
                                      text: context.tr('No saved findings yet. Run a permitted check to populate this repository.'),
                                    )
                                  : Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final severity in FindingSeverity.values)
                                          _SeverityButton(
                                            label: _severityLabel(severity, context),
                                            count: findingsBySeverity[severity]!,
                                            color: _severityColor(severity),
                                            onTap: () => onOpenFindings(severity),
                                          ),
                                      ],
                                    ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => onOpenFindings(null),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(context.tr('Open Findings')),
                ),
              ),
              const SizedBox(height: 12),
              _OverviewSectionTitle(title: context.tr('Network topology'), icon: Icons.hub_outlined),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.device_hub_outlined, color: _overviewBlue),
                    const SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.tr('Network map not available'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('Available tools record checks for a selected target; they do not collect asset relationships or network topology.'),
                        style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: onOpenAssessment,
                        icon: const Icon(Icons.radar_rounded),
                        label: Text(context.tr('View available assessments')),
                      ),
                    ])),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _OverviewSectionTitle(title: context.tr('Recent activity'), icon: Icons.history_rounded),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: activityBusy && !activityLoaded
                      ? _OverviewState(icon: Icons.hourglass_top_rounded, text: context.tr('Loading activity timeline…'))
                      : activityError != null && !activityLoaded
                          ? _OverviewState(icon: Icons.error_outline_rounded, text: context.tr('Could not load local activity history.'))
                          : !activityLoaded
                              ? _OverviewState(icon: Icons.hourglass_top_rounded, text: context.tr('Activity timeline is not available yet.'))
                              : recentEvents.isEmpty
                                  ? _OverviewState(icon: Icons.history_toggle_off_rounded, text: context.tr('No activity recorded yet'))
                                  : Column(children: [
                                      for (var i = 0; i < recentEvents.length; i++) ...[
                                        if (i > 0) const Divider(height: 1),
                                        _OverviewActivityRow(event: recentEvents[i], onTap: () => onOpenActivity(recentEvents[i])),
                                      ],
                                    ]),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: onOpenAssessment,
                  icon: const Icon(Icons.radar_rounded),
                  label: Text(context.tr('Assessment')),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenReports,
                  icon: const Icon(Icons.article_outlined),
                  label: Text(context.tr('Reports')),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewSectionTitle extends StatelessWidget {
  const _OverviewSectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: _overviewMint, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .25))),
      ]);
}

class _OverviewState extends StatelessWidget {
  const _OverviewState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: _overviewBlue, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 12, height: 1.4))),
      ]);
}

class _SeverityButton extends StatelessWidget {
  const _SeverityButton({required this.label, required this.count, required this.color, required this.onTap});
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: Material(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: color.withValues(alpha: .35))),
              child: Text('$label  $count', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      );
}

class _OverviewActivityRow extends StatelessWidget {
  const _OverviewActivityRow({required this.event, required this.onTap});
  final ActivityEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (event.status) {
      ActivityStatus.started || ActivityStatus.running => _overviewBlue,
      ActivityStatus.completed => _overviewMint,
      ActivityStatus.failed => Colors.orangeAccent,
      ActivityStatus.cancelled => Colors.white54,
    };
    final status = switch (event.status) {
      ActivityStatus.started => 'Started',
      ActivityStatus.running => 'Running',
      ActivityStatus.completed => 'Completed',
      ActivityStatus.failed => 'Failed',
      ActivityStatus.cancelled => 'Cancelled',
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          Icon(event.kind == ActivityKind.assessment
              ? Icons.radar_rounded
              : event.kind == ActivityKind.aiRequest
                  ? Icons.auto_awesome_outlined
                  : Icons.play_circle_outline_rounded, color: statusColor, size: 19),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.kind == ActivityKind.assessment
                ? context.tr('Assessment run')
                : event.kind == ActivityKind.aiRequest
                    ? context.tr('AI request')
                    : _toolLabel(event.toolId ?? '', context),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(event.target, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 11)),
          ])),
          const SizedBox(width: 8),
          Text(context.tr(status), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

String _toolLabel(String toolId, BuildContext context) => switch (toolId) {
      'dns_lookup' => context.tr('Pencarian DNS'),
      'tls_inspector' => context.tr('Inspeksi Sertifikat TLS'),
      'http_headers' => context.tr('Pemeriksa Header HTTP'),
      'response_analyzer' => context.tr('Analisis Temuan'),
      'terminal_workspace' => context.tr('Terminal workspace'),
      'cloudflare_accounts' => context.tr('Cloudflare Accounts Read'),
      'cloudflare_zones' => context.tr('Cloudflare Zones Read'),
      'cloudflare_zone_detail' => context.tr('Cloudflare Zone Details Read'),
      _ => context.tr('Tool activity'),
    };

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
      FindingSeverity.info => _overviewMint,
    };
