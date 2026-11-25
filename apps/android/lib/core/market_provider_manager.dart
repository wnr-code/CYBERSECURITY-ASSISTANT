import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'activity_timeline.dart';
import 'ai_provider_manager.dart';
import 'secure_credential_store.dart';

enum ManagedProviderStatus { installed, connected, disconnected, error, notReady }

class LocalAiDeviceCapabilities {
  const LocalAiDeviceCapabilities({
    required this.supportedAbis,
    required this.totalRamBytes,
    required this.availableRamBytes,
    required this.totalStorageBytes,
    required this.availableStorageBytes,
    required this.runtimeAvailable,
    required this.installedModelCount,
  });

  final List<String> supportedAbis;
  final int totalRamBytes;
  final int availableRamBytes;
  final int totalStorageBytes;
  final int availableStorageBytes;
  final bool runtimeAvailable;
  final int installedModelCount;

  static LocalAiDeviceCapabilities? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = Map<Object?, Object?>.from(value);
    final abis = map['supportedAbis'];
    final totalRam = map['totalRamBytes'];
    final availableRam = map['availableRamBytes'];
    final totalStorage = map['totalStorageBytes'];
    final availableStorage = map['availableStorageBytes'];
    final modelCount = map['installedModelCount'];
    if (abis is! List || abis.any((abi) => abi is! String) ||
        totalRam is! int || totalRam <= 0 || availableRam is! int || availableRam < 0 ||
        totalStorage is! int || totalStorage <= 0 || availableStorage is! int || availableStorage < 0 ||
        modelCount is! int || modelCount < 0) {
      return null;
    }
    return LocalAiDeviceCapabilities(
      supportedAbis: List.unmodifiable(abis.cast<String>()),
      totalRamBytes: totalRam,
      availableRamBytes: availableRam,
      totalStorageBytes: totalStorage,
      availableStorageBytes: availableStorage,
      runtimeAvailable: map['runtimeAvailable'] == true,
      installedModelCount: modelCount,
    );
  }
}

class LocalAiCapabilityProbe {
  const LocalAiCapabilityProbe({this.channel = const MethodChannel('org.cybersecurityassistant/local_ai_capabilities')});
  final MethodChannel channel;

  Future<LocalAiDeviceCapabilities?> inspect() async {
    try {
      final result = await channel
          .invokeMethod<Object?>('getDeviceCapabilities')
          .timeout(const Duration(seconds: 2));
      return LocalAiDeviceCapabilities.tryParse(result);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}

class CloudflareVerificationResponse {
  const CloudflareVerificationResponse({required this.statusCode, required this.body});
  final int statusCode;
  final List<int> body;
}

abstract interface class CloudflareTokenTransport {
  Future<CloudflareVerificationResponse> verify(String token);
}

/// Cloudflare's fixed token-verification endpoint only. It does not call or
/// imply availability of Workers, DNS, D1, R2, or any other product API.
class IoCloudflareTokenTransport implements CloudflareTokenTransport {
  IoCloudflareTokenTransport({HttpClient Function()? clientFactory}) : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;
  static final Uri _verifyUri = Uri.https('api.cloudflare.com', '/client/v4/user/tokens/verify');

  @override
  Future<CloudflareVerificationResponse> verify(String token) async {
    final client = _clientFactory();
    try {
      final request = await client.getUrl(_verifyUri).timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 20));
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > 64 * 1024) {
          throw const MarketProviderException('Cloudflare verification response exceeded the safe size limit.');
        }
        bytes.addAll(chunk);
      }
      return CloudflareVerificationResponse(statusCode: response.statusCode, body: List.unmodifiable(bytes));
    } on MarketProviderException {
      rethrow;
    } on SocketException {
      throw const MarketProviderException('Cloudflare could not be reached. Check your network connection.');
    } on HandshakeException {
      throw const MarketProviderException('Cloudflare TLS certificate validation failed.');
    } on HttpException {
      throw const MarketProviderException('Cloudflare returned an HTTP protocol error.');
    } on FormatException {
      throw const MarketProviderException('Cloudflare returned an invalid response.');
    } catch (_) {
      throw const MarketProviderException('Cloudflare connection test failed. The token was not written to logs.');
    } finally {
      client.close(force: true);
    }
  }
}

enum CloudflareAccessState { unknown, allowed, denied, error }

class CloudflareApiResponse {
  const CloudflareApiResponse({required this.statusCode, required this.body});
  final int statusCode;
  final List<int> body;
}

abstract interface class CloudflareReadTransport {
  Future<CloudflareApiResponse> get(Uri uri, String token);
}

/// Read-only Cloudflare API transport; accepts only HTTPS GETs to the two
/// account/zone resources used by this integration.
class IoCloudflareReadTransport implements CloudflareReadTransport {
  IoCloudflareReadTransport({HttpClient Function()? clientFactory}) : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;

  @override
  Future<CloudflareApiResponse> get(Uri uri, String token) async {
    final allowedPath = uri.path == '/client/v4/accounts' ||
        uri.path == '/client/v4/zones' ||
        RegExp(r'^/client/v4/zones/[0-9a-fA-F]{32}$').hasMatch(uri.path);
    final allowedQueryKeys = uri.path == '/client/v4/zones'
        ? {'page', 'per_page', 'account.id'}
        : {'page', 'per_page'};
    if (uri.scheme != 'https' || uri.host != 'api.cloudflare.com' || uri.port != 443 || uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty || !allowedPath || !allowedQueryKeys.containsAll(uri.queryParameters.keys)) {
      throw const MarketProviderException('Cloudflare read request was blocked because its destination is not allowed.');
    }
    final client = _clientFactory()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'CybersecurityAssistant/CloudflareReadOnly');
      final response = await request.close().timeout(const Duration(seconds: 20));
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > 512 * 1024) {
          throw const MarketProviderException('Cloudflare response exceeded the safe size limit.');
        }
        bytes.addAll(chunk);
      }
      return CloudflareApiResponse(statusCode: response.statusCode, body: List.unmodifiable(bytes));
    } on MarketProviderException {
      rethrow;
    } on TimeoutException {
      throw const MarketProviderException('Cloudflare request timed out. Check your connection and retry.');
    } on SocketException {
      throw const MarketProviderException('Cloudflare could not be reached. Check your network connection.');
    } on HandshakeException {
      throw const MarketProviderException('Cloudflare TLS certificate validation failed.');
    } on HttpException {
      throw const MarketProviderException('Cloudflare returned an HTTP protocol error.');
    } catch (_) {
      throw const MarketProviderException('Cloudflare read request failed. Secret values were not logged.');
    } finally {
      client.close(force: true);
    }
  }
}

class CloudflareAccount {
  const CloudflareAccount({required this.id, required this.name, this.type = ''});
  final String id;
  final String name;
  final String type;
}

class CloudflareZone {
  const CloudflareZone({required this.id, required this.name, required this.status, required this.accountId, this.accountName = '', this.type = ''});
  final String id;
  final String name;
  final String status;
  final String accountId;
  final String accountName;
  final String type;
}

class CloudflareZoneDetails extends CloudflareZone {
  const CloudflareZoneDetails({
    required super.id,
    required super.name,
    required super.status,
    required super.accountId,
    super.accountName,
    super.type,
    this.nameServers = const [],
    this.createdOn,
    this.activatedOn,
    this.paused = false,
  });
  final List<String> nameServers;
  final String? createdOn;
  final String? activatedOn;
  final bool paused;
}

class _CloudflareApiFailure extends MarketProviderException {
  const _CloudflareApiFailure(super.message, {required this.denied, this.unauthorized = false});
  final bool denied;
  final bool unauthorized;
}

class MarketProviderException implements Exception {
  const MarketProviderException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Namespaced provider configuration uses the same secure Android storage
/// backend as credentials. Non-secret metadata such as an Account ID remains
/// local, but is still protected from casual backup/log disclosure.
class ProviderConfigurationStore {
  ProviderConfigurationStore(this._storage);
  final SecureStorageBackend _storage;
  static const _namespace = 'cybersecurity_assistant.provider_config';

  Future<String?> readCloudflareAccountId() => _storage.read(key: '$_namespace.cloudflare.account_id');

  Future<void> saveCloudflareAccountId(String accountId) async {
    final normalized = accountId.trim();
    if (normalized.isEmpty) return; // Keep an existing value unless the user explicitly disconnects.
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(normalized)) {
      throw const MarketProviderException('Cloudflare Account ID must be 32 hexadecimal characters.');
    }
    await _storage.write(key: '$_namespace.cloudflare.account_id', value: normalized.toLowerCase());
  }

  Future<void> deleteCloudflareAccountId() => _storage.delete(key: '$_namespace.cloudflare.account_id');
}

/// One Market-facing manager for the three priority providers. Gemini tests and
/// inference delegate to the existing AiProviderManager/Gemini adapter; no
/// second Gemini implementation is constructed here.
class MarketProviderManager extends ChangeNotifier {
  MarketProviderManager({
    required this.credentials,
    required this.configuration,
    required this.aiProviders,
    CloudflareTokenTransport? cloudflareTransport,
    CloudflareReadTransport? cloudflareReadTransport,
    LocalAiCapabilityProbe? localAiProbe,
    this.activityStore,
    this.onActivity,
  })  : _cloudflareTransport = cloudflareTransport ?? IoCloudflareTokenTransport(),
        _cloudflareReadTransport = cloudflareReadTransport ?? IoCloudflareReadTransport(),
        _localAiProbe = localAiProbe ?? const LocalAiCapabilityProbe();

  final SecureCredentialStore credentials;
  final ProviderConfigurationStore configuration;
  final AiProviderManager aiProviders;
  final CloudflareTokenTransport _cloudflareTransport;
  final CloudflareReadTransport _cloudflareReadTransport;
  final LocalAiCapabilityProbe _localAiProbe;
  final ActivityHistoryStore? activityStore;
  final void Function(ActivityEvent event)? onActivity;
  static int _cloudflareActivitySequence = 0;
  static final Random _cloudflareActivityRandom = Random.secure();
  final Map<String, ManagedProviderStatus> _statuses = {
    'cloudflare': ManagedProviderStatus.installed,
    'gemini': ManagedProviderStatus.installed,
    'local_ai': ManagedProviderStatus.notReady,
  };
  final Map<String, String> _messages = {};
  bool _initialized = false;
  bool _busy = false;
  bool _cloudflareConfigured = false;
  bool _geminiConfigured = false;
  bool _disposed = false;
  String? _cloudflareAccountId;
  DateTime? _cloudflareLastCheckedAt;
  bool? _cloudflareLastCheckSucceeded;
  List<CloudflareAccount> _cloudflareAccounts = const [];
  List<CloudflareZone> _cloudflareZones = const [];
  CloudflareZoneDetails? _cloudflareZoneDetails;
  CloudflareAccessState _cloudflareAccountsAccess = CloudflareAccessState.unknown;
  CloudflareAccessState _cloudflareZonesAccess = CloudflareAccessState.unknown;
  CloudflareAccessState _cloudflareZoneDetailAccess = CloudflareAccessState.unknown;
  int _cloudflareAccountTotal = 0;
  int _cloudflareZoneTotal = 0;
  bool _cloudflareActivityPersistenceAvailable = true;
  String? _cloudflareReadError;
  String? _cloudflareReadWarning;
  LocalAiDeviceCapabilities? _localCapabilities;

  static const priorityProviderIds = ['cloudflare', 'gemini', 'local_ai'];
  static final cloudflareDocs = Uri.parse('https://developers.cloudflare.com/fundamentals/api/get-started/create-token/');
  static final cloudflarePermissionsDocs = Uri.parse('https://developers.cloudflare.com/fundamentals/api/reference/permissions/');
  static final cloudflareAccountsApiDocs = Uri.parse('https://developers.cloudflare.com/api/resources/accounts/methods/list/');
  static final cloudflareAccountDetailApiDocs = Uri.parse('https://developers.cloudflare.com/api/resources/accounts/methods/get/');
  static final cloudflareZonesApiDocs = Uri.parse('https://developers.cloudflare.com/api/resources/zones/methods/list/');
  static final cloudflareZoneDetailApiDocs = Uri.parse('https://developers.cloudflare.com/api/resources/zones/methods/get/');
  static final geminiStudioGettingStartedDocs = Uri.parse('https://aistudio.google.com/docs/get-started');
  static final geminiAiStudioDocsIndex = Uri.parse('https://aistudio.google.com/llms.txt');
  static final geminiKeyDocs = Uri.parse('https://ai.google.dev/gemini-api/docs/api-key');
  static final geminiModelsDocs = Uri.parse('https://ai.google.dev/gemini-api/docs/models');
  static final geminiPricingDocs = Uri.parse('https://ai.google.dev/gemini-api/docs/pricing');
  static final geminiTermsDocs = Uri.parse('https://ai.google.dev/gemini-api/terms');
  static final localAiDocs = Uri.parse('https://ai.google.dev/edge/litert-lm/android');
  static final localAiModelsDocs = Uri.parse('https://ai.google.dev/gemma/docs/core');
  static final localAiHuggingFaceModelsDocs = Uri.parse('https://huggingface.co/models');
  static final localAiKaggleModelsDocs = Uri.parse('https://www.kaggle.com/models');

  bool get isBusy => _busy;
  bool get isInitialized => _initialized;
  bool get cloudflareConfigured => _cloudflareConfigured;
  bool get geminiConfigured => _geminiConfigured;
  String? get cloudflareAccountId => _cloudflareAccountId;
  DateTime? get cloudflareLastCheckedAt => _cloudflareLastCheckedAt;
  bool? get cloudflareLastCheckSucceeded => _cloudflareLastCheckSucceeded;
  List<CloudflareAccount> get cloudflareAccounts => List.unmodifiable(_cloudflareAccounts);
  List<CloudflareZone> get cloudflareZones => List.unmodifiable(_cloudflareZones);
  CloudflareZoneDetails? get cloudflareZoneDetails => _cloudflareZoneDetails;
  CloudflareAccessState get cloudflareAccountsAccess => _cloudflareAccountsAccess;
  CloudflareAccessState get cloudflareZonesAccess => _cloudflareZonesAccess;
  CloudflareAccessState get cloudflareZoneDetailAccess => _cloudflareZoneDetailAccess;
  int get cloudflareAccountTotal => _cloudflareAccountTotal;
  int get cloudflareZoneTotal => _cloudflareZoneTotal;
  String? get cloudflareReadError => _cloudflareReadError;
  String? get cloudflareReadWarning => _cloudflareReadWarning;
  bool get cloudflareActivityPersistenceAvailable => _cloudflareActivityPersistenceAvailable;
  LocalAiDeviceCapabilities? get localAiCapabilities => _localCapabilities;
  String? messageFor(String providerId) => _messages[providerId];

  ManagedProviderStatus statusFor(String providerId) => _statuses[providerId] ?? ManagedProviderStatus.notReady;

  Future<void> initialize() async {
    if (_initialized) return;
    final cloudflareToken = await credentials.read(providerId: 'cloudflare', kind: SecureCredentialKind.accessToken);
    final geminiKey = await credentials.read(providerId: 'gemini', kind: SecureCredentialKind.apiKey);
    _cloudflareAccountId = await configuration.readCloudflareAccountId();
    _cloudflareConfigured = cloudflareToken != null;
    _geminiConfigured = geminiKey != null;
    _statuses['cloudflare'] = !_cloudflareConfigured ? ManagedProviderStatus.installed : ManagedProviderStatus.disconnected;
    _statuses['gemini'] = !_geminiConfigured ? ManagedProviderStatus.installed : ManagedProviderStatus.disconnected;
    _localCapabilities = await _localAiProbe.inspect();
    // No native inference runtime is integrated in this build. A model file or
    // device capability alone must never imply Ready/Connected.
    _statuses['local_ai'] = ManagedProviderStatus.notReady;
    _initialized = true;
    _notifyIfActive();
  }

  Future<void> saveCloudflareConfiguration({required String token, String accountId = ''}) async {
    _ensureNotBusy();
    final normalized = token.trim();
    if (normalized.length < 16 || normalized.length > 8192 || normalized.contains(RegExp(r'\s'))) {
      throw const MarketProviderException('Cloudflare API token is empty or has an invalid format.');
    }
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isNotEmpty && !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(normalizedAccountId)) {
      throw const MarketProviderException('Cloudflare Account ID must be 32 hexadecimal characters.');
    }
    _setBusy(true, 'cloudflare');
    try {
      await credentials.save(providerId: 'cloudflare', kind: SecureCredentialKind.accessToken, secret: normalized);
      await configuration.saveCloudflareAccountId(accountId);
      _cloudflareAccountId = await configuration.readCloudflareAccountId();
      _cloudflareConfigured = true;
      _clearCloudflareReadState();
      _statuses['cloudflare'] = ManagedProviderStatus.disconnected;
      _messages['cloudflare'] = 'Credential saved securely. Run Test Connection, then check each read capability separately.';
    } finally {
      _setBusy(false, 'cloudflare');
    }
  }

  Future<void> saveGeminiApiKey(String key) async {
    _ensureNotBusy();
    final normalized = key.trim();
    if (normalized.length > 512 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalized)) {
      throw const MarketProviderException('Gemini API key format is invalid.');
    }
    _setBusy(true, 'gemini');
    try {
      await credentials.save(providerId: 'gemini', kind: SecureCredentialKind.apiKey, secret: normalized);
      _geminiConfigured = true;
      _statuses['gemini'] = ManagedProviderStatus.disconnected;
      _messages['gemini'] = 'API key saved securely. Test Connection checks model access without sending a prompt.';
    } finally {
      _setBusy(false, 'gemini');
    }
  }

  Future<void> testConnection(String providerId) async {
    _ensureNotBusy();
    if (providerId != 'cloudflare' && providerId != 'gemini') {
      throw const MarketProviderException('This provider has no implemented connection test.');
    }
    _setBusy(true, providerId);
    try {
      if (providerId == 'cloudflare') {
        _cloudflareLastCheckedAt = DateTime.now().toUtc();
        _cloudflareLastCheckSucceeded = null;
        _clearCloudflareReadState();
        final token = await credentials.read(providerId: 'cloudflare', kind: SecureCredentialKind.accessToken);
        if (token == null) throw const MarketProviderException('Save a Cloudflare API token before testing the connection.');
        final response = await _cloudflareTransport.verify(token);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw const MarketProviderException('Cloudflare rejected the API token. Check token status and network access.');
        }
        final decoded = jsonDecode(utf8.decode(response.body));
        if (decoded is! Map<String, dynamic> || decoded['success'] != true || decoded['result'] is! Map ||
            (decoded['result'] as Map)['status'] != 'active') {
          throw const MarketProviderException('Cloudflare did not confirm an active API token.');
        }
        _cloudflareLastCheckSucceeded = true;
        _statuses['cloudflare'] = ManagedProviderStatus.connected;
        _messages['cloudflare'] = 'Cloudflare API token is active. Account and zone read access is checked per capability; DNS records, Workers, and other service APIs are not connected.';
      } else {
        await aiProviders.testConnection('gemini');
        _statuses['gemini'] = ManagedProviderStatus.connected;
        _messages['gemini'] = 'Gemini key and configured model access verified without sending a user prompt.';
      }
    } on FormatException {
      if (providerId == 'cloudflare') _cloudflareLastCheckSucceeded = false;
      _statuses[providerId] = ManagedProviderStatus.error;
      _messages[providerId] = 'Provider returned an invalid response.';
      throw MarketProviderException(_messages[providerId]!);
    } on MarketProviderException catch (error) {
      if (providerId == 'cloudflare') _cloudflareLastCheckSucceeded = false;
      _statuses[providerId] = ManagedProviderStatus.error;
      _messages[providerId] = error.message;
      rethrow;
    } on AiProviderException catch (error) {
      if (providerId == 'cloudflare') _cloudflareLastCheckSucceeded = false;
      _statuses[providerId] = ManagedProviderStatus.error;
      // AI provider exception strings are static, credential-free messages.
      _messages[providerId] = error.message;
      throw MarketProviderException(error.message);
    } catch (_) {
      if (providerId == 'cloudflare') _cloudflareLastCheckSucceeded = false;
      _statuses[providerId] = ManagedProviderStatus.error;
      _messages[providerId] = 'Connection test failed. Secret values were not logged.';
      throw MarketProviderException(_messages[providerId]!);
    } finally {
      _setBusy(false, providerId);
    }
  }

  Future<List<CloudflareAccount>> loadCloudflareAccounts() => _withCloudflareRead(
        toolId: 'cloudflare_accounts',
        activitySummary: 'Read Cloudflare account list.',
        updateAccess: (state) => _cloudflareAccountsAccess = state,
        operation: (token) async {
          final result = <CloudflareAccount>[];
          var total = 0;
          for (var page = 1; page <= 20; page++) {
            final envelope = await _getCloudflareEnvelope(
              Uri.https('api.cloudflare.com', '/client/v4/accounts', {'page': '$page', 'per_page': '50'}),
              token,
            );
            final items = envelope['result'];
            if (items is! List || items.length > 50) throw const MarketProviderException('Cloudflare returned an invalid account list.');
            for (final raw in items) {
              if (raw is! Map || !_validCloudflareId(raw['id']) || !_validCloudflareName(raw['name'])) {
                throw const MarketProviderException('Cloudflare returned an invalid account record.');
              }
              result.add(CloudflareAccount(id: raw['id'] as String, name: raw['name'] as String, type: _boundedText(raw['type'], 32)));
            }
            final info = envelope['result_info'];
            if (info is Map && info['total_count'] is int) total = info['total_count'] as int;
            if (items.isEmpty || (total > 0 && result.length >= total) || (total <= 0 && items.length < 50)) break;
          }
          _cloudflareAccounts = List.unmodifiable(result);
          _cloudflareAccountTotal = total > result.length ? total : result.length;
          return _cloudflareAccounts;
        },
      );

  Future<List<CloudflareZone>> loadCloudflareZones({String? accountId}) => _withCloudflareRead(
        toolId: 'cloudflare_zones',
        activitySummary: 'Read Cloudflare zone list.',
        updateAccess: (state) => _cloudflareZonesAccess = state,
        operation: (token) async {
          final normalizedAccountId = accountId?.trim();
          if (normalizedAccountId != null && normalizedAccountId.isNotEmpty && !_validCloudflareId(normalizedAccountId)) {
            throw const MarketProviderException('Selected Cloudflare Account ID is invalid.');
          }
          final result = <CloudflareZone>[];
          var total = 0;
          for (var page = 1; page <= 20; page++) {
            final query = <String, String>{'page': '$page', 'per_page': '50'};
            if (normalizedAccountId != null && normalizedAccountId.isNotEmpty) query['account.id'] = normalizedAccountId;
            final envelope = await _getCloudflareEnvelope(Uri.https('api.cloudflare.com', '/client/v4/zones', query), token);
            final items = envelope['result'];
            if (items is! List || items.length > 50) throw const MarketProviderException('Cloudflare returned an invalid zone list.');
            for (final raw in items) {
              if (raw is! Map || !_validCloudflareId(raw['id']) || !_validCloudflareName(raw['name'])) {
                throw const MarketProviderException('Cloudflare returned an invalid zone record.');
              }
              final account = raw['account'];
              result.add(CloudflareZone(
                id: raw['id'] as String,
                name: raw['name'] as String,
                status: _boundedText(raw['status'], 32),
                accountId: account is Map && _validCloudflareId(account['id']) ? account['id'] as String : '',
                accountName: account is Map ? _boundedText(account['name'], 128) : '',
                type: _boundedText(raw['type'], 32),
              ));
            }
            final info = envelope['result_info'];
            if (info is Map && info['total_count'] is int) total = info['total_count'] as int;
            if (items.isEmpty || (total > 0 && result.length >= total) || (total <= 0 && items.length < 50)) break;
          }
          _cloudflareZones = List.unmodifiable(result);
          _cloudflareZoneTotal = total > result.length ? total : result.length;
          return _cloudflareZones;
        },
      );

  Future<CloudflareZoneDetails> loadCloudflareZoneDetails(String zoneId) => _withCloudflareRead(
        toolId: 'cloudflare_zone_detail',
        activitySummary: 'Read Cloudflare zone details.',
        updateAccess: (state) => _cloudflareZoneDetailAccess = state,
        operation: (token) async {
          if (!_validCloudflareId(zoneId)) throw const MarketProviderException('Selected Cloudflare Zone ID is invalid.');
          final envelope = await _getCloudflareEnvelope(Uri.https('api.cloudflare.com', '/client/v4/zones/$zoneId'), token);
          final raw = envelope['result'];
          if (raw is! Map || raw['id'] != zoneId || !_validCloudflareName(raw['name'])) {
            throw const MarketProviderException('Cloudflare returned invalid zone details.');
          }
          final account = raw['account'];
          final rawNameservers = raw['name_servers'];
          final nameservers = rawNameservers is List
              ? rawNameservers.where(_validCloudflareName).cast<String>().take(16).toList(growable: false)
              : const <String>[];
          final details = CloudflareZoneDetails(
            id: zoneId,
            name: raw['name'] as String,
            status: _boundedText(raw['status'], 32),
            accountId: account is Map && _validCloudflareId(account['id']) ? account['id'] as String : '',
            accountName: account is Map ? _boundedText(account['name'], 128) : '',
            type: _boundedText(raw['type'], 32),
            nameServers: List.unmodifiable(nameservers),
            createdOn: _boundedText(raw['created_on'], 40),
            activatedOn: _boundedText(raw['activated_on'], 40),
            paused: raw['paused'] == true,
          );
          _cloudflareZoneDetails = details;
          return details;
        },
      );

  Future<Map<String, dynamic>> _getCloudflareEnvelope(Uri uri, String token) async {
    final response = await _cloudflareReadTransport.get(uri, token);
    if (response.statusCode == 401) {
      throw const _CloudflareApiFailure('Cloudflare rejected the saved token. Re-verify it in Provider settings.', denied: false, unauthorized: true);
    }
    if (response.statusCode == 403) {
      throw const _CloudflareApiFailure('Cloudflare denied this read. Check the minimum read permission for this capability.', denied: true);
    }
    if (response.statusCode == 429) {
      throw const _CloudflareApiFailure('Cloudflare rate limit reached. Wait briefly, then retry.', denied: false);
    }
    if (response.statusCode == 404) {
      throw const _CloudflareApiFailure('The requested Cloudflare account or zone was not found or is no longer accessible.', denied: false);
    }
    if (response.statusCode >= 500 && response.statusCode <= 599) {
      throw const _CloudflareApiFailure('Cloudflare is experiencing a server problem. Retry later.', denied: false);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const MarketProviderException('Cloudflare could not complete the read request.');
    }
    final decoded = jsonDecode(utf8.decode(response.body));
    if (decoded is! Map<String, dynamic> || decoded['success'] != true || decoded['result'] == null) {
      throw const MarketProviderException('Cloudflare returned an unsuccessful or malformed read response.');
    }
    return decoded;
  }

  Future<T> _withCloudflareRead<T>({
    required String toolId,
    required String activitySummary,
    required void Function(CloudflareAccessState) updateAccess,
    required Future<T> Function(String token) operation,
  }) async {
    _ensureNotBusy();
    // Claim the shared provider-operation lock before any asynchronous preflight.
    // Otherwise two simultaneous reads can both pass _ensureNotBusy, then dispatch
    // independently after initialize()/secure-storage reads complete.
    _setBusy(true, 'cloudflare');
    try {
      await initialize();
      final token = await credentials.read(providerId: 'cloudflare', kind: SecureCredentialKind.accessToken);
      if (token == null) {
        _cloudflareConfigured = false;
        _statuses['cloudflare'] = ManagedProviderStatus.disconnected;
        updateAccess(CloudflareAccessState.unknown);
        _cloudflareReadError = 'Save and verify a Cloudflare API token before reading account or zone data.';
        _notifyIfActive();
        throw MarketProviderException(_cloudflareReadError!);
      }
      if (_statuses['cloudflare'] != ManagedProviderStatus.connected) {
        updateAccess(CloudflareAccessState.unknown);
        _cloudflareReadError = 'Verify the Cloudflare API token before requesting account or zone data.';
        _notifyIfActive();
        throw MarketProviderException(_cloudflareReadError!);
      }
      updateAccess(CloudflareAccessState.unknown);
      _cloudflareReadError = null;
      final startedAt = DateTime.now().toUtc();
      final event = ActivityEvent(
        eventId: _newCloudflareActivityId(),
        kind: ActivityKind.tool,
        toolId: toolId,
        target: 'api.cloudflare.com',
        status: ActivityStatus.started,
        startedAt: startedAt,
        summary: activitySummary,
      );
      await _persistCloudflareActivity(event);
      try {
        final result = await operation(token);
        updateAccess(CloudflareAccessState.allowed);
        _cloudflareReadError = null;
        _cloudflareReadWarning = null;
        _statuses['cloudflare'] = ManagedProviderStatus.connected;
        _messages['cloudflare'] = 'Cloudflare token authorized this read-only capability. No write request was made.';
        await _persistCloudflareActivity(event.copyWith(
          status: ActivityStatus.completed,
          finishedAt: DateTime.now().toUtc(),
          summary: activitySummary,
        ));
        return result;
      } on _CloudflareApiFailure catch (error) {
        updateAccess(error.denied ? CloudflareAccessState.denied : CloudflareAccessState.error);
        _cloudflareReadError = error.message;
        if (error.unauthorized) {
          _statuses['cloudflare'] = ManagedProviderStatus.error;
          _cloudflareLastCheckedAt = DateTime.now().toUtc();
          _cloudflareLastCheckSucceeded = false;
        }
        await _persistCloudflareActivity(event.copyWith(
          status: ActivityStatus.failed,
          finishedAt: DateTime.now().toUtc(),
          summary: 'Cloudflare API read was rejected or unavailable.',
        ));
        throw MarketProviderException(error.message);
      } on MarketProviderException catch (error) {
        updateAccess(CloudflareAccessState.error);
        _cloudflareReadError = error.message;
        if (_cloudflareConfigured) _statuses['cloudflare'] = ManagedProviderStatus.error;
        await _persistCloudflareActivity(event.copyWith(
          status: ActivityStatus.failed,
          finishedAt: DateTime.now().toUtc(),
          summary: 'Cloudflare read failed.',
        ));
        rethrow;
      } on FormatException {
        updateAccess(CloudflareAccessState.error);
        _cloudflareReadError = 'Cloudflare returned an invalid response.';
        _statuses['cloudflare'] = ManagedProviderStatus.error;
        await _persistCloudflareActivity(event.copyWith(
          status: ActivityStatus.failed,
          finishedAt: DateTime.now().toUtc(),
          summary: 'Cloudflare returned an invalid read response.',
        ));
        throw MarketProviderException(_cloudflareReadError!);
      } catch (_) {
        updateAccess(CloudflareAccessState.error);
        _cloudflareReadError = 'Cloudflare read request failed. Secret values were not logged.';
        _statuses['cloudflare'] = ManagedProviderStatus.error;
        await _persistCloudflareActivity(event.copyWith(
          status: ActivityStatus.failed,
          finishedAt: DateTime.now().toUtc(),
          summary: 'Cloudflare read request failed.',
        ));
        throw MarketProviderException(_cloudflareReadError!);
      }
    } finally {
      _setBusy(false, 'cloudflare');
    }
  }

  Future<void> _persistCloudflareActivity(ActivityEvent event) async {
    try {
      final sanitized = event.sanitizedForStorage().validated();
      await activityStore?.upsertActivity(sanitized);
      onActivity?.call(sanitized);
      _cloudflareActivityPersistenceAvailable = activityStore != null && activityStore is! MemoryActivityHistoryStore;
    } catch (_) {
      _cloudflareActivityPersistenceAvailable = false;
      _cloudflareReadWarning = 'Cloudflare activity could not be saved to the Activity Timeline.';
    }
  }

  static String _newCloudflareActivityId() =>
      'cf-${DateTime.now().toUtc().microsecondsSinceEpoch}-${++_cloudflareActivitySequence}-${_cloudflareActivityRandom.nextInt(1 << 32).toRadixString(16)}';

  static final _unsafeCloudflareText = RegExp(r'[\u0000-\u001F\u007F-\u009F\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]');
  static bool _validCloudflareId(Object? value) => value is String && RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(value);
  static bool _validCloudflareName(Object? value) =>
      value is String && value.trim().isNotEmpty && value.length <= 253 && !_unsafeCloudflareText.hasMatch(value);
  static String _boundedText(Object? value, int maxLength) =>
      value is String && value.length <= maxLength && !_unsafeCloudflareText.hasMatch(value) ? value.trim() : '';

  Future<void> testInference() async {
    throw const MarketProviderException('Local AI is Not Ready: no on-device inference runtime or installed model is available. No cloud fallback was attempted.');
  }

  Future<void> disconnect(String providerId) async {
    _ensureNotBusy();
    _setBusy(true, providerId);
    try {
      switch (providerId) {
        case 'cloudflare':
          await credentials.delete(providerId: 'cloudflare', kind: SecureCredentialKind.accessToken);
          await configuration.deleteCloudflareAccountId();
          _cloudflareConfigured = false;
          _clearCloudflareReadState();
          break;
        case 'gemini':
          await credentials.delete(providerId: 'gemini', kind: SecureCredentialKind.apiKey);
          _geminiConfigured = false;
          break;
        case 'local_ai':
          throw const MarketProviderException('No local runtime or model is installed to disconnect.');
        default:
          throw const MarketProviderException('Unknown provider.');
      }
      _statuses[providerId] = providerId == 'local_ai' ? ManagedProviderStatus.notReady : ManagedProviderStatus.installed;
      _messages[providerId] = 'Provider credential disconnected and deleted from secure storage.';
      if (providerId == 'cloudflare') _cloudflareAccountId = null;
    } finally {
      _setBusy(false, providerId);
    }
  }

  void _clearCloudflareReadState() {
    _cloudflareAccounts = const [];
    _cloudflareZones = const [];
    _cloudflareZoneDetails = null;
    _cloudflareAccountsAccess = CloudflareAccessState.unknown;
    _cloudflareZonesAccess = CloudflareAccessState.unknown;
    _cloudflareZoneDetailAccess = CloudflareAccessState.unknown;
    _cloudflareAccountTotal = 0;
    _cloudflareZoneTotal = 0;
    _cloudflareReadError = null;
    _cloudflareReadWarning = null;
  }

  void _ensureNotBusy() {
    if (_busy) throw const MarketProviderException('Another provider operation is already in progress.');
  }

  void _setBusy(bool value, String providerId) {
    _busy = value;
    if (value) _messages.remove(providerId);
    _notifyIfActive();
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
