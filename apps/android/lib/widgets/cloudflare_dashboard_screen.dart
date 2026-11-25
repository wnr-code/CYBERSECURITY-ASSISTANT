import 'package:material_ui/material_ui.dart';

import '../core/market_provider_manager.dart';
import '../l10n/app_localizations.dart';
import 'market_provider_dialog.dart';

class CloudflareDashboardScreen extends StatelessWidget {
  const CloudflareDashboardScreen({
    super.key,
    required this.manager,
    required this.onOpenTerminal,
  });

  final MarketProviderManager manager;
  final VoidCallback onOpenTerminal;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: manager,
        builder: (context, _) {
          final providerStatus = manager.statusFor('cloudflare');
          final connected = providerStatus == ManagedProviderStatus.connected;
          final accountId = manager.cloudflareAccountId;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Cloudflare'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Center(child: _ConnectionBadge(status: providerStatus)),
                ),
              ],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
                  children: [
                    _sectionLabel(context, 'ACCOUNT OVERVIEW'),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const CircleAvatar(
                              backgroundColor: Color(0x22F38020),
                              child: Icon(Icons.cloud_rounded, color: Color(0xFFF38020)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(context.tr('Cloudflare API token'), style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text(connected
                                  ? context.tr('Token active · read permissions checked per capability')
                                  : providerStatus == ManagedProviderStatus.error
                                      ? context.tr('Token verification failed')
                                      : context.tr('Token not verified'),
                                  style: TextStyle(color: connected ? const Color(0xFF73F0C2) : Colors.orangeAccent, fontSize: 12)),
                            ])),
                          ]),
                          const SizedBox(height: 14),
                          Text(context.tr('Account ID'), style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 11)),
                          const SizedBox(height: 4),
                          SelectableText(_maskedAccountId(accountId), style: const TextStyle(fontSize: 15, letterSpacing: .5)),
                          const SizedBox(height: 10),
                          Text(context.tr('The account ID shown above is an optional saved filter. Actual account names and domains below are fetched from Cloudflare and are never replaced with sample data.'),
                              style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 12, height: 1.4)),
                          const SizedBox(height: 12),
                          CloudflareReadOnlyPanel(manager: manager),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            OutlinedButton.icon(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => MarketProviderDialog(providerId: 'cloudflare', manager: manager),
                              ),
                              icon: const Icon(Icons.settings_outlined),
                              label: Text(context.tr('Connection settings')),
                            ),
                            FilledButton.icon(
                              onPressed: manager.isBusy ? null : () => _verifyToken(context),
                              icon: manager.isBusy
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.sync_rounded),
                              label: Text(context.tr('Verify token')),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel(context, 'CLOUDFLARE SERVICES'),
                    const SizedBox(height: 4),
                    Text(context.tr('Read-only account and zone information is fetched using supported GET endpoints. Zone listing requires Zone Zone Read; no write APIs are called.'),
                        style: TextStyle(color: Colors.white.withValues(alpha: .67), fontSize: 12, height: 1.4)),
                    const SizedBox(height: 10),
                    const _UnavailableServiceCard(icon: Icons.code_rounded, title: 'Workers', subtitle: 'Scripts, deployments, and logs'),
                    const _UnavailableServiceCard(icon: Icons.security_rounded, title: 'Security', subtitle: 'WAF, SSL/TLS, and security events'),
                    const _UnavailableServiceCard(icon: Icons.analytics_outlined, title: 'Analytics', subtitle: 'Traffic and account statistics'),
                    const _UnavailableServiceCard(icon: Icons.storage_rounded, title: 'R2 Storage', subtitle: 'Buckets and object inventory'),
                    const _UnavailableServiceCard(icon: Icons.web_rounded, title: 'Pages', subtitle: 'Projects and deployments'),
                    const SizedBox(height: 20),
                    _sectionLabel(context, 'QUICK ACTIONS'),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(children: [
                        ListTile(
                          leading: const Icon(Icons.sync_rounded),
                          title: Text(context.tr('Verify API token')),
                          subtitle: Text(context.tr('Verifies token status only. Use Refresh Account & Zone Data to run the separately permission-checked read-only API requests.')),
                          onTap: manager.isBusy ? null : () => _verifyToken(context),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.terminal_rounded),
                          title: Text(context.tr('Open Terminal')),
                          subtitle: Text(context.tr('Opens the existing app-local safe command workspace; it cannot run Cloudflare code or change provider settings.')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: onOpenTerminal,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel(context, 'RECENT ACTIVITY'),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: _recentCheck(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(context.tr('Read-only account and zone requests are also recorded in the app Activity Timeline. Cloudflare account audit logs are not connected.'),
                        style: TextStyle(color: Colors.white.withValues(alpha: .56), fontSize: 11, height: 1.4)),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _recentCheck(BuildContext context) {
    final at = manager.cloudflareLastCheckedAt;
    if (at == null) {
      return Row(children: [
        const Icon(Icons.history_rounded, color: Colors.white54),
        const SizedBox(width: 10),
        Expanded(child: Text(context.tr('No token-check activity recorded in this session.'))),
      ]);
    }
    final succeeded = manager.cloudflareLastCheckSucceeded;
    final localTime = at.toLocal();
    final timestamp = '${localTime.year.toString().padLeft(4, '0')}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')} '
        '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(succeeded == true ? Icons.check_circle_outline : succeeded == false ? Icons.error_outline : Icons.hourglass_top_rounded,
          color: succeeded == true ? const Color(0xFF73F0C2) : Colors.orangeAccent),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(succeeded == true ? context.tr('API token verification succeeded') : succeeded == false ? context.tr('API token verification failed') : context.tr('API token verification in progress')),
        const SizedBox(height: 3),
        Text('$timestamp · ${context.tr('local time; this session only')}', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: .62))),
      ])),
    ]);
  }

  Future<void> _verifyToken(BuildContext context) async {
    try {
      await manager.testConnection('cloudflare');
    } on MarketProviderException catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(error.message))));
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Cloudflare token verification failed.'))));
    }
  }

  Widget _sectionLabel(BuildContext context, String label) => Text(
        context.tr(label),
        style: TextStyle(color: const Color(0xFF73F0C2).withValues(alpha: .88), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
      );

  String _maskedAccountId(String? accountId) {
    final value = accountId?.trim() ?? '';
    if (value.length != 32) return '—';
    return '•••• •••• •••• ${value.substring(value.length - 4)}';
  }
}

class CloudflareReadOnlyPanel extends StatefulWidget {
  const CloudflareReadOnlyPanel({super.key, required this.manager});
  final MarketProviderManager manager;

  @override
  State<CloudflareReadOnlyPanel> createState() => _CloudflareReadOnlyPanelState();
}

class _CloudflareReadOnlyPanelState extends State<CloudflareReadOnlyPanel> {
  bool _loading = false;
  String? _selectedZoneId;

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_handleManagerChange);
    if (widget.manager.statusFor('cloudflare') == ManagedProviderStatus.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void dispose() {
    widget.manager.removeListener(_handleManagerChange);
    super.dispose();
  }

  void _handleManagerChange() {
    final manager = widget.manager;
    if (mounted && !manager.isBusy && manager.statusFor('cloudflare') == ManagedProviderStatus.connected &&
        manager.cloudflareAccountsAccess == CloudflareAccessState.unknown && manager.cloudflareZonesAccess == CloudflareAccessState.unknown && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _loading || widget.manager.isBusy || widget.manager.statusFor('cloudflare') != ManagedProviderStatus.connected) return;
    setState(() => _loading = true);
    try {
      try {
        await widget.manager.loadCloudflareAccounts();
      } on MarketProviderException {
        // Account access is independent; still attempt zones if the token remains connected.
      }
      if (widget.manager.statusFor('cloudflare') == ManagedProviderStatus.connected) {
        try {
          await widget.manager.loadCloudflareZones(accountId: widget.manager.cloudflareAccountId);
        } on MarketProviderException {
          // The manager retains per-capability permission state and a safe error.
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openZone(String zoneId) async {
    if (widget.manager.isBusy) return;
    setState(() => _selectedZoneId = zoneId);
    try {
      await widget.manager.loadCloudflareZoneDetails(zoneId);
    } on MarketProviderException {
      // Error details are presented by the manager; no raw response body is shown.
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.manager,
        builder: (context, _) {
          final manager = widget.manager;
          final connected = manager.statusFor('cloudflare') == ManagedProviderStatus.connected;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(context.tr('Account & Zone Read-Only'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              IconButton(
                tooltip: context.tr('Refresh Account & Zone Data'),
                onPressed: connected && !_loading && !manager.isBusy ? _refresh : null,
                icon: _loading || manager.isBusy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
              ),
            ]),
            Text(context.tr('Account list is checked by its API result. Zones require Zone Zone Read. The active-token endpoint does not return token permission scopes.'),
                style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12, height: 1.4)),
            const SizedBox(height: 8),
            if (!connected)
              Text(context.tr('Verify a Cloudflare token before reading account or zone data.'), style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))
            else ...[
              _permissionStatus(context, 'Account list access', manager.cloudflareAccountsAccess),
              if (manager.cloudflareAccountsAccess == CloudflareAccessState.allowed) ...[
                const SizedBox(height: 5),
                Text('${context.tr('Accounts returned')}: ${manager.cloudflareAccounts.length}${manager.cloudflareAccountTotal > manager.cloudflareAccounts.length ? ' / ${manager.cloudflareAccountTotal}' : ''}',
                    style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 11)),
                for (final account in manager.cloudflareAccounts.take(100))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.business_outlined, size: 18),
                    title: Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${account.type.isEmpty ? context.tr('Account') : account.type} · ${_maskId(account.id)}'),
                  ),
                if (manager.cloudflareAccounts.length > 100)
                  Text(context.tr('Showing first 100 accounts. Narrow access or filter the list to view fewer items.'),
                      style: TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 11)),
              ],
              const Divider(height: 18),
              _permissionStatus(context, 'Zone list access', manager.cloudflareZonesAccess),
              if (manager.cloudflareZonesAccess == CloudflareAccessState.allowed) ...[
                const SizedBox(height: 5),
                Text('${context.tr('Zones returned')}: ${manager.cloudflareZones.length}${manager.cloudflareZoneTotal > manager.cloudflareZones.length ? ' / ${manager.cloudflareZoneTotal}' : ''}',
                    style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 11)),
                if (manager.cloudflareAccountId != null)
                  Text(context.tr('Zones are filtered by the saved Account ID.'), style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 11)),
                if (manager.cloudflareZones.isEmpty) Text(context.tr('No zones were returned for the current read scope.'), style: const TextStyle(fontSize: 12)),
                for (final zone in manager.cloudflareZones.take(100))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.language_rounded, size: 18),
                    title: Text(zone.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${zone.status.isEmpty ? context.tr('Status unavailable') : zone.status} · ${zone.accountName.isEmpty ? _maskId(zone.accountId) : zone.accountName}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: manager.isBusy ? null : () => _openZone(zone.id),
                  ),
                if (manager.cloudflareZones.length > 100)
                  Text(context.tr('Showing first 100 zones. Set the optional Account ID filter to narrow the result.'),
                      style: TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 11)),
                if (_selectedZoneId != null) ...[
                  _permissionStatus(context, 'Selected zone detail access', manager.cloudflareZoneDetailAccess),
                  if (manager.cloudflareZoneDetailAccess == CloudflareAccessState.allowed && manager.cloudflareZoneDetails?.id == _selectedZoneId)
                    _zoneDetailCard(context, manager.cloudflareZoneDetails!),
                ],
              ],
              if (manager.cloudflareReadError case final error?) ...[
                const SizedBox(height: 6),
                Text(context.tr(error), style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
              ],
              if (!manager.cloudflareActivityPersistenceAvailable || manager.cloudflareReadWarning != null) ...[
                const SizedBox(height: 6),
                Text(context.tr(manager.cloudflareReadWarning ?? 'Activity Timeline storage is not available; this read may not be persisted.'),
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
              ],
            ],
          ]);
        },
      );

  Widget _permissionStatus(BuildContext context, String label, CloudflareAccessState state) {
    final text = switch (state) {
      CloudflareAccessState.unknown => context.tr('Not checked'),
      CloudflareAccessState.allowed => context.tr('Read access confirmed by API'),
      CloudflareAccessState.denied => context.tr('Permission denied by API'),
      CloudflareAccessState.error => context.tr('Read unavailable; permission unknown'),
    };
    final color = state == CloudflareAccessState.allowed
        ? const Color(0xFF73F0C2)
        : state == CloudflareAccessState.denied || state == CloudflareAccessState.error
            ? Colors.orangeAccent
            : Colors.white54;
    return Row(children: [
      Expanded(child: Text(context.tr(label), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      Text(text, style: TextStyle(color: color, fontSize: 11)),
    ]);
  }

  Widget _zoneDetailCard(BuildContext context, CloudflareZoneDetails zone) => Card(
        color: Colors.black.withValues(alpha: .16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(zone.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('${context.tr('Zone status')}: ${zone.status.isEmpty ? context.tr('Unknown') : zone.status}'),
            Text('${context.tr('Zone type')}: ${zone.type.isEmpty ? context.tr('Unknown') : zone.type}'),
            Text('${context.tr('Account')}: ${zone.accountName.isEmpty ? _maskId(zone.accountId) : zone.accountName}'),
            Text('${context.tr('Paused')}: ${zone.paused ? context.tr('Yes') : context.tr('No')}'),
            if (zone.activatedOn != null) Text('${context.tr('Activated')}: ${zone.activatedOn}'),
            if (zone.nameServers.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(context.tr('Nameservers'), style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final nameserver in zone.nameServers) Text(nameserver),
            ],
          ]),
        ),
      );

  String _maskId(String id) => id.length == 32 ? '•••• •••• •••• ${id.substring(28)}' : context.tr('ID unavailable');
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.status});
  final ManagedProviderStatus status;

  @override
  Widget build(BuildContext context) {
    final connected = status == ManagedProviderStatus.connected;
    final color = connected ? const Color(0xFF73F0C2) : status == ManagedProviderStatus.error ? Colors.redAccent : Colors.orangeAccent;
    final label = switch (status) {
      ManagedProviderStatus.connected => context.tr('Connected'),
      ManagedProviderStatus.error => context.tr('Error'),
      ManagedProviderStatus.disconnected => context.tr('Disconnected'),
      ManagedProviderStatus.installed => context.tr('Installed'),
      ManagedProviderStatus.notReady => context.tr('Not Ready'),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _UnavailableServiceCard extends StatelessWidget {
  const _UnavailableServiceCard({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon, color: Colors.white54),
          title: Text(context.tr(title)),
          subtitle: Text(context.tr(subtitle)),
          trailing: Text(context.tr('Not integrated'), style: const TextStyle(color: Colors.orangeAccent, fontSize: 10)),
          enabled: false,
        ),
      );
}
