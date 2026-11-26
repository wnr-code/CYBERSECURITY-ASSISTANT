import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'provider_registry.dart';

abstract interface class SecureStorageBackend {
  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
}

class FlutterSecureStorageBackend implements SecureStorageBackend {
  FlutterSecureStorageBackend({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String value}) => _storage.write(key: key, value: value);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

enum SecureCredentialKind { apiKey, accessToken }

class SecureCredentialException implements Exception {
  const SecureCredentialException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Namespaced credential operations. No values are logged or sent to a backend.
/// The production backend delegates encryption/key handling to Android Keystore
/// through flutter_secure_storage; tests inject an in-memory fake backend.
class SecureCredentialStore {
  SecureCredentialStore({SecureStorageBackend? backend})
      : _backend = backend ?? FlutterSecureStorageBackend();

  static const _namespace = 'cybersecurity_assistant.credential';
  static const _maxSecretLength = 8192;
  final SecureStorageBackend _backend;

  Future<void> save({
    required String providerId,
    required SecureCredentialKind kind,
    required String secret,
  }) async {
    final definition = _provider(providerId);
    _validateKind(definition, kind);
    if (secret.trim().isEmpty || secret.length > _maxSecretLength) {
      throw const SecureCredentialException('Credential is empty or exceeds the allowed size.');
    }
    await _backend.write(key: _key(providerId, kind), value: secret);
  }

  Future<String?> read({required String providerId, required SecureCredentialKind kind}) async {
    final definition = _provider(providerId);
    _validateKind(definition, kind);
    return _backend.read(key: _key(providerId, kind));
  }

  Future<void> delete({required String providerId, required SecureCredentialKind kind}) async {
    final definition = _provider(providerId);
    _validateKind(definition, kind);
    await _backend.delete(key: _key(providerId, kind));
  }

  ProviderDefinition _provider(String providerId) {
    for (final provider in providerRegistry) {
      if (provider.id == providerId) return provider;
    }
    throw const SecureCredentialException('Unknown provider ID.');
  }

  void _validateKind(ProviderDefinition provider, SecureCredentialKind kind) {
    final allowed = switch (kind) {
      SecureCredentialKind.apiKey => provider.authType == ProviderAuthType.apiKey,
      SecureCredentialKind.accessToken => provider.authType == ProviderAuthType.scopedToken,
    };
    if (!allowed) {
      throw const SecureCredentialException('Credential type is not valid for this provider.');
    }
  }

  String _key(String providerId, SecureCredentialKind kind) =>
      '$_namespace.$providerId.${kind.name}';
}
