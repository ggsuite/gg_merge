// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_git/gg_git.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:gg_process/gg_process.dart';

import 'dart:io';

class MockGgProcessWrapper extends Mock implements GgProcessWrapper {}

/// Lets [defaultBranch] answer [name] for every directory.
void mockDefaultBranch(MockDefaultBranch defaultBranch, String name) {
  when(
    () => defaultBranch.get(
      directory: any(named: 'directory'),
      ggLog: any(named: 'ggLog'),
    ),
  ).thenAnswer((_) async => name);
}

/// Creates a local repository with a bare origin whose default branch is
/// [branch] — there is no `main` at all. `origin/HEAD` points at [branch],
/// the local checkout tracks `origin/[branch]` and holds one pushed commit.
Future<(Directory local, Directory remote)> initLocalAndRemoteGitWithDefault(
  String branch,
) async {
  final local = await Directory.systemTemp.createTemp('ggmerge_local_');
  final remote = await Directory.systemTemp.createTemp('ggmerge_remote_');
  await runGitOrThrow(remote, ['init', '--bare', '--initial-branch=$branch']);
  await runGitOrThrow(local, ['init', '--initial-branch=$branch']);
  await runGitOrThrow(local, ['config', 'user.email', 'test@example.com']);
  await runGitOrThrow(local, ['config', 'user.name', 'Test']);
  await runGitOrThrow(local, ['config', 'commit.gpgsign', 'false']);
  await addAndCommitSampleFile(local, fileName: 'init', content: 'init');
  await runGitOrThrow(local, ['remote', 'add', 'origin', remote.path]);
  await runGitOrThrow(local, ['push', '--set-upstream', 'origin', branch]);
  await runGitOrThrow(local, ['remote', 'set-head', 'origin', '--auto']);
  return (local, remote);
}

/// Runs git in [directory] and throws when it fails.
Future<String> runGitOrThrow(Directory directory, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: directory.path,
  );
  if (result.exitCode != 0) {
    throw Exception('git ${args.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout.toString().trim();
}

/// Helper to capture ggLog output
void capturePrint({
  required void Function(String) ggLog,
  required Future<void> Function() code,
}) async {
  final messages = <String>[];
  ggLog = messages.add;
  await code();
}

/// Fake Directory fallback for mocktail
class _FakeDirectory extends Fake implements Directory {}

/// Fake GgLog fallback
class _FakeGgLog extends Fake {
  void call(String _) {}
}

void registerTestFallbacks() {
  registerFallbackValue(_FakeDirectory());
  registerFallbackValue(<String>[]);
  registerFallbackValue(_FakeGgLog());
}
