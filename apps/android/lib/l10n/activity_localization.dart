import 'package:flutter/widgets.dart';

import '../core/activity_timeline.dart';
import 'app_localizations.dart';

/// Localizes bounded assessment summaries and app-owned terminal audit labels,
/// preserving unknown future summaries verbatim.
String activitySummaryText(ActivityEvent event, BuildContext context) {
  final summary = event.summary ?? '';
  if (event.kind == ActivityKind.aiRequest) {
    return switch (summary) {
      'Assistant request started.' => context.tr('AI request started.'),
      'Assistant request completed.' => context.tr('AI request completed.'),
      'Assistant request failed; prompt content was not recorded.' => context.tr('AI request failed; prompt content was not recorded.'),
      _ => summary,
    };
  }
  if (event.kind == ActivityKind.tool && event.toolId?.startsWith('cloudflare_') == true) {
    return context.tr(summary);
  }
  if (event.kind == ActivityKind.tool && event.toolId == 'terminal_workspace') {
    if (AppLocalizations.of(context).locale.languageCode != 'id') return summary;
    final action = RegExp(r'^Terminal session action: ([a-z_]+)\.$').firstMatch(summary)?.group(1);
    if (action == null) return summary;
    final localizedAction = switch (action) {
      'help' => 'bantuan',
      'status' => 'pemeriksaan status',
      'tools' => 'daftar tool',
      'run' => 'menjalankan tool',
      'session_exit' => 'keluar dari sesi',
      _ => 'perintah tidak valid',
    };
    return 'Aktivitas terminal: $localizedAction.';
  }
  if (AppLocalizations.of(context).locale.languageCode != 'id' || event.kind != ActivityKind.assessment) {
    return summary;
  }

  final counts = RegExp(r'^(\d+) checks completed, (\d+) failed, (\d+) skipped \(partial\), (\d+) cancelled\.$').firstMatch(summary);
  if (counts != null) {
    return '${counts.group(1)} pemeriksaan selesai · ${counts.group(2)} gagal · '
        '${counts.group(3)} dilewati (parsial) · ${counts.group(4)} dibatalkan';
  }
  final oneCount = RegExp(r'^(\d+) checks completed\.$').firstMatch(summary);
  if (oneCount != null) return '${oneCount.group(1)} pemeriksaan selesai.';
  return switch (summary) {
    'Assessment cancelled.' => 'Assessment dibatalkan.',
    'Assessment ended before completion.' => 'Assessment berakhir sebelum selesai.',
    _ => summary,
  };
}
