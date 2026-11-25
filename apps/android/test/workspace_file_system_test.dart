import 'dart:io';

import 'package:cybersecurity_assistant/core/workspace_file_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;
  late Directory root;
  late Directory privateRoot;
  late Set<WorkspaceActor> deniedActors;
  late List<(WorkspaceActor, WorkspaceAction, String)> authorizations;
  late WorkspaceFileSystem workspace;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('workspace-boundary-test-');
    root = Directory('${sandbox.path}/projects');
    privateRoot = Directory('${sandbox.path}/app-private');
    deniedActors = {};
    authorizations = [];
    workspace = await WorkspaceFileSystem.fromRoot(
      root,
      protectedRoots: [privateRoot],
      authorize: ({required actor, required action, required relativePath}) async {
        authorizations.add((actor, action, relativePath));
        return !deniedActors.contains(actor);
      },
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('reads and writes project text only through an explicit actor-scoped grant', () async {
    await workspace.writeText('demo/lib/main.dart', 'void main() {}', actor: WorkspaceActor.terminal, overwrite: false);
    expect(await workspace.readText('demo/lib/main.dart', actor: WorkspaceActor.terminal), 'void main() {}');
    expect((await workspace.list('demo/lib', actor: WorkspaceActor.terminal)).single.path, 'demo/lib/main.dart');
    expect(authorizations.map((entry) => entry.$2), containsAll([WorkspaceAction.write, WorkspaceAction.read, WorkspaceAction.list]));
    expect(authorizations.every((entry) => entry.$1 == WorkspaceActor.terminal), isTrue);
  });

  test('denies access if authorization fails and does not create or mutate files', () async {
    deniedActors.add(WorkspaceActor.gemini);
    await expectLater(
      workspace.writeText('notes.txt', 'private prompt data', actor: WorkspaceActor.gemini, overwrite: false),
      throwsA(isA<WorkspaceSecurityException>()),
    );
    expect(await File('${root.path}/notes.txt').exists(), isFalse);
    await expectLater(
      workspace.list('', actor: WorkspaceActor.market),
      throwsA(isA<WorkspaceSecurityException>()),
    );
  });

  test('AI, runtime, and Market actors have no workspace access through an overbroad prompt callback', () async {
    for (final actor in [WorkspaceActor.gemini, WorkspaceActor.localAi, WorkspaceActor.runtime, WorkspaceActor.market]) {
      await expectLater(
        workspace.readText('project.dart', actor: actor),
        throwsA(isA<WorkspaceSecurityException>()),
        reason: '$actor must stay outside the workspace boundary.',
      );
    }
    expect(authorizations, isEmpty);
  });

  test('rejects traversal, absolute paths, reserved private names, credentials, and executable binaries', () async {
    for (final path in [
      '../outside.txt',
      'src/../../outside.txt',
      '/data/user/0/app/files/private.db',
      r'..\outside.txt',
      'C:/private.txt',
      '.env',
      '.env.production',
      'credentials.json',
      'secrets/key.txt',
      'build/release.apk',
      'native/libapp.so',
      'signing/upload.jks',
    ]) {
      await expectLater(
        workspace.writeText(path, 'data', actor: WorkspaceActor.terminal, overwrite: false),
        throwsA(isA<WorkspaceSecurityException>()),
        reason: 'Must reject workspace path $path',
      );
    }
    expect(await File('${sandbox.path}/outside.txt').exists(), isFalse);
  });

  test('rejects workspace roots overlapping app-private storage', () async {
    await expectLater(
      WorkspaceFileSystem.fromRoot(
        Directory('${privateRoot.path}/workspace'),
        protectedRoots: [privateRoot],
        authorize: ({required actor, required action, required relativePath}) async => true,
      ),
      throwsA(isA<WorkspaceSecurityException>()),
    );
  });

  test('rejects a symbolic-link workspace root before creating or accessing files', () async {
    final linkRoot = '${sandbox.path}/root-link';
    await Link(linkRoot).create(privateRoot.path);
    await expectLater(
      WorkspaceFileSystem.fromRoot(
        Directory(linkRoot),
        protectedRoots: [privateRoot],
        authorize: ({required actor, required action, required relativePath}) async => true,
      ),
      throwsA(isA<WorkspaceSecurityException>()),
    );
    expect(await File('${privateRoot.path}/workspace/marker').exists(), isFalse);
  });

  test('rejects symbolic links for both reads and writes', () async {
    final outside = File('${sandbox.path}/outside.txt')..writeAsStringSync('outside secret');
    await Link('${root.path}/escape.txt').create(outside.path);
    await Link('${root.path}/escape-dir').create('${privateRoot.path}');

    await expectLater(
      workspace.readText('escape.txt', actor: WorkspaceActor.terminal),
      throwsA(isA<WorkspaceSecurityException>()),
    );
    await expectLater(
      workspace.writeText('escape.txt', 'overwrite', actor: WorkspaceActor.terminal, overwrite: true),
      throwsA(isA<WorkspaceSecurityException>()),
    );
    await expectLater(
      workspace.writeText('escape-dir/owned.txt', 'overwrite', actor: WorkspaceActor.terminal, overwrite: false),
      throwsA(isA<WorkspaceSecurityException>()),
    );
    expect(outside.readAsStringSync(), 'outside secret');
  });

  test('limits text size, binary reads, and overwrites by default', () async {
    await workspace.writeText('readme.md', 'safe', actor: WorkspaceActor.terminal, overwrite: false);
    await expectLater(
      workspace.writeText('readme.md', 'changed', actor: WorkspaceActor.terminal, overwrite: false),
      throwsA(isA<WorkspaceSecurityException>()),
    );
    await workspace.writeText('binary.txt', 'not binary', actor: WorkspaceActor.terminal, overwrite: false);
    File('${root.path}/binary.txt').writeAsBytesSync([0, 1, 2]);
    await expectLater(
      workspace.readText('binary.txt', actor: WorkspaceActor.terminal),
      throwsA(isA<WorkspaceSecurityException>()),
    );
    await expectLater(
      workspace.writeText('large.txt', List.filled(WorkspaceFileSystem.maxTextBytes + 1, 'x').join(), actor: WorkspaceActor.terminal, overwrite: false),
      throwsA(isA<WorkspaceSecurityException>()),
    );
  });
}
