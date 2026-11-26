/// UI-facing state resolved from the owning integration, not catalog presence.
/// `connected` means the provider-specific connection test succeeded; it is not
/// a promise of uninterrupted service or of every optional read permission.
enum CapabilityStatus { available, configured, connected, unavailable, notReady, error }

extension CapabilityStatusLabel on CapabilityStatus {
  String get sourceLabel => switch (this) {
        CapabilityStatus.available => 'Available',
        CapabilityStatus.configured => 'Configured · not tested',
        CapabilityStatus.connected => 'Connected',
        CapabilityStatus.unavailable => 'Unavailable',
        CapabilityStatus.notReady => 'Not Ready — integration in progress',
        CapabilityStatus.error => 'Error · retry',
      };
}
