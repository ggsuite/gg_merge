// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_merge/src/commands/local_merge.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers.dart';

// ignore_for_file: unused_import

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('LocalMerge', () {
    late Directory d;
    late LocalMerge localMerge;
    late MockGgProcessWrapper processWrapper;
    late MockDefaultBranch defaultBranch;
    final messages = <String>[];
    final ggLog = messages.add;

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      processWrapper = MockGgProcessWrapper();
      defaultBranch = MockDefaultBranch();
      mockDefaultBranch(defaultBranch, 'main');
      localMerge = LocalMerge(
        ggLog: ggLog,
        processWrapper: processWrapper,
        defaultBranch: defaultBranch,
      );
      messages.clear();
    });

    tearDown(() async {
      await d.delete(recursive: true);
    });

    void mockCurrentBranch(String branch) {
      when(
        () => processWrapper.run(
          any(),
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, branch, ''));
    }

    void mockCheckoutMain({
      String branch = 'main',
      int exitCode = 0,
      String stderr = '',
    }) {
      when(
        () => processWrapper.run(
          any(),
          ['checkout', branch],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, exitCode, '', stderr));
    }

    void mockSquash(String branch, {int exitCode = 0, String stderr = ''}) {
      when(
        () => processWrapper.run(
          any(),
          ['merge', branch, '--squash'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, exitCode, '', stderr));
    }

    void mockCommit(String message, {int exitCode = 0, String stderr = ''}) {
      when(
        () => processWrapper.run(
          any(),
          ['commit', '-m', message],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, exitCode, '', stderr));
    }

    test('performs successful local merge', () async {
      mockCurrentBranch('feature-branch');
      mockCheckoutMain();
      mockSquash('feature-branch');
      mockCommit('Merged feature-branch into main');

      final result = await localMerge.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      expect(
        messages.any((m) => m.contains('✓ Local merge successful.')),
        isTrue,
      );
    });

    test('performs successful local merge with custom message', () async {
      mockCurrentBranch('feature-branch');
      mockCheckoutMain();
      mockSquash('feature-branch');
      mockCommit('Custom merge message');

      final result = await localMerge.get(
        directory: d,
        ggLog: ggLog,
        message: 'Custom merge message',
      );
      expect(result, isTrue);
      expect(
        messages.any((m) => m.contains('✓ Local merge successful.')),
        isTrue,
      );
    });

    test('does not run pub get or stage pubspec.lock', () async {
      mockCurrentBranch('feature-branch');
      mockCheckoutMain();
      mockSquash('feature-branch');
      mockCommit('Merged feature-branch into main');

      final result = await localMerge.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      verifyNever(
        () => processWrapper.run(
          any(),
          ['pub', 'get'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      );
      verifyNever(
        () => processWrapper.run(
          any(),
          ['add', 'pubspec.lock'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      );
    });

    test('throws if already on main', () async {
      mockCurrentBranch('main');
      expect(
        () => localMerge.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Already on main'),
          ),
        ),
      );
    });

    test('throws on merge failure', () async {
      mockCurrentBranch('feature');
      mockCheckoutMain();
      mockSquash('feature', exitCode: 1, stderr: 'conflict');
      expect(
        () => localMerge.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Merge failed'),
          ),
        ),
      );
    });

    test('throws on commit failure', () async {
      mockCurrentBranch('feature');
      mockCheckoutMain();
      mockSquash('feature');
      mockCommit(
        'Merged feature into main',
        exitCode: 1,
        stderr: 'commit error',
      );
      expect(
        () => localMerge.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Commit failed'),
          ),
        ),
      );
    });

    test('throws Exception if getting current branch fails', () async {
      when(
        () => processWrapper.run(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'git error'));
      expect(
        () => localMerge.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to get current branch: git error'),
          ),
        ),
      );
    });

    test('throws Exception if checkout to main fails', () async {
      mockCurrentBranch('feature');
      when(
        () => processWrapper.run(
          'git',
          ['checkout', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'checkout error'));
      expect(
        () => localMerge.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to checkout main: checkout error'),
          ),
        ),
      );
    });

    test('merges into the default branch of the repository', () async {
      mockDefaultBranch(defaultBranch, 'develop');
      mockCurrentBranch('feature');
      mockCheckoutMain(branch: 'develop');
      mockSquash('feature');
      mockCommit('Merged feature into develop');

      final result = await localMerge.get(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      verify(
        () => processWrapper.run(
          any(),
          ['checkout', 'develop'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
      verify(
        () => processWrapper.run(
          any(),
          ['commit', '-m', 'Merged feature into develop'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
    });

    test('merges into mainBranch when the caller names it', () async {
      mockCurrentBranch('feature');
      mockCheckoutMain(branch: 'release');
      mockSquash('feature');
      mockCommit('Merged feature into release');

      final result = await localMerge.get(
        directory: d,
        ggLog: ggLog,
        mainBranch: 'release',
      );
      expect(result, isTrue);
      verifyNever(
        () => defaultBranch.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      );
    });

    test('throws if already on the default branch', () async {
      mockDefaultBranch(defaultBranch, 'develop');
      mockCurrentBranch('develop');
      expect(
        () => localMerge.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Already on develop'),
          ),
        ),
      );
    });

    test('throws when the repository has no default branch', () async {
      mockDefaultBranch(defaultBranch, '');
      await expectLater(
        () => localMerge.get(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('No default branch found (origin/HEAD, main, master)'),
          ),
        ),
      );
      verifyNever(
        () => processWrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
    });

    group('with a repository whose default branch is develop', () {
      late Directory local;
      late Directory remote;

      setUp(() async {
        (local, remote) = await initLocalAndRemoteGitWithDefault('develop');
        localMerge = LocalMerge(ggLog: ggLog);
      });

      tearDown(() async {
        await local.delete(recursive: true);
        await remote.delete(recursive: true);
      });

      test('squash-merges the feature branch into develop', () async {
        await runGitOrThrow(local, ['checkout', '-b', 'feature']);
        await addAndCommitSampleFile(local, fileName: 'work', content: 'x');

        final result = await localMerge.get(directory: local, ggLog: ggLog);
        expect(result, isTrue);

        final branch = await runGitOrThrow(local, [
          'rev-parse',
          '--abbrev-ref',
          'HEAD',
        ]);
        expect(branch, 'develop');
        final subject = await runGitOrThrow(local, [
          'log',
          '-1',
          '--format=%s',
        ]);
        expect(subject, 'Merged feature into develop');
        expect(await File('${local.path}/work').exists(), isTrue);
      });

      test('refuses to merge develop into itself', () async {
        await expectLater(
          () => localMerge.get(directory: local, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Already on develop branch'),
            ),
          ),
        );
      });
    });

    group('--verbose', () {
      test('logs each executed command when the flag is set', () async {
        mockCurrentBranch('feature-branch');
        mockCheckoutMain();
        mockSquash('feature-branch');
        mockCommit('Merged feature-branch into main');

        final runner = CommandRunner<dynamic>('test', 'test')
          ..addCommand(localMerge);
        await runner.run(['local-merge', '--verbose', '--input', d.path]);

        expect(
          messages,
          containsAll([
            '\$ git rev-parse --abbrev-ref HEAD',
            '\$ git checkout main',
            '\$ git merge feature-branch --squash',
            '\$ git commit -m Merged feature-branch into main',
          ]),
        );
      });

      test('does not log commands when the flag is not set', () async {
        mockCurrentBranch('feature-branch');
        mockCheckoutMain();
        mockSquash('feature-branch');
        mockCommit('Merged feature-branch into main');

        final result = await localMerge.exec(directory: d, ggLog: ggLog);
        expect(result, isTrue);
        expect(messages.where((m) => m.startsWith('\$ ')), isEmpty);
      });
    });
  });
}
