// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_git/gg_git.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_merge/src/commands/update_project_git.dart';

import '../helpers.dart';

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('UpdateProjectGit', () {
    late Directory d;
    late UpdateProjectGit updateProjectGit;
    late MockGgProcessWrapper processWrapper;
    final messages = <String>[];
    final ggLog = messages.add;

    const fetch = ['fetch', '--all', '-p'];
    const upstream = ['rev-parse', '--verify', '--quiet', '@{u}'];
    const pull = ['pull'];
    const dropped = 'Connection to github.com closed by remote host.';

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      processWrapper = MockGgProcessWrapper();
      updateProjectGit = UpdateProjectGit(
        ggLog: ggLog,
        processWrapper: processWrapper,
        gitRetry: GitRetry.example,
      );
      messages.clear();
    });

    tearDown(() async => d.delete(recursive: true));

    // .........................................................................
    /// Lets `git <args>` answer with [exitCodes], one per call.
    void mockGit(List<String> args, List<int> exitCodes, {String stderr = ''}) {
      final codes = [...exitCodes];
      when(
        () => processWrapper.run(
          'git',
          args,
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async {
        final code = codes.length > 1 ? codes.removeAt(0) : codes.first;
        return ProcessResult(0, code, '', code == 0 ? '' : stderr);
      });
    }

    void verifyGit(List<String> args, int count) => verify(
      () => processWrapper.run(
        'git',
        args,
        runInShell: true,
        workingDirectory: d.path,
      ),
    ).called(count);

    // .........................................................................
    test('runs fetch and pull successfully', () async {
      mockGit(fetch, [0]);
      mockGit(upstream, [0]);
      mockGit(pull, [0]);

      final result = await updateProjectGit.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      verifyGit(pull, 1);
    });

    test('throws Exception if fetch fails', () async {
      mockGit(fetch, [1], stderr: 'fail-fetch');

      expect(
        () => updateProjectGit.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('git fetch --all failed: fail-fetch'),
          ),
        ),
      );
    });

    test('throws Exception if pull fails', () async {
      mockGit(fetch, [0]);
      mockGit(upstream, [0]);
      mockGit(pull, [1], stderr: 'fail-pull');

      expect(
        () => updateProjectGit.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('git pull failed: fail-pull'),
          ),
        ),
      );
    });

    test('skips the pull when the branch has no upstream left', () async {
      mockGit(fetch, [0]);
      mockGit(upstream, [1]);

      final result = await updateProjectGit.get(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      verifyNever(
        () => processWrapper.run(
          'git',
          pull,
          runInShell: true,
          workingDirectory: d.path,
        ),
      );
      expect(
        messages.join('\n'),
        contains(
          'The current branch has no upstream to pull from (never pushed, '
          'or merged and deleted on the remote). Skipping git pull.',
        ),
      );
    });

    test('retries a fetch the remote dropped and then succeeds', () async {
      mockGit(fetch, [1, 0], stderr: dropped);
      mockGit(upstream, [0]);
      mockGit(pull, [0]);

      final result = await updateProjectGit.get(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      verifyGit(fetch, 2);
      expect(messages.join('\n'), contains('git fetch --all -p failed'));
    });

    test('retries a pull the remote dropped and then succeeds', () async {
      mockGit(fetch, [0]);
      mockGit(upstream, [0]);
      mockGit(pull, [1, 0], stderr: dropped);

      final result = await updateProjectGit.get(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      verifyGit(pull, 2);
      expect(messages.join('\n'), contains('git pull failed'));
    });

    // .........................................................................
    group('with a real repository', () {
      late Directory local;
      late Directory remote;

      setUp(() async {
        (local, remote) = await initLocalAndRemoteGitWithDefault('main');
        updateProjectGit = UpdateProjectGit(ggLog: ggLog);
      });

      tearDown(() async {
        await local.delete(recursive: true);
        await remote.delete(recursive: true);
      });

      test('pulls a branch whose upstream exists', () async {
        final result = await updateProjectGit.get(
          directory: local,
          ggLog: ggLog,
        );
        expect(result, isTrue);
        expect(messages.join('\n'), isNot(contains('Skipping git pull')));
      });

      test(
        'skips the pull after the remote branch was merged and deleted',
        () async {
          await runGitOrThrow(local, ['checkout', '-b', 'feature']);
          await runGitOrThrow(local, [
            'push',
            '--set-upstream',
            'origin',
            'feature',
          ]);
          // The provider completed the pull request and deleted the branch
          await runGitOrThrow(local, ['push', 'origin', '--delete', 'feature']);

          final result = await updateProjectGit.get(
            directory: local,
            ggLog: ggLog,
          );
          expect(result, isTrue);
          expect(messages.join('\n'), contains('Skipping git pull'));
        },
      );
    });
  });
}
