import 'package:material_ui/material_ui.dart';

import '../core/activity_timeline.dart';
import '../core/assessment_progress.dart';
import '../core/package_manager.dart';
import '../core/security_findings.dart';
import '../core/security_tools.dart';
import '../core/tool_orchestrator.dart';
import '../core/tool_registry.dart';
import '../l10n/activity_localization.dart';
import '../l10n/app_localizations.dart';
import 'security_status_hero.dart';

const _dashboardMint = Color(0xFF73F0C2);
const _dashboardBlue = Color(0xFF36D9FF);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.recentResults,
    required this.savedResultCount,
    required this.savedHistoryLoaded,
    required this.findings,
    required this.findingsLoaded,
    required this.findingsBusy,
    required this.findingsError,
    required this.activityEvents,
    required this.activityLoaded,
    required this.activityBusy,
    required this.activityError,
    required this.marketPackageManager,
    required this.assessmentProgress,
    required this.activeAssessmentTarget,
    required this.onNavigateToTools,
    required this.onOpenCatalog,
    required this.onNavigateToReports,
    required this.onNavigateToFindings,
    required this.onOpenSecurityOverview,
    required this.onOpenAssistant,
    required this.onOpenActivity,
    required this.onOpenResult,
    required this.onSaveResult,
  });

  final List<ToolRunResult> recentResults;
  final int savedResultCount;
  final bool savedHistoryLoaded;
  final List<FindingRecord> findings;
  final bool findingsLoaded;
  final bool findingsBusy;
  final String? findingsError;
  final List<ActivityEvent> activityEvents;
  final bool activityLoaded;
  final bool activityBusy;
  final String? activityError;
  final MarketPackageManager marketPackageManager;
  final AssessmentProgressSnapshot? assessmentProgress;
  final String? activeAssessmentTarget;
  final VoidCallback onNavigateToTools;
  final VoidCallback onOpenCatalog;
  final VoidCallback onNavigateToReports;
  final ValueChanged<FindingSeverity?> onNavigateToFindings;
  final VoidCallback onOpenSecurityOverview;
  final VoidCallback onOpenAssistant;
  final ValueChanged<ActivityEvent> onOpenActivity;
  final ValueChanged<ToolRunResult> onOpenResult;
  final Future<bool> Function(ToolRunResult) onSaveResult;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<ToolAvailability?>> _toolAvailability;

  @override
  void initState() {
    super.initState();
    _toolAvailability = _resolveToolAvailability();
    widget.marketPackageManager.addListener(_refreshToolAvailability);
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marketPackageManager != widget.marketPackageManager) {
      oldWidget.marketPackageManager.removeListener(_refreshToolAvailability);
      widget.marketPackageManager.addListener(_refreshToolAvailability);
      _toolAvailability = _resolveToolAvailability();
    }
  }

  void _refreshToolAvailability() {
    _toolAvailability = _resolveToolAvailability();
    if (mounted) setState(() {});
  }

  Future<List<ToolAvailability?>> _resolveToolAvailability() async {
    final orchestrator = ToolOrchestrator(packageManager: widget.marketPackageManager);
    return Future.wait(toolRegistry.map((definition) async {
      try {
        return await orchestrator.availabilityForTool(definition.id);
      } catch (_) {
        return null;
      }
    }));
  }

  @override
  void dispose() {
    widget.marketPackageManager.removeListener(_refreshToolAvailability);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 14.0 : 20.0;
    final assessmentEvents = widget.activityEvents.where((event) => event.kind == ActivityKind.assessment).toList(growable: false);
    final latestAssessment = assessmentEvents.isEmpty ? null : _latestAssessment(assessmentEvents);
    final findingsBySeverity = <FindingSeverity, int>{
      for (final severity in FindingSeverity.values)
        severity: widget.findings.where((finding) => finding.severity == severity).length,
    };
    final running = widget.assessmentProgress;
    // Recent results also retain derived response analysis for review; it is
    // not a selected technical check and must not inflate this count.
    final sessionTechnicalCheckCount = widget.recentResults.where((result) => result.toolId != 'response_analyzer').length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          key: const ValueKey('dashboard-scroll-view'),
          padding: EdgeInsets.fromLTRB(horizontalPadding, 18, horizontalPadding, 28),
          children: [
            Text(context.tr('Your security workspace'), style: _dashboardEyebrow()),
            const SizedBox(height: 5),
            Text(
              context.tr('Security, with control in your hands.'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.12),
            ),
            const SizedBox(height: 5),
            Text(
              context.tr('Local-first overview · no live network map'),
              style: TextStyle(color: Colors.white.withValues(alpha: .7), height: 1.4),
            ),
            const SizedBox(height: 16),
            SecurityStatusHero(
              assessmentProgress: running,
              activeAssessmentTarget: widget.activeAssessmentTarget,
              latestAssessment: latestAssessment,
              activityLoaded: widget.activityLoaded,
              activityBusy: widget.activityBusy,
              activityError: widget.activityError,
              findingsCount: widget.findings.length,
              findingsBySeverity: findingsBySeverity,
              findingsLoaded: widget.findingsLoaded,
              findingsBusy: widget.findingsBusy,
              findingsError: widget.findingsError,
              onTap: widget.onOpenSecurityOverview,
            ),
            const SizedBox(height: 18),
            _DashboardHeading(title: context.tr('SECURITY INSTRUMENTS'), icon: Icons.tune_rounded),
            const SizedBox(height: 9),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                child: Column(children: [
                  _SecurityInstrument(
                    key: const ValueKey('instrument-security-score'),
                    icon: Icons.help_outline_rounded,
                    title: context.tr('Security Score'),
                    value: context.tr('Unavailable'),
                    detail: context.tr('Methodology not defined'),
                  ),
                  const Divider(height: 1),
                  _SecurityInstrument(
                    key: const ValueKey('instrument-risk-level'),
                    icon: Icons.remove_rounded,
                    title: context.tr('Risk Level'),
                    value: context.tr('Not calculated'),
                    detail: context.tr('Severity counts stay separate'),
                  ),
                  const Divider(height: 1),
                  _SecurityInstrument(
                    key: const ValueKey('instrument-scan-progress'),
                    icon: running == null ? Icons.remove_rounded : Icons.radar_rounded,
                    title: context.tr('Scan Progress'),
                    value: running == null ? context.tr('Idle') : '${running.processedCount} / ${running.selectedCount} ${context.tr('checks')}',
                    detail: running == null
                        ? context.tr('No assessment running')
                        : context.tr('Assessment checks are running'),
                    progress: running?.fraction,
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              context.tr('Security score and overall risk are unavailable until reviewed methods are defined.'),
              style: TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 20),
            _DashboardHeading(title: context.tr('SECURITY ANALYTICS'), icon: Icons.insights_rounded),
            const SizedBox(height: 9),
            _findingsCard(context, findingsBySeverity),
            const SizedBox(height: 10),
            _assessmentHistoryCard(context, assessmentEvents),
            const SizedBox(height: 10),
            _toolRegistryCard(context),
            const SizedBox(height: 10),
            _activityCard(context),
            const SizedBox(height: 18),
            _DashboardHeading(
              title: context.tr('Recent check results'),
              icon: Icons.fact_check_outlined,
              action: TextButton(onPressed: widget.onNavigateToReports, child: Text(context.tr('View reports'))),
            ),
            const SizedBox(height: 8),
            _recentResultsCard(context),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _CompactMetric(
                value: '${toolRegistry.length}',
                label: context.tr('Registry entries'),
                icon: Icons.grid_view_rounded,
                onTap: widget.onOpenCatalog,
              )),
              const SizedBox(width: 8),
              Expanded(child: _CompactMetric(
                value: '$sessionTechnicalCheckCount',
                label: context.tr('Session checks'),
                icon: Icons.bolt_rounded,
                onTap: widget.onNavigateToReports,
              )),
              const SizedBox(width: 8),
              Expanded(child: _CompactMetric(
                value: widget.savedHistoryLoaded ? '${widget.savedResultCount}' : '…',
                label: context.tr('Loaded saved reports'),
                icon: Icons.inventory_2_outlined,
                onTap: widget.onNavigateToReports,
              )),
            ]),
            const SizedBox(height: 14),
            _AssistantModuleCard(onOpen: widget.onOpenAssistant),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.privacy_tip_outlined, color: _dashboardMint),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    context.tr('Only assess systems you own or have permission to test. App confirmation is not legal proof of authorization.'),
                    style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12, height: 1.45),
                  )),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _findingsCard(BuildContext context, Map<FindingSeverity, int> counts) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(context.tr('Findings by severity'), style: _cardEyebrow())),
              _DataScopePill(label: context.tr('Loaded set')),
            ]),
            const SizedBox(height: 12),
            if (widget.findingsBusy && !widget.findingsLoaded)
              _DashboardInlineState(label: context.tr('Loading local findings…'), icon: Icons.hourglass_top_rounded)
            else if (widget.findingsError != null)
              _DashboardInlineState(label: context.tr('Could not load local security findings.'), icon: Icons.error_outline_rounded)
            else if (!widget.findingsLoaded)
              _DashboardInlineState(label: context.tr('Local findings are not available yet.'), icon: Icons.hourglass_top_rounded)
            else if (widget.findings.isEmpty) ...[
              Text('0 ${context.tr('findings in loaded records')}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(context.tr('No findings in this loaded view'), style: _mutedBody()),
              const SizedBox(height: 3),
              Text(context.tr('This does not mean the system is risk-free.'), style: _mutedBody()),

            ] else ...[
              Text('${widget.findings.length} ${context.tr('findings in loaded records')}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 9),
              Wrap(spacing: 7, runSpacing: 7, children: [
                for (final severity in FindingSeverity.values)
                  _SeverityCountChip(
                    label: _severityName(severity, context),
                    count: counts[severity]!,
                    color: _severityColor(severity),
                    onTap: widget.findingsLoaded ? () => widget.onNavigateToFindings(severity) : null,
                  ),
              ]),
            ],
            if (widget.findingsLoaded && widget.findings.isEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 7, runSpacing: 7, children: [
                for (final severity in FindingSeverity.values)
                  _SeverityCountChip(
                    label: _severityName(severity, context),
                    count: 0,
                    color: _severityColor(severity),
                    onTap: () => widget.onNavigateToFindings(severity),
                  ),
              ]),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => widget.onNavigateToFindings(null),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(context.tr('Open Findings')),
              ),
            ),
          ]),
        ),
      );

  Widget _assessmentHistoryCard(BuildContext context, List<ActivityEvent> assessmentEvents) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('Assessment history'), style: _cardEyebrow()),
            const SizedBox(height: 13),
            if (widget.activityBusy && !widget.activityLoaded)
              _DashboardInlineState(label: context.tr('Loading activity timeline…'), icon: Icons.hourglass_top_rounded)
            else if (widget.activityError != null)
              _DashboardInlineState(label: context.tr('Could not load local activity history.'), icon: Icons.error_outline_rounded)
            else if (!widget.activityLoaded)
              _DashboardInlineState(label: context.tr('Activity timeline is not available yet.'), icon: Icons.hourglass_top_rounded)
            else if (assessmentEvents.isEmpty) ...[
              Text(context.tr('No assessment history yet'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(context.tr('Run a permitted assessment to build local history.'), style: _mutedBody()),
            ] else ...[
              Text('${assessmentEvents.length} ${context.tr('assessment runs in loaded records')}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(_assessmentStatusSummary(assessmentEvents, context), style: _mutedBody()),
              const SizedBox(height: 3),
              Text(context.tr('Loaded Activity Timeline records only; not all-time.'), style: _scopeText()),
            ],
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onNavigateToTools,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(context.tr('Open Assessment')),
              ),
            ),
          ]),
        ),
      );

  Widget _toolRegistryCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('Tool Registry status'), style: _cardEyebrow()),
            const SizedBox(height: 10),
            FutureBuilder<List<ToolAvailability?>>(
              future: _toolAvailability,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return _DashboardInlineState(label: context.tr('Checking tool readiness…'), icon: Icons.sync_rounded);
                }
                final data = snapshot.data;
                if (snapshot.hasError || data == null) {
                  return _DashboardInlineState(label: context.tr('Could not determine tool status.'), icon: Icons.error_outline_rounded);
                }
                final executable = data.whereType<ToolAvailability>().where((item) => item.adapterRegistered).length;
                final ready = data.whereType<ToolAvailability>().where((item) => item.ready).length;
                final unresolved = data.where((item) => item == null).length;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr('Readiness is resolved on device'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 7),
                  Wrap(spacing: 7, runSpacing: 7, children: [
                    _RegistryCount(label: context.tr('Registry entries'), value: toolRegistry.length, color: _dashboardBlue),
                    _RegistryCount(label: context.tr('Executable'), value: executable, color: const Color(0xFF8AB8FF)),
                    _RegistryCount(label: context.tr('Ready'), value: ready, color: _dashboardMint),
                  ]),
                  if (unresolved > 0) ...[
                    const SizedBox(height: 5),
                    Text('$unresolved ${context.tr('tool status unresolved')}', style: _scopeText()),
                  ],
                  const SizedBox(height: 3),
                  Text(context.tr('Registry entries are not the same as executable or ready tools.'), style: _scopeText()),
                ]);
              },
            ),
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onOpenCatalog,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(context.tr('Open Catalog')),
              ),
            ),
          ]),
        ),
      );

  Widget _activityCard(BuildContext context) {
    final events = widget.activityEvents.take(3).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _DashboardHeading(
            title: context.tr('Recent activity'),
            icon: Icons.history_rounded,
          ),
          const SizedBox(height: 7),
          if (widget.activityBusy && !widget.activityLoaded)
            _DashboardInlineState(label: context.tr('Loading activity timeline…'), icon: Icons.hourglass_top_rounded)
          else if (widget.activityError != null)
            _DashboardInlineState(label: context.tr('Could not load local activity history.'), icon: Icons.error_outline_rounded)
          else if (!widget.activityLoaded)
            _DashboardInlineState(label: context.tr('Activity timeline is not available yet.'), icon: Icons.hourglass_top_rounded)
          else if (events.isEmpty)
            _DashboardInlineState(label: context.tr('No activity recorded yet'), icon: Icons.history_toggle_off_rounded,
                detail: context.tr('Only attempted work recorded in Activity Timeline appears here.'))
          else
            for (var index = 0; index < events.length; index++) ...[
              if (index > 0) const Divider(height: 1),
              _ActivityPreviewRow(
                event: events[index],
                onTap: () => widget.onOpenActivity(events[index]),
              ),
            ],
        ]),
      ),
    );
  }

  Widget _recentResultsCard(BuildContext context) {
    if (widget.recentResults.isEmpty) {
      return _DashboardEmptyCard(
        icon: Icons.fact_check_outlined,
        title: context.tr('No checks yet'),
        detail: context.tr('Start an authorized check from the tool catalog. Results will appear here.'),
        action: TextButton.icon(onPressed: widget.onOpenCatalog, icon: const Icon(Icons.arrow_forward_rounded), label: Text(context.tr('Open Catalog'))),
      );
    }
    return Column(children: [
      for (final result in widget.recentResults.take(3)) ...[
        Card(
          child: InkWell(
            key: ValueKey('dashboard-result-${result.toolId}-${result.completedAt.microsecondsSinceEpoch}'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => widget.onOpenResult(result),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                const Icon(Icons.fact_check_outlined, color: _dashboardMint),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_toolName(result.toolId, context), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('${result.target} · ${result.summary}', maxLines: 2, overflow: TextOverflow.ellipsis, style: _mutedBody()),
                  const SizedBox(height: 2),
                  Text(context.tr('Session result'), style: TextStyle(color: _dashboardMint.withValues(alpha: .9), fontSize: 11, fontWeight: FontWeight.w600)),
                ])),
                IconButton(
                  tooltip: context.tr('Save report locally'),
                  onPressed: () => widget.onSaveResult(result),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 7),
      ],
    ]);
  }
}

class _SecurityInstrument extends StatelessWidget {
  const _SecurityInstrument({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final double? progress;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: progress ?? 0,
                strokeWidth: 3,
                backgroundColor: const Color(0xFF33415B),
                color: _dashboardMint,
                semanticsLabel: title,
              ),
              Icon(icon, size: 19, color: _dashboardMint),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .25)),
            const SizedBox(height: 2),
            Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: _scopeText()),
          ])),
        ]),
      );
}

class _DashboardHeading extends StatelessWidget {
  const _DashboardHeading({required this.title, required this.icon, this.action});
  final String title;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: _dashboardMint),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: _cardEyebrow())),
        if (action != null) action!,
      ]);
}

class _DashboardInlineState extends StatelessWidget {
  const _DashboardInlineState({required this.label, required this.icon, this.detail});
  final String label;
  final IconData icon;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: Colors.white54),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (detail != null) ...[const SizedBox(height: 3), Text(detail!, style: _mutedBody())],
          ])),
        ]),
      );
}

class _DashboardEmptyCard extends StatelessWidget {
  const _DashboardEmptyCard({required this.icon, required this.title, required this.detail, this.action});
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: _dashboardMint),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(detail, style: _mutedBody()),
              if (action != null) Align(alignment: Alignment.centerLeft, child: action!),
            ])),
          ]),
        ),
      );
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.value, required this.label, required this.icon, required this.onTap});
  final String value;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: _dashboardMint, size: 18),
              const SizedBox(height: 5),
              Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 10, height: 1.25)),
            ]),
          ),
        ),
      );
}

class _DataScopePill extends StatelessWidget {
  const _DataScopePill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xFF12243B), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: const TextStyle(color: _dashboardBlue, fontSize: 10, fontWeight: FontWeight.w800)),
      );
}

class _SeverityCountChip extends StatelessWidget {
  const _SeverityCountChip({required this.label, required this.count, required this.color, this.onTap});
  final String label;
  final int count;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: color.withValues(alpha: .35)),
              ),
              child: Text('$label  $count', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
}

class _RegistryCount extends StatelessWidget {
  const _RegistryCount({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
        child: Text('$label  $value', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class _ActivityPreviewRow extends StatelessWidget {
  const _ActivityPreviewRow({required this.event, required this.onTap});
  final ActivityEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = event.kind == ActivityKind.assessment
        ? context.tr('Assessment run')
        : event.kind == ActivityKind.aiRequest
            ? context.tr('AI request')
            : _toolName(event.toolId ?? '', context);
    final statusColor = switch (event.status) {
      ActivityStatus.started || ActivityStatus.running => const Color(0xFF71B7FF),
      ActivityStatus.completed => _dashboardMint,
      ActivityStatus.failed => Colors.orangeAccent,
      ActivityStatus.cancelled => Colors.white54,
    };
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(event.kind == ActivityKind.assessment
                ? Icons.radar_rounded
                : event.kind == ActivityKind.aiRequest
                    ? Icons.auto_awesome_outlined
                    : Icons.play_circle_outline_rounded, color: statusColor, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(event.target, maxLines: 1, overflow: TextOverflow.ellipsis, style: _scopeText()),
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_activityStatus(event.status, context), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
              Text(_timeLabel(event.startedAt), style: _scopeText()),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _AssistantModuleCard extends StatelessWidget {
  const _AssistantModuleCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: const Color(0xFF8066FF).withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFAA9AFF)),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('AI assistant module'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(context.tr('Not connected · local security tools remain available'), style: _scopeText()),
              ])),
              const Icon(Icons.arrow_forward_rounded),
            ]),
          ),
        ),
      );
}

TextStyle _dashboardEyebrow() => const TextStyle(
      color: _dashboardMint,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1,
    );

TextStyle _cardEyebrow() => TextStyle(
      color: Colors.white.withValues(alpha: .7),
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: .45,
    );

TextStyle _mutedBody() => TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 12, height: 1.4);
TextStyle _scopeText() => TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 11, height: 1.35);

String _severityName(FindingSeverity severity, BuildContext context) => switch (severity) {
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
      FindingSeverity.info => _dashboardMint,
    };

ActivityEvent _latestAssessment(List<ActivityEvent> events) {
  final ordered = List<ActivityEvent>.of(events)..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return ordered.first;
}

String _assessmentStatusSummary(List<ActivityEvent> events, BuildContext context) {
  final completed = events.where((event) => event.status == ActivityStatus.completed).length;
  final failed = events.where((event) => event.status == ActivityStatus.failed).length;
  final cancelled = events.where((event) => event.status == ActivityStatus.cancelled).length;
  final active = events.where((event) => event.status == ActivityStatus.started || event.status == ActivityStatus.running).length;
  return '${context.tr('Completed')}: $completed · ${context.tr('Failed')}: $failed · ${context.tr('Cancelled')}: $cancelled${active == 0 ? '' : ' · ${context.tr('Running')}: $active'}';
}

String _activityStatus(ActivityStatus status, BuildContext context) => switch (status) {
      ActivityStatus.started => context.tr('Started'),
      ActivityStatus.running => context.tr('Running'),
      ActivityStatus.completed => context.tr('Completed'),
      ActivityStatus.failed => context.tr('Failed'),
      ActivityStatus.cancelled => context.tr('Cancelled'),
    };

String _toolName(String id, BuildContext context) => switch (id) {
      'dns_lookup' => context.tr('DNS Lookup'),
      'tls_inspector' => context.tr('TLS Certificate Inspection'),
      'http_headers' => context.tr('HTTP Security Header Checker'),
      'response_analyzer' => context.tr('Security Response Analyzer'),
      'terminal_workspace' => context.tr('Terminal workspace'),
      'cloudflare_accounts' => context.tr('Cloudflare Accounts Read'),
      'cloudflare_zones' => context.tr('Cloudflare Zones Read'),
      'cloudflare_zone_detail' => context.tr('Cloudflare Zone Details Read'),
      _ => id.isEmpty ? context.tr('Tool activity') : id,
    };

String _timeLabel(DateTime time) {
  final local = time.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
