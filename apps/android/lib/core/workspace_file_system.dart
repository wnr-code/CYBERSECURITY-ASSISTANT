import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum WorkspaceActor { terminal, gemini, localAi, runtime, market }
enum WorkspaceAction { list, read, write, createDirectory, delete }

class WorkspaceSecurityException implements Exception {
  const WorkspaceSecurityException(this.message);
  final String message;

  @override
  String toString() => message;
}

class WorkspaceEntry {
  const WorkspaceEntry({required this.path, required this.isDirectory, this.sizeBytes});
  final String path;
  final bool isDirectory;
  final int? sizeBytes;
}

typedef WorkspaceAccessAuthorizer = Future<bool> Function({
  required WorkspaceActor actor,
  required WorkspaceAction action,
  required String relativePath,
});

/// Capability-limited, text-only API for the user's project workspace.
///
/// No caller receives a Directory/File handle or an absolute path. All
/// operations are relative to the dedicated Documents/workspace root, require
/// an actor and per-operation authorization, reject links/path traversal and
/// keep app-private data directories outside this API. AI providers, runtime
/// adapters, and Market must not be given raw filesystem handles; if a future
/// feature needs project files it must use this same API and authorization.
class WorkspaceFileSystem {
  WorkspaceFileSystem._({required String canonicalRoot, required this.authorize}) : _root = canonicalRoot;

  static const maxTextBytes = 1024 * 1024;
  static const maxEntriesPerDirectory = 500;
  static const _blockedDirectoryNames = {
    '.ssh', '.gnupg', '.aws', 'credentials', 'credential', 'secrets', 'secret',
    'keystore', 'shared_prefs', 'databases', 'runtime_workspaces', 'market_packages', 'code_cache',
  };
  static const _blockedFileNames = {
    '.env', '.npmrc', '.pypirc', 'id_rsa', 'id_ed25519', 'credentials', 'credential',
    'secrets', 'secret', 'google-services.json', 'service-account.json',
  };
  static const _blockedExtensions = {
    '.apk', '.aab', '.dex', '.so', '.o', '.a', '.class', '.jar', '.war',
    '.exe', '.dll', '.dylib', '.bin', '.wasm', '.pyc', '.pyo',
    '.pem', '.p12', '.pfx', '.jks', '.keystore', '.key',
  };

  final String _root;
  final WorkspaceAccessAuthorizer authorize;
  static final Random _random = Random.secure();

  /// Creates a dedicated user workspace under application Documents and
  /// verifies that it does not overlap the app-support/private-data directory.
  static Future<WorkspaceFileSystem> forApplication({
    required WorkspaceAccessAuthorizer authorize,
    Future<Directory> Function()? documentsDirectoryProvider,
    Future<Directory> Function()? supportDirectoryProvider,
  }) async {
    final documents = await (documentsDirectoryProvider ?? getApplicationDocumentsDirectory)();
    final support = await (supportDirectoryProvider ?? getApplicationSupportDirectory)();
    return fromRoot(
      Directory(p.join(documents.path, 'user_workspace')),
      authorize: authorize,
      protectedRoots: [support],
    );
  }

  /// Test/embedding constructor. Production code should use [forApplication]
  /// so the root is selected from Android's app-specific Documents location.
  static Future<WorkspaceFileSystem> fromRoot(
    Directory workspaceRoot, {
    required WorkspaceAccessAuthorizer authorize,
    Iterable<Directory> protectedRoots = const [],
  }) async {
    final requestedRoot = p.normalize(p.absolute(workspaceRoot.path));
    for (final protectedRoot in protectedRoots) {
      final protectedPath = await _canonicalizeExistingRoot(protectedRoot);
      if (_pathsOverlap(requestedRoot, protectedPath)) {
        throw const WorkspaceSecurityException('Workspace cannot overlap app-private storage.');
      }
    }
    var existingAncestor = p.dirname(requestedRoot);
    while (await FileSystemEntity.type(existingAncestor, followLinks: false) == FileSystemEntityType.notFound) {
      final parent = p.dirname(existingAncestor);
      if (parent == existingAncestor) break;
      existingAncestor = parent;
    }
    if (await FileSystemEntity.type(existingAncestor, followLinks: false) == FileSystemEntityType.link) {
      throw const WorkspaceSecurityException('Workspace root cannot be a symbolic link.');
    }
    final canonicalAncestor = await Directory(existingAncestor).resolveSymbolicLinks();
    if (canonicalAncestor != existingAncestor) {
      throw const WorkspaceSecurityException('Workspace root resolved outside its configured location.');
    }
    if (await FileSystemEntity.type(requestedRoot, followLinks: false) == FileSystemEntityType.link) {
      throw const WorkspaceSecurityException('Workspace root cannot be a symbolic link.');
    }
    final root = Directory(requestedRoot);
    await root.create(recursive: true);
    final canonicalRoot = await root.resolveSymbolicLinks();
    if (canonicalRoot != requestedRoot) {
      throw const WorkspaceSecurityException('Workspace root resolved outside its configured location.');
    }
    return WorkspaceFileSystem._(canonicalRoot: canonicalRoot, authorize: authorize);
  }

  Future<List<WorkspaceEntry>> list(
    String relativeDirectory, {
    required WorkspaceActor actor,
  }) async {
    final safeRelative = _validateRelativePath(relativeDirectory, allowRoot: true, directory: true);
    await _authorize(actor, WorkspaceAction.list, safeRelative);
    final target = await _resolve(safeRelative, allowRoot: true, directory: true, createParents: false);
    final directory = Directory(target);
    if (!await directory.exists()) throw const WorkspaceSecurityException('Workspace directory does not exist.');
    final entries = <WorkspaceEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final relative = safeRelative.isEmpty ? name : p.posix.join(safeRelative, name);
      final child = await _resolve(relative, allowRoot: false, directory: false, createParents: false);
      final type = await FileSystemEntity.type(child, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const WorkspaceSecurityException('Symbolic links are not allowed in the user workspace.');
      }
      if (type == FileSystemEntityType.directory) {
        entries.add(WorkspaceEntry(path: relative, isDirectory: true));
      } else if (type == FileSystemEntityType.file) {
        final length = await File(child).length();
        entries.add(WorkspaceEntry(path: relative, isDirectory: false, sizeBytes: length));
      }
      if (entries.length > maxEntriesPerDirectory) {
        throw const WorkspaceSecurityException('Workspace directory contains too many entries.');
      }
    }
    entries.sort((left, right) => left.path.compareTo(right.path));
    return List.unmodifiable(entries);
  }

  Future<String> readText(String relativePath, {required WorkspaceActor actor}) async {
    final safeRelative = _validateRelativePath(relativePath, allowRoot: false, directory: false);
    await _authorize(actor, WorkspaceAction.read, safeRelative);
    final resolved = await _resolve(safeRelative, allowRoot: false, directory: false, createParents: false);
    final file = File(resolved);
    final type = await FileSystemEntity.type(resolved, followLinks: false);
    if (type != FileSystemEntityType.file) throw const WorkspaceSecurityException('Workspace file does not exist.');
    final length = await file.length();
    if (length > maxTextBytes) throw const WorkspaceSecurityException('Workspace text file exceeds the size limit.');
    final bytes = await file.readAsBytes();
    if (bytes.contains(0)) throw const WorkspaceSecurityException('Binary files cannot be read through the text workspace API.');
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const WorkspaceSecurityException('Workspace file is not valid UTF-8 text.');
    }
  }

  Future<void> writeText(
    String relativePath,
    String contents, {
    required WorkspaceActor actor,
    required bool overwrite,
  }) async {
    final safeRelative = _validateRelativePath(relativePath, allowRoot: false, directory: false);
    final bytes = utf8.encode(contents);
    if (bytes.length > maxTextBytes || contents.contains('\u0000')) {
      throw const WorkspaceSecurityException('Workspace text exceeds the size limit or contains binary data.');
    }
    await _authorize(actor, WorkspaceAction.write, safeRelative);
    final destinationPath = await _resolve(safeRelative, allowRoot: false, directory: false, createParents: true);
    final destination = File(destinationPath);
    final type = await FileSystemEntity.type(destinationPath, followLinks: false);
    if (type == FileSystemEntityType.link || (type == FileSystemEntityType.file && !overwrite)) {
      throw const WorkspaceSecurityException('Workspace file already exists or is unsafe to replace.');
    }
    if (type == FileSystemEntityType.directory || type == FileSystemEntityType.notFound) {
      if (type == FileSystemEntityType.directory) throw const WorkspaceSecurityException('A directory cannot be replaced by a text file.');
    }
    final temporary = File('$destinationPath.tmp-${_random.nextInt(1 << 32)}');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      // Revalidate immediately before atomic replacement so a substituted link
      // is rejected rather than followed by the write.
      await _resolve(safeRelative, allowRoot: false, directory: false, createParents: false);
      await temporary.rename(destinationPath);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> createDirectory(String relativePath, {required WorkspaceActor actor}) async {
    final safeRelative = _validateRelativePath(relativePath, allowRoot: false, directory: true);
    await _authorize(actor, WorkspaceAction.createDirectory, safeRelative);
    final target = await _resolve(safeRelative, allowRoot: false, directory: true, createParents: true);
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.link || type == FileSystemEntityType.file) {
      throw const WorkspaceSecurityException('Workspace directory path is occupied by an unsafe entry.');
    }
    await Directory(target).create();
  }

  Future<void> deleteFile(String relativePath, {required WorkspaceActor actor}) async {
    final safeRelative = _validateRelativePath(relativePath, allowRoot: false, directory: false);
    await _authorize(actor, WorkspaceAction.delete, safeRelative);
    final target = await _resolve(safeRelative, allowRoot: false, directory: false, createParents: false);
    if (await FileSystemEntity.type(target, followLinks: false) != FileSystemEntityType.file) {
      throw const WorkspaceSecurityException('Only regular workspace files can be deleted.');
    }
    await File(target).delete();
  }

  Future<void> _authorize(WorkspaceActor actor, WorkspaceAction action, String relativePath) async {
    // These components currently have no user-workspace use case and therefore
    // remain hard-denied even if an overly broad UI callback is supplied.
    if (actor != WorkspaceActor.terminal ||
        !await authorize(actor: actor, action: action, relativePath: relativePath)) {
      throw const WorkspaceSecurityException('Workspace access was not authorized.');
    }
  }

  String _validateRelativePath(String value, {required bool allowRoot, required bool directory}) {
    if (value.isEmpty && allowRoot) return '';
    if (value.isEmpty || value.startsWith('/') || value.startsWith('\\') || value.contains('\\') ||
        value.contains('\u0000') || value.contains(':') || value.length > 1024) {
      throw const WorkspaceSecurityException('Workspace path is invalid.');
    }
    final segments = value.split('/');
    if (segments.any((segment) => segment.isEmpty || segment == '.' || segment == '..')) {
      throw const WorkspaceSecurityException('Workspace path traversal is not allowed.');
    }
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final lower = segment.toLowerCase();
      if (_blockedDirectoryNames.contains(lower) ||
          (!directory || index == segments.length - 1) && _isBlockedFile(segment)) {
        throw const WorkspaceSecurityException('Private, credential, executable, and app-internal paths are not part of the workspace.');
      }
    }
    return p.posix.joinAll(segments);
  }

  bool _isBlockedFile(String name) {
    final lower = name.toLowerCase();
    return _blockedFileNames.contains(lower) ||
        lower.startsWith('.env.') ||
        _blockedExtensions.contains(p.posix.extension(lower));
  }

  Future<String> _resolve(
    String relativePath, {
    required bool allowRoot,
    required bool directory,
    required bool createParents,
  }) async {
    final rootType = await FileSystemEntity.type(_root, followLinks: false);
    if (rootType == FileSystemEntityType.link || rootType != FileSystemEntityType.directory) {
      throw const WorkspaceSecurityException('Workspace root resolved outside its configured location.');
    }
    if (await Directory(_root).resolveSymbolicLinks() != _root) {
      throw const WorkspaceSecurityException('Workspace root resolved outside its configured location.');
    }
    if (relativePath.isEmpty && allowRoot) return _root;
    final segments = relativePath.split('/');
    var current = _root;
    final parentCount = segments.length - 1;
    for (var index = 0; index < parentCount; index++) {
      current = p.join(current, segments[index]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const WorkspaceSecurityException('Symbolic links are not allowed in the user workspace.');
      }
      if (type == FileSystemEntityType.file) {
        throw const WorkspaceSecurityException('Workspace path traverses through a regular file.');
      }
      if (type == FileSystemEntityType.notFound && createParents) await Directory(current).create();
      if (type != FileSystemEntityType.notFound) {
        final canonical = await Directory(current).resolveSymbolicLinks();
        if (!_isWithinRoot(canonical)) throw const WorkspaceSecurityException('Workspace path resolved outside its root.');
      }
    }
    final target = p.join(_root, relativePath);
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw const WorkspaceSecurityException('Symbolic links are not allowed in the user workspace.');
    }
    if (type != FileSystemEntityType.notFound) {
      if (directory && type != FileSystemEntityType.directory) {
        throw const WorkspaceSecurityException('Workspace directory path is occupied by an unsafe entry.');
      }
      final canonical = await FileSystemEntity.resolveSymbolicLinks(target);
      if (!_isWithinRoot(canonical)) throw const WorkspaceSecurityException('Workspace path resolved outside its root.');
    }
    return target;
  }

  bool _isWithinRoot(String path) {
    final normalized = p.normalize(p.absolute(path));
    return normalized == _root || p.isWithin(_root, normalized);
  }

  static bool _pathsOverlap(String left, String right) =>
      left == right || p.isWithin(left, right) || p.isWithin(right, left);

  static Future<String> _canonicalizeExistingRoot(Directory directory) async {
    await directory.create(recursive: true);
    return directory.resolveSymbolicLinks();
  }
}
