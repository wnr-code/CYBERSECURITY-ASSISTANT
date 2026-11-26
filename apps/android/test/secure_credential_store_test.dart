import 'package:cybersecurity_assistant/core/secure_credential_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySecretBackend implements SecureStorageBackend {
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
  test('stores and deletes a secret under a provider-specific namespace', () async {
    final backend = _MemorySecretBackend();
    final store = SecureCredentialStore(backend: backend);

    await store.save(providerId: 'openai', kind: SecureCredentialKind.apiKey, secret: ' user-key ');
    expect(await store.read(providerId: 'openai', kind: SecureCredentialKind.apiKey), ' user-key ');
    expect(backend.values.keys.single, 'cybersecurity_assistant.credential.openai.apiKey');

    await store.delete(providerId: 'openai', kind: SecureCredentialKind.apiKey);
    expect(await store.read(providerId: 'openai', kind: SecureCredentialKind.apiKey), isNull);
  });

  test('rejects unknown providers and credential types not listed for that provider', () async {
    final store = SecureCredentialStore(backend: _MemorySecretBackend());

    await expectLater(
      store.save(providerId: 'unknown', kind: SecureCredentialKind.apiKey, secret: 'secret'),
      throwsA(isA<SecureCredentialException>()),
    );
    await expectLater(
      store.save(providerId: 'openai', kind: SecureCredentialKind.accessToken, secret: 'secret'),
      throwsA(isA<SecureCredentialException>()),
    );
    await expectLater(
      store.save(providerId: 'cloudflare_workers', kind: SecureCredentialKind.apiKey, secret: 'secret'),
      throwsA(isA<SecureCredentialException>()),
    );
  });

  test('rejects empty and oversized credentials without writing them', () async {
    final backend = _MemorySecretBackend();
    final store = SecureCredentialStore(backend: backend);

    await expectLater(
      store.save(providerId: 'openai', kind: SecureCredentialKind.apiKey, secret: '  '),
      throwsA(isA<SecureCredentialException>()),
    );
    await expectLater(
      store.save(providerId: 'openai', kind: SecureCredentialKind.apiKey, secret: 'x' * 8193),
      throwsA(isA<SecureCredentialException>()),
    );
    expect(backend.values, isEmpty);
  });
}
