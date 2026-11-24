import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const diagnosticLabels = <String>['bug', 'runtime-error', 'auto-report'];
const _queueLimit = 50;

String sanitizeDiagnosticText(String input, {int maxLength = 240}) {
  var text = input
      .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '[url]')
      .replaceAll(RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false), '[email]')
      .replaceAll(RegExp(r'(authorization|token|api[_-]?key|password|secret)\s*[:=]\s*[^\s,;]+', caseSensitive: false), r'$1=[redacted]')
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

String sanitizeDiagnosticMessage(String input, DiagnosticCategory category) {
  final safe = sanitizeDiagnosticText(input);
  if (category == DiagnosticCategory.network || category == DiagnosticCategory.package) {
    return safe.replaceAll(RegExp(r'\b(?:[a-z0-9-]+\.)+[a-z]{2,}\b', caseSensitive: false), '[host]');
  }
  return safe;
}

bool validDiagnosticRepository(String value) => RegExp(r'^[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}$').hasMatch(value);

enum DiagnosticCategory { flutter, dart, native, network, database, startup, runtime, package }
enum DiagnosticStatus { queued, waitingForReview, uploading, sent, failed }

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
    this.occurrences = 1,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastUploadError,
    this.isLocalTest = false,
  });
  final String id;
  final String fingerprint;
  final DiagnosticCategory category;
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
  final bool isLocalTest;

  DiagnosticReport copyWith({DateTime? lastSeen, DiagnosticStatus? status, int? occurrences, int? attempts, DateTime? nextAttemptAt, bool clearNextAttemptAt = false, String? lastUploadError}) => DiagnosticReport(
        id: id,
        fingerprint: fingerprint,
        category: category,
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
        lastUploadError: lastUploadError,
        isLocalTest: isLocalTest,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'fingerprint': fingerprint,
        'category': category.name,
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
        'isLocalTest': isLocalTest,
      };

  factory DiagnosticReport.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) throw const FormatException('Invalid diagnostic report.');
    DateTime date(Object? value) => DateTime.tryParse(value is String ? value : '')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    T enumeration<T extends Enum>(List<T> values, Object? name, T fallback) => values.firstWhere((value) => value.name == name, orElse: () => fallback);
    final id = json['id'];
    final fp = json['fingerprint'];
    final type = json['errorType'];
    final stack = json['stack'];
    final version = json['appVersion'];
    final build = json['buildNumber'];
    final android = json['androidVersion'];
    final next = json['nextAttemptAt'];
    final lastError = json['lastUploadError'];
    return DiagnosticReport(
      id: id is String ? id : '',
      fingerprint: fp is String ? fp : '',
      category: enumeration(DiagnosticCategory.values, json['category'], DiagnosticCategory.dart),
      errorType: sanitizeDiagnosticText(type is String ? type : 'Error'),
      message: sanitizeDiagnosticText(json['message'] is String ? json['message'] as String : ''),
      stack: sanitizeDiagnosticStack(StackTrace.fromString(stack is String ? stack : '')),
      firstSeen: date(json['firstSeen']),
      lastSeen: date(json['lastSeen']),
      appVersion: sanitizeDiagnosticText(version is String ? version : 'unknown'),
      buildNumber: sanitizeDiagnosticText(build is String ? build : 'unknown'),
      androidVersion: sanitizeDiagnosticText(android is String ? android : 'unknown'),
      status: enumeration(DiagnosticStatus.values, json['status'], DiagnosticStatus.queued),
      occurrences: json['occurrences'] is int ? (json['occurrences'] as int).clamp(1, 100000).toInt() : 1,
      attempts: json['attempts'] is int ? (json['attempts'] as int).clamp(0, 100).toInt() : 0,
      nextAttemptAt: next is String ? DateTime.tryParse(next)?.toUtc() : null,
      lastUploadError: lastError is String ? sanitizeDiagnosticText(lastError) : null,
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

class DiagnosticUploadRequest {
  const DiagnosticUploadRequest(this.report, this.repository);
  final DiagnosticReport report;
  final String repository;
  Map<String, Object?> toJson() => {'schemaVersion': 1, 'repository': repository, 'labels': diagnosticLabels, 'report': report.toJson()};
}

abstract interface class DiagnosticUploader {
  Future<void> upload(DiagnosticUploadRequest request, Uri endpoint, {required Duration timeout});
  Future<bool> testConnection(Uri endpoint, {required Duration timeout});
}

class UserRelayDiagnosticUploader implements DiagnosticUploader {
  UserRelayDiagnosticUploader({HttpClient Function()? clientFactory}) : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;
  static bool validEndpoint(Uri uri) => uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty && !uri.hasFragment && !uri.hasQuery;

  @override
  Future<void> upload(DiagnosticUploadRequest request, Uri endpoint, {required Duration timeout}) async {
    if (!validEndpoint(endpoint) || !validDiagnosticRepository(request.repository)) throw const FormatException('Configure an HTTPS user-owned relay and a valid repository.');
    final client = _clientFactory();
    try {
      final req = await client.postUrl(endpoint).timeout(timeout);
      req.followRedirects = false;
      req.maxRedirects = 0;
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.add(utf8.encode(jsonEncode(request.toJson())));
      final response = await req.close().timeout(timeout);
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Relay rejected the report (${response.statusCode}).');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> testConnection(Uri endpoint, {required Duration timeout}) async {
    if (!validEndpoint(endpoint)) return false;
    final client = _clientFactory();
    try {
      final req = await client.getUrl(endpoint).timeout(timeout);
      req.followRedirects = false;
      req.maxRedirects = 0;
      final response = await req.close().timeout(timeout);
      await response.drain<void>();
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
    Future<bool> Function()? wifiAvailable,
    DateTime Function()? clock,
    this.appVersion = '0.1.0',
    this.buildNumber = '1',
    this.androidVersion = 'Android',
    this.requestTimeout = const Duration(seconds: 8),
    this.maxAttempts = 5,
  })  : uploader = uploader ?? UserRelayDiagnosticUploader(),
        _wifiAvailable = wifiAvailable ?? (() async => false),
        _clock = clock ?? DateTime.now;

  static DiagnosticReporter? active;
  static void recordGlobal(Object error, {StackTrace? stackTrace, DiagnosticCategory category = DiagnosticCategory.dart}) {
    final current = active;
    if (current != null) unawaited(current.record(error, stackTrace: stackTrace, category: category));
  }

  final DiagnosticQueueStore store;
  final DiagnosticUploader uploader;
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
  DateTime? _lastSuccessfulUpload;
  bool _initialized = false;
  bool _busy = false;
  bool? _wifiStatusOverride;
  String? storageWarning;
  Timer? _retryTimer;

  void setWifiAvailability(bool available) {
    _wifiStatusOverride = available;
    if (_settings.autoReportingEnabled && _settings.wifiOnly && available) unawaited(retryPending());
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
  bool get hasRelay => UserRelayDiagnosticUploader.validEndpoint(Uri.tryParse(_settings.backendEndpoint) ?? Uri());

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
    } catch (error) {
      _settings = const DiagnosticSettings();
      storageWarning = sanitizeDiagnosticText(error.runtimeType.toString());
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> configure(DiagnosticSettings settings) async {
    if (settings.autoReportingEnabled && !settings.consentGranted) throw StateError('Explicit consent is required to enable automatic reporting.');
    if (settings.backendEndpoint.isNotEmpty && !UserRelayDiagnosticUploader.validEndpoint(Uri.tryParse(settings.backendEndpoint) ?? Uri())) {
      throw const FormatException('The endpoint must be an HTTPS user-owned relay URL.');
    }
    if (!validDiagnosticRepository(settings.repository)) throw const FormatException('Repository must be owner/name.');
    _settings = settings;
    for (var i = 0; i < _reports.length; i++) {
      final report = _reports[i];
      if (report.status == DiagnosticStatus.sent || report.status == DiagnosticStatus.uploading) continue;
      if (settings.reviewBeforeUpload) {
        _reports[i] = report.copyWith(status: DiagnosticStatus.waitingForReview);
      } else if (report.status == DiagnosticStatus.waitingForReview) {
        _reports[i] = report.copyWith(status: DiagnosticStatus.queued);
      }
    }
    await _persist();
    notifyListeners();
    if (settings.autoReportingEnabled && !settings.reviewBeforeUpload) unawaited(retryPending());
  }

  Future<DiagnosticReport> record(Object error, {StackTrace? stackTrace, required DiagnosticCategory category, String? message}) async {
    await initialize();
    final now = _clock().toUtc();
    final type = sanitizeDiagnosticText(error.runtimeType.toString());
    final safeMessage = sanitizeDiagnosticMessage(message ?? error.toString(), category);
    final safeStack = sanitizeDiagnosticStack(stackTrace);
    final key = '${category.name}|$type|${safeStack.split('\n').take(4).join('|').replaceAll(RegExp(r':\d+'), ':#')}';
    final fingerprint = sha256.convert(utf8.encode(key)).toString();
    final duplicate = _reports.indexWhere((row) => row.fingerprint == fingerprint && now.difference(row.lastSeen) < const Duration(days: 1));
    if (duplicate >= 0) {
      final old = _reports[duplicate];
      _reports[duplicate] = old.copyWith(
        lastSeen: now,
        occurrences: (old.occurrences + 1).clamp(1, 100000).toInt(),
        status: old.status == DiagnosticStatus.sent ? (_settings.reviewBeforeUpload ? DiagnosticStatus.waitingForReview : DiagnosticStatus.queued) : old.status,
      );
      await _persist();
      notifyListeners();
      if (_settings.autoReportingEnabled && !_settings.reviewBeforeUpload) unawaited(retryPending());
      return _reports[duplicate];
    }
    final report = DiagnosticReport(
      id: '${now.microsecondsSinceEpoch}-${fingerprint.substring(0, 10)}',
      fingerprint: fingerprint,
      category: category,
      errorType: type,
      message: safeMessage,
      stack: safeStack,
      firstSeen: now,
      lastSeen: now,
      appVersion: sanitizeDiagnosticText(appVersion),
      buildNumber: sanitizeDiagnosticText(buildNumber),
      androidVersion: sanitizeDiagnosticText(androidVersion),
      status: _settings.reviewBeforeUpload ? DiagnosticStatus.waitingForReview : DiagnosticStatus.queued,
    );
    _reports.insert(0, report);
    if (_reports.length > _queueLimit) _reports.removeRange(_queueLimit, _reports.length);
    await _persist();
    notifyListeners();
    if (_settings.autoReportingEnabled && !_settings.reviewBeforeUpload) unawaited(retryPending());
    return report;
  }

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
    final i = _reports.indexWhere((row) => row.id == id);
    if (i < 0 || _reports[i].isLocalTest || _reports[i].attempts >= maxAttempts) return;
    _reports[i] = _reports[i].copyWith(status: DiagnosticStatus.queued);
    await _persist();
    await _uploadAt(i);
  }

  Future<void> retryPending() async {
    await initialize();
    if (_busy || !_settings.consentGranted || !_settings.autoReportingEnabled || _settings.reviewBeforeUpload || !hasRelay) return;
    if (_settings.wifiOnly && !await _isWifiAvailable()) return;
    for (var i = 0; i < _reports.length; i++) {
      final report = _reports[i];
      if (report.isLocalTest || report.status == DiagnosticStatus.sent || report.status == DiagnosticStatus.waitingForReview || report.attempts >= maxAttempts) continue;
      if (report.nextAttemptAt != null && _clock().toUtc().isBefore(report.nextAttemptAt!)) continue;
      await _uploadAt(i);
    }
  }

  Future<void> _uploadAt(int index) async {
    if (index >= _reports.length || _reports[index].isLocalTest || _busy || !hasRelay || !_settings.consentGranted || !_settings.autoReportingEnabled) return;
    if (_settings.wifiOnly && !await _isWifiAvailable()) return;
    _busy = true;
    final report = _reports[index];
    _reports[index] = report.copyWith(status: DiagnosticStatus.uploading);
    notifyListeners();
    try {
      await uploader.upload(
        DiagnosticUploadRequest(report, _settings.repository),
        Uri.parse(_settings.backendEndpoint),
        timeout: requestTimeout,
      );
      _reports[index] = report.copyWith(status: DiagnosticStatus.sent, attempts: report.attempts + 1, clearNextAttemptAt: true, lastUploadError: null);
      _lastSuccessfulUpload = _clock().toUtc();
    } catch (error) {
      final attempts = report.attempts + 1;
      const delays = [1, 5, 15, 60, 360];
      final delay = delays[(attempts - 1).clamp(0, delays.length - 1).toInt()];
      _reports[index] = report.copyWith(
        status: DiagnosticStatus.failed,
        attempts: attempts,
        nextAttemptAt: _clock().toUtc().add(Duration(minutes: delay)),
        lastUploadError: sanitizeDiagnosticText(error.runtimeType.toString()),
      );
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
    _reports.removeWhere((row) => row.status != DiagnosticStatus.sent);
    await _persist();
    notifyListeners();
  }

  Future<void> clearLocalReports() async {
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

  Future<void> _persist() async {
    try {
      await store.save({
        'settings': _settings.toJson(),
        'reports': _reports.map((row) => row.toJson()).toList(),
        'lastSuccessfulUpload': _lastSuccessfulUpload?.toIso8601String(),
      });
      storageWarning = null;
    } catch (error) {
      storageWarning = sanitizeDiagnosticText(error.runtimeType.toString());
    }
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
