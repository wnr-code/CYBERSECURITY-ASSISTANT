import 'secure_credential_store.dart';

/// Persists explicit AI conversation-sharing consent separately for each provider.
/// The value contains no message or credential data and is kept in secure local storage.
class AiDataSharingConsentStore {
  AiDataSharingConsentStore({required this._backend});

  static const _namespace = 'cybersecurity_assistant.ai_data_sharing_consent.v1';
  static const supportedProviderIds = <String>{'gemini', 'local_ai'};

  final SecureStorageBackend _backend;

  Future<bool> hasConsent(String providerId) async {
    _validateProvider(providerId);
    return await _backend.read(key: _key(providerId)) == 'granted';
  }

  Future<void> grant(String providerId) async {
    _validateProvider(providerId);
    await _backend.write(key: _key(providerId), value: 'granted');
  }

  Future<void> revoke(String providerId) async {
    _validateProvider(providerId);
    await _backend.delete(key: _key(providerId));
  }

  Future<void> revokeAll() async {
    await Future.wait(supportedProviderIds.map((providerId) => _backend.delete(key: _key(providerId))));
  }

  String _key(String providerId) => '$_namespace.$providerId';

  void _validateProvider(String providerId) {
    if (!supportedProviderIds.contains(providerId)) {
      throw ArgumentError.value(providerId, 'providerId', 'Provider is not eligible for AI conversation consent.');
    }
  }
}
