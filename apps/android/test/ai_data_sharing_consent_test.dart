import 'package:cybersecurity_assistant/core/ai_data_sharing_consent.dart';
import 'package:cybersecurity_assistant/core/secure_credential_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryConsentBackend implements SecureStorageBackend {
  final values = <String, String>{};

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

void main() {
  test('consent is persisted locally and scoped independently to each provider', () async {
    final backend = _MemoryConsentBackend();
    final store = AiDataSharingConsentStore(backend: backend);

    expect(await store.hasConsent('gemini'), isFalse);
    expect(await store.hasConsent('local_ai'), isFalse);

    await store.grant('gemini');
    final reopenedStore = AiDataSharingConsentStore(backend: backend);
    expect(await reopenedStore.hasConsent('gemini'), isTrue);
    expect(await reopenedStore.hasConsent('local_ai'), isFalse);

    await reopenedStore.grant('local_ai');
    expect(await store.hasConsent('local_ai'), isTrue);
    await store.revoke('gemini');
    expect(await store.hasConsent('gemini'), isFalse);
    expect(await store.hasConsent('local_ai'), isTrue);
  });

  test('revokeAll clears consent for every supported provider', () async {
    final store = AiDataSharingConsentStore(backend: _MemoryConsentBackend());
    for (final providerId in AiDataSharingConsentStore.supportedProviderIds) {
      await store.grant(providerId);
    }

    await store.revokeAll();
    for (final providerId in AiDataSharingConsentStore.supportedProviderIds) {
      expect(await store.hasConsent(providerId), isFalse);
    }
  });

  test('unknown providers cannot acquire or query consent', () async {
    final store = AiDataSharingConsentStore(backend: _MemoryConsentBackend());
    await expectLater(store.hasConsent('other'), throwsArgumentError);
    await expectLater(store.grant('other'), throwsArgumentError);
  });
}
