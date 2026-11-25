import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'secure_credential_store.dart';

const diagnosticLabels = <String>['bug', 'runtime-error', 'auto-report'];
const _queueLimit = 50;

bool _validRelayBearer(String? value) => value != null && value.length >= 32 && value.length <= 512 && value.trim() == value && !value.contains(RegExp(r'\s'));

String sanitizeDiagnosticText(String input, {int maxLength = 240}) {
  var text = input
      .replaceAll(RegExp(r'-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----', dotAll: true), '[private-key-redacted]')
      .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '[url]')
      .replaceAll(RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false), '[email]')
      .replaceAll(RegExp(r'\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false), '[authorization-redacted]')
      .replaceAll(RegExp(r'\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[A-Za-z0-9_-]{30,}|AKIA[0-9A-Z]{16})\b'), '[credential-redacted]')
      .replaceAll(RegExp(r'\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b'), '[jwt-redacted]')
      .replaceAll(RegExp(r'(authorization|cookie|set-cookie|credential|token|api[_-]?key|password|secret)\s*[:=]\s*[^\s,;]+', caseSensitive: false), r'$1=[redacted]')
      .replaceAll(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'), '[ip]')
      .replaceAll(RegExp(r'(?:/data/\S+|/storage/emulated/\S+|/sdcard/\S+|/Users/\S+|/home/\S+|/private/var/\S+|[A-Z]:\\\S+)', caseSensitive: false), '[path]')
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  if (text.length > maxLength) text = '${text.substring(0, maxLength)}…';
  return text;
}

String sanitizeDiagnosticStack(StackTrace? stack) {
  if (stack == null) return '';
  final frames = <String>[];
  for (final raw in stack.toString().split('\n')) {
    if (frames.length == 12) break;
    final safe = sanitizeDiagnosticText(raw, maxLength: 180);
    if (safe.isNotEmpty) frames.add(safe.replaceAll(RegExp(r'\([^)]*\)'), '(frame)'));
  }
  return frames.join('\n');
}

String sanitizeDiagnosticMessage(String input, DiagnosticCategory category, {int maxLength = 600}) {
  final safe = sanitizeDiagnosticText(input, maxLength: maxLength);
  if (category == DiagnosticCategory.network || category == DiagnosticCategory.package) {
    return safe.replaceAll(RegExp(r'\b(?:[a-z0-9-]+\.)+[a-z]{2,}\b', caseSensitive: false), '[host]');
  }
  return safe;
}

bool validDiagnosticRepository(String value) => RegExp(r'^[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}$').hasMatch(value);

enum DiagnosticCategory { flutter, dart, native, network, database, startup, runtime, package, bug, assessment, terminal, aiProvider }
enum DiagnosticReportType { bugReport, crashReport, runtimeError, assessmentError, terminalError, aiProviderError, marketError, networkCloudError }
enum DiagnosticSeverity { info, low, medium, high, critical }
enum DiagnosticStatus { queued, waitingForReview, uploading, sent, failed }

DiagnosticReportType reportTypeForCategory(DiagnosticCategory category) => switch (category) {
      DiagnosticCategory.bug => DiagnosticReportType.bugReport,
      DiagnosticCategory.native || DiagnosticCategory.startup => DiagnosticReportType.crashReport,
      DiagnosticCategory.assessment => DiagnosticReportType.assessmentError,
      DiagnosticCategory.terminal => DiagnosticReportType.terminalError,
      DiagnosticCategory.aiProvider => DiagnosticReportType.aiProviderError,
      DiagnosticCategory.package => DiagnosticReportType.marketError,
      DiagnosticCategory.network => DiagnosticReportType.networkCloudError,
      DiagnosticCategory.flutter || DiagnosticCategory.dart || DiagnosticCategory.database || DiagnosticCategory.runtime => DiagnosticReportType.runtimeError,
    };

DiagnosticSeverity severityForCategory(DiagnosticCategory category) => switch (category) {
      DiagnosticCategory.native => DiagnosticSeverity.critical,
      DiagnosticCategory.startup || DiagnosticCategory.runtime || DiagnosticCategory.assessment || DiagnosticCategory.terminal => DiagnosticSeverity.high,
      DiagnosticCategory.bug || DiagnosticCategory.flutter || DiagnosticCategory.dart || DiagnosticCategory.database || DiagnosticCategory.package || DiagnosticCategory.aiProvider => DiagnosticSeverity.medium,
      DiagnosticCategory.network => DiagnosticSeverity.low,
    };

class DiagnosticSettings {
  const DiagnosticSettings({
    this.consentGranted = false,
    this.autoReportingEnabled = false,
    this.wifiOnly = false,
    this.reviewBeforeUpload = true,
    this.backendEndpoint = '',
    this.repository = 'wnr-code/CYBERSECURITY-ASSISTANT',
  });
  final bool consentGranted;
  final bool autoReportingEnabled;
  final bool wifiOnly;
  final bool reviewBeforeUpload;
  final String backendEndpoint;
  final String repository;

  DiagnosticSettings copyWith({bool? consentGranted, bool? autoReportingEnabled, bool? wifiOnly, bool? reviewBeforeUpload, String? backendEndpoint, String? repository}) => DiagnosticSettings(
        consentGranted: consentGranted ?? this.consentGranted,
        autoReportingEnabled: autoReportingEnabled ?? this.autoReportingEnabled,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        reviewBeforeUpload: reviewBeforeUpload ?? this.reviewBeforeUpload,
        backendEndpoint: backendEndpoint ?? this.backendEndpoint,
        repository: repository ?? this.repository,
      );

  Map<String, Object?> toJson() => {
        'consentGranted': consentGranted,
        'autoReportingEnabled': autoReportingEnabled,
        'wifiOnly': wifiOnly,
        'reviewBeforeUpload': reviewBeforeUpload,
        'backendEndpoint': backendEndpoint,
        'repository': repository,
      };

  factory DiagnosticSettings.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const DiagnosticSettings();
    final endpoint = json['backendEndpoint'];
    final repository = json['repository'];
    return DiagnosticSettings(
      consentGranted: json['consentGranted'] == true,
      autoReportingEnabled: json['autoReportingEnabled'] == true,
      wifiOnly: json['wifiOnly'] == true,
      reviewBeforeUpload: json['reviewBeforeUpload'] != false,
      backendEndpoint: endpoint is String ? endpoint : '',
      repository: repository is String && validDiagnosticRepository(repository) ? repository : 'wnr-code/CYBERSECURITY-ASSISTANT',
    );
  }
}

class DiagnosticReport {
  const DiagnosticReport({
    required this.id,
    required this.fingerprint,
    required this.category,
    required this.errorType,
    required this.message,
    required this.stack,
    required this.firstSeen,
    required this.lastSeen,
    required this.appVersion,
    required this.buildNumber,
    required this.androidVersion,
    required this.status,
    this.reportType,
    this.severity,
    this.component = 'app',
    this.moduleVersion,
    this.assessmentId,
    this.executionId,
    this.runtimeStatus,
    this.reproductionSteps = '',
    this.occurrences = 1,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastUploadError,
    this.uploadApproved = false,
    this.isLocalTest = false,
  });

  final String id;
  final String fingerprint;
  final DiagnosticCategory category;
  final DiagnosticReportType? reportType;
  final DiagnosticSeverity? severity;
  final String component;
  final String? moduleVersion;
  final String? assessmentId;
  final String? executionId;
  final String? runtimeStatus;
  final String reproductionSteps;
  final String errorType;
  final String message;
  final String stack;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final String appVersion;
  final String buildNumber;
  final String androidVersion;
  final DiagnosticStatus status;
  final int occurrences;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastUploadError;
  final bool uploadApproved;
  final bool isLocalTest;

  DiagnosticReport copyWith({
    DateTime? lastSeen,
    DiagnosticStatus? status,
    int? occurrences,
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    String? lastUploadError,
    bool clearLastUploadError = false,
    bool? uploadApproved,
  }) => DiagnosticReport(
        id: id,
        fingerprint: fingerprint,
        category: category,
        reportType: reportType,
        severity: severity,
        component: component,
        moduleVersion: moduleVersion,
        assessmentId: assessmentId,
        executionId: executionId,
        runtimeStatus: runtimeStatus,
        reproductionSteps: reproductionSteps,
        errorType: errorType,
        message: message,
        stack: stack,
        firstSeen: firstSeen,
        lastSeen: lastSeen ?? this.lastSeen,
        appVersion: appVersion,
        buildNumber: buildNumber,
        androidVersion: androidVersion,
        status: status ?? this.status,
        occurrences: occurrences ?? this.occurrences,
        attempts: attempts ?? this.attempts,
        nextAttemptAt: nextAttemptAt ?? (clearNextAttemptAt ? null : this.nextAttemptAt),
        lastUploadError: clearLastUploadError ? null : lastUploadError ?? this.lastUploadError,
        uploadApproved: uploadApproved ?? this.uploadApproved,
        isLocalTest: isLocalTest,
      );

  /// Full local queue serialization, including retry/approval state. This JSON
  /// is never sent directly to the relay.
  Map<String, Object?> toJson() => {
        'id': id,
        'fingerprint': fingerprint,
        'category': category.name,
        'reportType': (reportType ?? reportTypeForCategory(category)).name,
        'severity': (severity ?? severityForCategory(category)).name,
        'component': component,
        'moduleVersion': moduleVersion,
        'assessmentId': assessmentId,
        'executionId': executionId,
        'runtimeStatus': runtimeStatus,
        'reproductionSteps': reproductionSteps,
        'errorType': errorType,
        'message': message,
        'stack': stack,
        'firstSeen': firstSeen.toUtc().toIso8601String(),
        'lastSeen': lastSeen.toUtc().toIso8601String(),
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'androidVersion': androidVersion,
        'status': status.name,
        'occurrences': occurrences,
        'attempts': attempts,
        'nextAttemptAt': nextAttemptAt?.toUtc().toIso8601String(),
        'lastUploadError': lastUploadError,
        'uploadApproved': uploadApproved,
        'isLocalTest': isLocalTest,
      };

  /// Strict allowlist for outbound relay payload; never includes local IDs,
  /// fingerprints, retry state, test markers, or transport errors.
  Map<String, Object?> toRelayJson() => {
        'type': (reportType ?? reportTypeForCategory(category)).name,
        'severity': (severity ?? severityForCategory(category)).name,
        'category': category.name,
        'component': component,
        'moduleVersion': moduleVersion ?? appVersion,
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'runtimeVersion': androidVersion,
        'occurredAt': lastSeen.toUtc().toIso8601String(),
        'assessmentId': assessmentId,
        'executionId': executionId,
        'runtimeStatus': runtimeStatus,
        'errorType': errorType,
        'message': message,
        'stackTrace': stack,
        'reproductionSteps': reproductionSteps,
        'occurrences': occurrences,
      };

  factory DiagnosticReport.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) throw const FormatException('Invalid diagnostic report.');
    DateTime date(Object? value) => DateTime.tryParse(value is String ? value : '')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    T enumeration<T extends Enum>(List<T> values, Object? name, T fallback) => values.firstWhere((value) => value.name == name, orElse: () => fallback);
    String text(Object? value, String fallback, {int limit = 120}) => sanitizeDiagnosticText(value is String ? value : fallback, maxLength: limit);
    final category = enumeration(DiagnosticCategory.values, json['category'], DiagnosticCategory.dart);
    final rawStack = json['stack'];
    final next = json['nextAttemptAt'];
    final lastError = json['lastUploadError'];
    return DiagnosticReport(
      id: text(json['id'], '', limit: 180),
      fingerprint: text(json['fingerprint'], '', limit: 64),
      category: category,
      reportType: enumeration(DiagnosticReportType.values, json['reportType'], reportTypeForCategory(category)),
      severity: enumeration(DiagnosticSeverity.values, json['severity'], severityForCategory(category)),
      component: text(json['component'], 'app', limit: 80),
      moduleVersion: json['moduleVersion'] is String ? text(json['moduleVersion'], 'unknown', limit: 80) : null,
      assessmentId: json['assessmentId'] is String ? text(json['assessmentId'], '', limit: 128) : null,
      executionId: json['executionId'] is String ? text(json['executionId'], '', limit: 128) : null,
      runtimeStatus: json['runtimeStatus'] is String ? text(json['runtimeStatus'], '', limit: 120) : null,
      reproductionSteps: text(json['reproductionSteps'], '', limit: 1200),
      errorType: text(json['errorType'], 'Error', limit: 100),
      message: sanitizeDiagnosticText(json['message'] is String ? json['message'] as String : '', maxLength: 900),
      stack: sanitizeDiagnosticStack(StackTrace.fromString(rawStack is String ? rawStack : '')),
      firstSeen: date(json['firstSeen']),
      lastSeen: date(json['lastSeen']),
      appVersion: text(json['appVersion'], 'unknown', limit: 80),
      buildNumber: text(json['buildNumber'], 'unknown', limit: 80),
      androidVersion: text(json['androidVersion'], 'unknown', limit: 80),
      status: enumeration(DiagnosticStatus.values, json['status'], DiagnosticStatus.queued),
      occurrences: json['occurrences'] is int ? (json['occurrences'] as int).clamp(1, 100000).toInt() : 1,
      attempts: json['attempts'] is int ? (json['attempts'] as int).clamp(0, 100).toInt() : 0,
      nextAttemptAt: next is String ? DateTime.tryParse(next)?.toUtc() : null,
      lastUploadError: lastError is String ? sanitizeDiagnosticText(lastError) : null,
      uploadApproved: json['uploadApproved'] == true,
      isLocalTest: json['isLocalTest'] == true,
    );
  }
}

abstract interface class DiagnosticQueueStore {
  Future<Map<String, Object?>> load();
  Future<void> save(Map<String, Object?> data);
}

class FileDiagnosticQueueStore implements DiagnosticQueueStore {
  FileDiagnosticQueueStore({Future<Directory> Function()? directoryProvider}) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directoryProvider;

  Future<File> _file() async {
    final root = await _directoryProvider();
    final folder = Directory(p.join(root.path, 'diagnostics'));
    await folder.create(recursive: true);
    return File(p.join(folder.path, 'queue.json'));
  }

  @override
  Future<Map<String, Object?>> load() async {
    final file = await _file();
    if (!await file.exists()) return <String, Object?>{};
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, dynamic>) throw const FormatException('Diagnostic queue is invalid.');
    return json;
  }

  @override
  Future<void> save(Map<String, Object?> data) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(file.path);
  }
}

class DiagnosticRelaySecretStore {
  DiagnosticRelaySecretStore({SecureStorageBackend? backend}) : _backend = backend ?? FlutterSecureStorageBackend();
  static const _key = 'cybersecurity_assistant.diagnostics.relay_bearer';
  final SecureStorageBackend _backend;

  Future<String?> read() => _backend.read(key: _key);

  Future<void> save(String value) async {
    final secret = value.trim();
    if (!_validRelayBearer(secret)) {
      throw const FormatException('Relay credential must be a 32–512 character token without whitespace.');
    }
    await _backend.write(key: _key, value: secret);
  }

  Future<void> delete() => _backend.delete(key: _key);
}

class DiagnosticUploadRequest {
  const DiagnosticUploadRequest(this.report, this.repository);
  final DiagnosticReport report;
  final String repository;
  Map<String, Object?> toJson() => {
        'schemaVersion': 2,
        'repository': repository,
        'labels': diagnosticLabels,
        'report': report.toRelayJson(),
      };
}

abstract interface class DiagnosticUploader {
  Future<void> upload(DiagnosticUploadRequest request, Uri endpoint, {required String bearerToken, required Duration timeout});
  Future<bool> testConnection(Uri endpoint, {required Duration timeout});
}

class UserRelayDiagnosticUploader implements DiagnosticUploader {
  UserRelayDiagnosticUploader({HttpClient Function()? clientFactory}) : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;
  static bool validEndpoint(Uri uri) => uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty && !uri.hasFragment && !uri.hasQuery;

  @override
  Future<void> upload(DiagnosticUploadRequest request, Uri endpoint, {required String bearerToken, required Duration timeout}) async {
    if (!validEndpoint(endpoint) || !validDiagnosticRepository(request.repository)) throw const FormatException('Configure an HTTPS user-owned relay and a valid repository.');
    if (!_validRelayBearer(bearerToken)) throw const FormatException('Relay credential is missing or invalid.');
    final payload = utf8.encode(jsonEncode(request.toJson()));
    if (payload.length > 64 * 1024) throw const FormatException('Sanitized diagnostic report exceeds the relay payload limit.');
    final client = _clientFactory()..connectionTimeout = timeout;
    try {
      final req = await client.postUrl(endpoint).timeout(timeout);
      req.followRedirects = false;
      req.maxRedirects = 0;
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      req.add(payload);
      final response = await req.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Relay rejected the report (${response.statusCode}).');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> testConnection(Uri endpoint, {required Duration timeout}) async {
    if (!validEndpoint(endpoint)) return false;
    final client = _clientFactory()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(endpoint).timeout(timeout);
      req.followRedirects = false;
      req.maxRedirects = 0;
      final response = await req.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

class DiagnosticReporter extends ChangeNotifier {
  DiagnosticReporter({
    required this.store,
    DiagnosticUploader? uploader,
    DiagnosticRelaySecretStore? relaySecretStore,
    Future<bool> Function()? wifiAvailable,
    DateTime Function()? clock,
    this.appVersion = '0.1.0',
    this.buildNumber = '1',
    this.androidVersion = 'Android',
    this.requestTimeout = const Duration(seconds: 8),
    this.maxAttempts = 5,
  })  : uploader = uploader ?? UserRelayDiagnosticUploader(),
        relaySecretStore = relaySecretStore ?? DiagnosticRelaySecretStore(),
        _wifiAvailable = wifiAvailable ?? (() async => false),
        _clock = clock ?? DateTime.now;

  static DiagnosticReporter? active;
  static void recordGlobal(
    Object error, {
    StackTrace? stackTrace,
    DiagnosticCategory category = DiagnosticCategory.dart,
    DiagnosticReportType? reportType,
    DiagnosticSeverity? severity,
    String component = 'app',
    String? assessmentId,
    String? executionId,
    String? runtimeStatus,
    String? moduleVersion,
    String reproductionSteps = '',
  }) {
    final current = active;
    if (current != null) {
      unawaited(current.record(
        error,
        stackTrace: stackTrace,
        category: category,
        reportType: reportType,
        severity: severity,
        component: component,
        assessmentId: assessmentId,
        executionId: executionId,
        runtimeStatus: runtimeStatus,
        moduleVersion: moduleVersion,
        reproductionSteps: reproductionSteps,
      ));
    }
  }

  final DiagnosticQueueStore store;
  final DiagnosticUploader uploader;
  final DiagnosticRelaySecretStore relaySecretStore;
  final Future<bool> Function() _wifiAvailable;
  final DateTime Function() _clock;
  String appVersion;
  String buildNumber;
  String androidVersion;
  final Duration requestTimeout;
  final int maxAttempts;
  final List<DiagnosticReport> _reports = [];
  DiagnosticSettings _settings = const DiagnosticSettings();
  Future<void>? _initializing;
  Future<void> _persisting = Future<void>.value();
  DateTime? _lastSuccessfulUpload;
  bool _initialized = false;
  bool _relayCredentialConfigured = false;
  bool _busy = false;
  bool? _wifiStatusOverride;
  String? storageWarning;
  Timer? _retryTimer;

  void setWifiAvailability(bool available) {
    _wifiStatusOverride = available;
    if (_settings.wifiOnly && available) unawaited(retryPending());
  }

  void updateDeviceMetadata({required String appVersion, required String buildNumber, required String androidVersion}) {
    this.appVersion = sanitizeDiagnosticText(appVersion);
    this.buildNumber = sanitizeDiagnosticText(buildNumber);
    this.androidVersion = sanitizeDiagnosticText(androidVersion);
  }

  void startRetryLoop() {
    _retryTimer ??= Timer.periodic(const Duration(minutes: 1), (_) => unawaited(retryPending()));
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    if (identical(DiagnosticReporter.active, this)) DiagnosticReporter.active = null;
    super.dispose();
  }

  List<DiagnosticReport> get reports => List.unmodifiable(_reports);
  List<DiagnosticReport> get pendingReports => List.unmodifiable(_reports.where((row) => row.status != DiagnosticStatus.sent));
  DiagnosticSettings get settings => _settings;
  DateTime? get lastSuccessfulUpload => _lastSuccessfulUpload;
  bool get isBusy => _busy;
  int get pendingCount => pendingReports.length;
  bool get relayCredentialConfigured => _relayCredentialConfigured;
  bool get hasRelay => _relayCredentialConfigured && UserRelayDiagnosticUploader.validEndpoint(Uri.tryParse(_settings.backendEndpoint) ?? Uri());

  Future<void> initialize() async {
    if (_initialized) return;
    final ongoing = _initializing;
    if (ongoing != null) return ongoing;
    final future = _load();
    _initializing = future;
    try {
      await future;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _load() async {
    _reports.clear();
    try {
      final data = await store.load();
      _settings = DiagnosticSettings.fromJson(data['settings']);
      final rows = data['reports'];
      if (rows is List) {
        for (final row in rows) {
          try {
            final report = DiagnosticReport.fromJson(row);
            if (report.id.isNotEmpty && report.fingerprint.isNotEmpty) _reports.add(report);
          } on FormatException {
            continue;
          }
        }
      }
      _reports.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      if (_reports.length > _queueLimit) _reports.removeRange(_queueLimit, _reports.length);
      final last = data['lastSuccessfulUpload'];
      _lastSuccessfulUpload = last is String ? DateTime.tryParse(last)?.toUtc() : null;
      for (var i = 0; i < _reports.length; i++) {
        final report = _reports[i];
        if (report.status == DiagnosticStatus.uploading) {
          _reports[i] = report.copyWith(status: report.uploadApproved ? DiagnosticStatus.queued : DiagnosticStatus.waitingForReview);
        }
        if (!_settings.consentGranted && _reports[i].uploadApproved) {
          _reports[i] = _reports[i].copyWith(uploadApproved: false, status: DiagnosticStatus.waitingForReview);
        }
      }
    } catch (error) {
      _settings = const DiagnosticSettings();
      storageWarning = sanitizeDiagnosticText(error.runtimeType.toString());
    }
    try {
      _relayCredentialConfigured = _validRelayBearer(await relaySecretStore.read());
    } catch (error) {
      _relayCredentialConfigured = false;
      storageWarning ??= sanitizeDiagnosticText(error.runtimeType.toString());
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> configure(DiagnosticSettings settings) async {
    await initialize();
    if (_busy) throw StateError('Wait for the current report upload before changing relay settings.');
    if (settings.autoReportingEnabled && !settings.consentGranted) throw StateError('Explicit consent is required to enable automatic reporting.');
    final normalizedEndpoint = settings.backendEndpoint.trim();
    if (normalizedEndpoint.isNotEmpty && !UserRelayDiagnosticUploader.validEndpoint(Uri.tryParse(normalizedEndpoint) ?? Uri())) {
      throw const FormatException('The endpoint must be an HTTPS user-owned relay URL.');
    }
    if (!validDiagnosticRepository(settings.repository)) throw const FormatException('Repository must be owner/name.');
    final endpointChanged = normalizedEndpoint != _settings.backendEndpoint;
    final consentRevoked = _settings.consentGranted && !settings.consentGranted;
    final reviewWasEnabled = !_settings.reviewBeforeUpload && settings.reviewBeforeUpload;
    _settings = settings.copyWith(backendEndpoint: normalizedEndpoint);
    for (var i = 0; i < _reports.length; i++) {
      final report = _reports[i];
      if (report.status == DiagnosticStatus.sent || report.isLocalTest) continue;
      if (endpointChanged || consentRevoked || reviewWasEnabled) {
        _reports[i] = report.copyWith(status: DiagnosticStatus.waitingForReview, uploadApproved: false, clearNextAttemptAt: true);
      } else if (settings.autoReportingEnabled && !settings.reviewBeforeUpload && settings.consentGranted) {
        _reports[i] = report.copyWith(status: DiagnosticStatus.queued, uploadApproved: true);
      }
    }
    if (!await _persist()) throw StateError('Diagnostic settings could not be saved locally.');
    notifyListeners();
    if (settings.consentGranted && settings.autoReportingEnabled && !settings.reviewBeforeUpload) unawaited(retryPending());
  }

  Future<void> saveRelayCredential(String secret) async {
    await initialize();
    if (_busy) throw StateError('Wait for the current report upload before changing relay credentials.');
    await relaySecretStore.save(secret);
    _relayCredentialConfigured = true;
    _revokePendingApprovals();
    if (!await _persist()) throw StateError('Relay credential metadata could not be saved locally.');
    notifyListeners();
  }

  Future<void> clearRelayCredential() async {
    await initialize();
    if (_busy) throw StateError('Wait for the current report upload before deleting relay credentials.');
    await relaySecretStore.delete();
    _relayCredentialConfigured = false;
    _revokePendingApprovals();
    if (!await _persist()) throw StateError('Relay settings could not be saved locally.');
    notifyListeners();
  }

  void _revokePendingApprovals() {
    for (var i = 0; i < _reports.length; i++) {
      final report = _reports[i];
      if (report.status == DiagnosticStatus.sent || report.isLocalTest) continue;
      _reports[i] = report.copyWith(status: DiagnosticStatus.waitingForReview, uploadApproved: false, clearNextAttemptAt: true);
    }
  }

  Future<DiagnosticReport> record(
    Object error, {
    StackTrace? stackTrace,
    required DiagnosticCategory category,
    String? message,
    String? errorType,
    DiagnosticReportType? reportType,
    DiagnosticSeverity? severity,
    String component = 'app',
    String? moduleVersion,
    String? assessmentId,
    String? executionId,
    String? runtimeStatus,
    String reproductionSteps = '',
  }) async {
    await initialize();
    final now = _clock().toUtc();
    String? safeIdentifier(String? value) {
      if (value == null || value.isEmpty || value.length > 128 || !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) return null;
      return value;
    }
    final safeType = sanitizeDiagnosticText(errorType ?? error.runtimeType.toString(), maxLength: 100);
    final resolvedType = reportType ?? reportTypeForCategory(category);
    final safeMessage = sanitizeDiagnosticMessage(message ?? error.toString(), category, maxLength: 900);
    final safeStack = sanitizeDiagnosticStack(stackTrace);
    final safeComponent = sanitizeDiagnosticText(component, maxLength: 80);
    final safeSteps = sanitizeDiagnosticText(reproductionSteps, maxLength: 1200);
    final safeAssessmentId = safeIdentifier(assessmentId);
    final safeExecutionId = safeIdentifier(executionId);
    final safeRuntimeStatus = runtimeStatus == null ? null : sanitizeDiagnosticText(runtimeStatus, maxLength: 120);
    // When a stack is present, identify repeats by the originating frames rather
    // than volatile message text (for example, an ArgumentError value). Keep the
    // message in the key for stackless reports so unrelated errors do not merge.
    final fingerprintMessage = safeStack.isEmpty ? safeMessage.toLowerCase() : '';
    final key = '${resolvedType.name}|${safeComponent.toLowerCase()}|$safeType|$fingerprintMessage|${safeStack.split('\n').take(4).join('|').replaceAll(RegExp(r':\d+'), ':#')}';
    final fingerprint = sha256.convert(utf8.encode(key)).toString();
    final duplicate = _reports.indexWhere((row) => row.fingerprint == fingerprint && now.difference(row.lastSeen) < const Duration(days: 1));
    final automaticApproval = _settings.consentGranted && _settings.autoReportingEnabled && !_settings.reviewBeforeUpload;
    if (duplicate >= 0) {
      final old = _reports[duplicate];
      final status = old.status == DiagnosticStatus.sent
          ? (automaticApproval ? DiagnosticStatus.queued : DiagnosticStatus.waitingForReview)
          : old.status == DiagnosticStatus.uploading
              ? DiagnosticStatus.uploading
              : _settings.reviewBeforeUpload
                  ? DiagnosticStatus.waitingForReview
                  : automaticApproval
                      ? DiagnosticStatus.queued
                      : old.status;
      _reports[duplicate] = old.copyWith(
        lastSeen: now,
        occurrences: (old.occurrences + 1).clamp(1, 100000).toInt(),
        status: status,
        uploadApproved: old.status == DiagnosticStatus.uploading ? automaticApproval : (old.status == DiagnosticStatus.sent ? automaticApproval : (automaticApproval || (!_settings.reviewBeforeUpload && old.uploadApproved))),
      );
      final saved = await _persist();
      notifyListeners();
      if (saved && automaticApproval) unawaited(retryPending());
      return _reports[duplicate];
    }
    final report = DiagnosticReport(
      id: '${now.microsecondsSinceEpoch}-${fingerprint.substring(0, 10)}',
      fingerprint: fingerprint,
      category: category,
      reportType: resolvedType,
      severity: severity,
      component: safeComponent.isEmpty ? 'app' : safeComponent,
      errorType: safeType,
      message: safeMessage,
      stack: safeStack,
      reproductionSteps: safeSteps,
      firstSeen: now,
      lastSeen: now,
      appVersion: sanitizeDiagnosticText(appVersion),
      buildNumber: sanitizeDiagnosticText(buildNumber),
      moduleVersion: sanitizeDiagnosticText(moduleVersion ?? appVersion),
      androidVersion: sanitizeDiagnosticText(androidVersion),
      assessmentId: safeAssessmentId,
      executionId: safeExecutionId,
      runtimeStatus: safeRuntimeStatus,
      status: automaticApproval ? DiagnosticStatus.queued : (_settings.reviewBeforeUpload ? DiagnosticStatus.waitingForReview : DiagnosticStatus.queued),
      uploadApproved: automaticApproval,
    );
    _reports.insert(0, report);
    if (_reports.length > _queueLimit) _reports.removeRange(_queueLimit, _reports.length);
    final saved = await _persist();
    notifyListeners();
    if (saved && automaticApproval) unawaited(retryPending());
    return report;
  }

  Future<DiagnosticReport> recordBugReport({
    required String title,
    required String description,
    required String reproductionSteps,
    required DiagnosticSeverity severity,
    required String component,
  }) =>
      record(
        StateError('User submitted bug report'),
        category: DiagnosticCategory.bug,
        reportType: DiagnosticReportType.bugReport,
        severity: severity,
        component: component,
        errorType: 'UserSubmittedBug',
        message: '${title.trim()}\n${description.trim()}',
        reproductionSteps: reproductionSteps,
      );

  /// Adds a synthetic, persistent report to verify the local diagnostics UI.
  /// This item is permanently excluded from automatic and manual uploads.
  Future<DiagnosticReport> recordLocalTestReport({String message = 'Laporan uji lokal. Ini bukan error aplikasi yang sebenarnya.'}) async {
    await initialize();
    final now = _clock().toUtc();
    final id = 'local-test-${now.microsecondsSinceEpoch}';
    final fingerprint = sha256.convert(utf8.encode(id)).toString();
    final report = DiagnosticReport(
      id: id,
      fingerprint: fingerprint,
      category: DiagnosticCategory.dart,
      errorType: 'DiagnosticSelfTest',
      message: sanitizeDiagnosticText(message),
      stack: '',
      firstSeen: now,
      lastSeen: now,
      appVersion: sanitizeDiagnosticText(appVersion),
      buildNumber: sanitizeDiagnosticText(buildNumber),
      androidVersion: sanitizeDiagnosticText(androidVersion),
      status: DiagnosticStatus.waitingForReview,
      isLocalTest: true,
    );
    _reports.insert(0, report);
    if (_reports.length > _queueLimit) _reports.removeRange(_queueLimit, _reports.length);
    await _persist();
    notifyListeners();
    return report;
  }

  Future<void> approveAndUpload(String id) async {
    await initialize();
    if (!_settings.consentGranted) throw StateError('Explicit consent is required to approve an upload.');
    if (!hasRelay) throw StateError('Configure a private HTTPS relay and secure relay credential first.');
    final index = _reports.indexWhere((row) => row.id == id);
    if (index < 0 || _reports[index].isLocalTest || _reports[index].attempts >= maxAttempts) return;
    _reports[index] = _reports[index].copyWith(
      status: DiagnosticStatus.queued,
      uploadApproved: true,
      clearNextAttemptAt: true,
    );
    if (!await _persist()) throw StateError('The approved report could not be saved locally; upload was not started.');
    notifyListeners();
    await _uploadById(id);
  }

  Future<void> retryPending() async {
    await initialize();
    if (_busy || !_settings.consentGranted || !hasRelay) return;
    if (_settings.wifiOnly && !await _isWifiAvailable()) return;
    final now = _clock().toUtc();
    final eligibleIds = _reports
        .where((row) => row.uploadApproved && !row.isLocalTest && row.status != DiagnosticStatus.sent && row.status != DiagnosticStatus.uploading && row.attempts < maxAttempts)
        .where((row) => row.nextAttemptAt == null || !now.isBefore(row.nextAttemptAt!))
        .map((row) => row.id)
        .toList(growable: false);
    for (final id in eligibleIds) {
      if (_busy) break;
      await _uploadById(id);
    }
  }

  Future<void> _uploadById(String id) async {
    await initialize();
    if (_busy || !hasRelay || !_settings.consentGranted) return;
    var index = _reports.indexWhere((row) => row.id == id);
    if (index < 0) return;
    var report = _reports[index];
    if (report.isLocalTest || report.status == DiagnosticStatus.sent || report.attempts >= maxAttempts) return;
    final automaticApproval = _settings.consentGranted && _settings.autoReportingEnabled && !_settings.reviewBeforeUpload;
    if (!report.uploadApproved && !automaticApproval) return;
    if (_settings.wifiOnly && !await _isWifiAvailable()) return;

    _busy = true;
    String? bearerToken;
    try {
      try {
        bearerToken = await relaySecretStore.read();
      } catch (_) {
        bearerToken = null;
      }
      if (bearerToken == null || !_validRelayBearer(bearerToken)) {
        index = _reports.indexWhere((row) => row.id == id);
        if (index >= 0) {
          _relayCredentialConfigured = false;
          _reports[index] = _reports[index].copyWith(status: DiagnosticStatus.waitingForReview, uploadApproved: false, lastUploadError: 'RelayCredentialUnavailable');
        }
        return;
      }
      index = _reports.indexWhere((row) => row.id == id);
      if (index < 0) return;
      report = _reports[index];
      _reports[index] = report.copyWith(status: DiagnosticStatus.uploading);
      if (!await _persist()) {
        index = _reports.indexWhere((row) => row.id == id);
        if (index >= 0) _reports[index] = _reports[index].copyWith(status: DiagnosticStatus.queued);
        return;
      }
      notifyListeners();
      try {
        await uploader.upload(
          DiagnosticUploadRequest(report, _settings.repository),
          Uri.parse(_settings.backendEndpoint),
          bearerToken: bearerToken,
          timeout: requestTimeout,
        );
        index = _reports.indexWhere((row) => row.id == id);
        if (index >= 0) {
          final latest = _reports[index];
          final hasNewOccurrences = latest.occurrences > report.occurrences;
          final automaticRetryAllowed = _settings.consentGranted && _settings.autoReportingEnabled && !_settings.reviewBeforeUpload;
          _reports[index] = latest.copyWith(
            status: hasNewOccurrences
                ? (_settings.reviewBeforeUpload ? DiagnosticStatus.waitingForReview : DiagnosticStatus.queued)
                : DiagnosticStatus.sent,
            uploadApproved: hasNewOccurrences && automaticRetryAllowed,
            attempts: latest.attempts + 1,
            clearNextAttemptAt: true,
            lastUploadError: null,
            clearLastUploadError: true,
          );
          _lastSuccessfulUpload = _clock().toUtc();
        }
      } catch (error) {
        index = _reports.indexWhere((row) => row.id == id);
        if (index >= 0) {
          final latest = _reports[index];
          final attempts = latest.attempts + 1;
          const delays = [1, 5, 15, 60, 360];
          final delay = delays[(attempts - 1).clamp(0, delays.length - 1).toInt()];
          _reports[index] = latest.copyWith(
            status: latest.uploadApproved ? DiagnosticStatus.failed : DiagnosticStatus.waitingForReview,
            attempts: attempts,
            nextAttemptAt: latest.uploadApproved ? _clock().toUtc().add(Duration(minutes: delay)) : null,
            clearNextAttemptAt: !latest.uploadApproved,
            lastUploadError: sanitizeDiagnosticText(error.runtimeType.toString()),
          );
        }
      }
    } finally {
      _busy = false;
      await _persist();
      notifyListeners();
    }
  }

  Future<bool> _isWifiAvailable() async => _wifiStatusOverride ?? await _wifiAvailable();

  Future<bool> testConnection() async => testRelayEndpoint(_settings.backendEndpoint);

  Future<bool> testRelayEndpoint(String endpoint) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || !UserRelayDiagnosticUploader.validEndpoint(uri)) return false;
    return uploader.testConnection(uri, timeout: requestTimeout);
  }

  Future<void> deletePendingReports() async {
    if (_busy) return;
    _reports.removeWhere((row) => row.status != DiagnosticStatus.sent);
    await _persist();
    notifyListeners();
  }

  Future<void> clearLocalReports() async {
    if (_busy) return;
    _reports.clear();
    await _persist();
    notifyListeners();
  }

  String exportReport() => const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'settings': {
          'consentGranted': _settings.consentGranted,
          'autoReportingEnabled': _settings.autoReportingEnabled,
          'wifiOnly': _settings.wifiOnly,
          'reviewBeforeUpload': _settings.reviewBeforeUpload,
          'endpointConfigured': hasRelay,
          'repository': _settings.repository,
        },
        'lastSuccessfulUpload': _lastSuccessfulUpload?.toIso8601String(),
        'reports': _reports.map((row) => row.toJson()).toList(),
      });

  Future<bool> _persist() async {
    final previous = _persisting;
    final completed = Completer<void>();
    _persisting = completed.future;
    var saved = false;
    try {
      await previous;
      await store.save({
        'settings': _settings.toJson(),
        'reports': _reports.map((row) => row.toJson()).toList(),
        'lastSuccessfulUpload': _lastSuccessfulUpload?.toIso8601String(),
      });
      storageWarning = null;
      saved = true;
    } catch (error) {
      storageWarning = sanitizeDiagnosticText(error.runtimeType.toString());
    } finally {
      completed.complete();
    }
    return saved;
  }

}

class DiagnosticHooks {
  DiagnosticHooks._();
  static bool _installed = false;

  static void install(DiagnosticReporter reporter) {
    if (_installed) return;
    _installed = true;
    DiagnosticReporter.active = reporter;
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      DiagnosticReporter.recordGlobal(details.exception, stackTrace: details.stack, category: DiagnosticCategory.flutter);
      if (previousFlutter != null) {
        previousFlutter(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    final previousDispatcher = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.dart);
      return previousDispatcher?.call(error, stack) ?? true;
    };
  }
}

Future<bool> consumeNativeCrashFile(DiagnosticReporter reporter, File file) async {
  if (!await file.exists()) return false;
  final text = await file.readAsString();
  await reporter.record(Exception('Android uncaught native exception'), category: DiagnosticCategory.native, message: text);
  await file.delete();
  return true;
}
