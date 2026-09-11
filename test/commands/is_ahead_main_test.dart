// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:io';

import 'package:gg_git/gg_git.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_merge/src/commands/is_ahead_main.dart';

import '../helpers.dart';

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('IsAheadMain', () {
    late Directory d;
    late IsAheadMain isAheadMain;
    late MockGgProcessWrapper processWrapper;
    late MockDefaultBranch defaultBranch;
    final messages = <String>[];
    final ggLog = messages.add;

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      processWrapper = MockGgProcessWrapper();
      defaultBranch = MockDefaultBranch();
      mockDefaultBranch(defaultBranch, 'main');
      isAheadMain = IsAheadMain(
        ggLog: ggLog,
        processWrapper: processWrapper,
        defaultBranch: defaultBranch,
      );
      messages.clear();
    });
    tearDown(() async => d.delete(recursive: true));

    void mockRevList(String stdout) {
      when(
        () => processWrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, stdout, ''));
    }

    List<String> revListArgs(String branch) => [
      'rev-list',
      '--left-right',
      '--count',
      'origin/$branch...HEAD',
    ];

    test('returns true when ahead > 0', () async {
      mockRevList('0 1');
      final result = await isAheadMain.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });
    test('returns false when ahead == 0', () async {
      mockRevList('5 0');
      final result = await isAheadMain.exec(directory: d, ggLog: ggLog);
      expect(result, isFalse);
    });

    test('throws Exception if git rev-list fails', () async {
      when(
        () => processWrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'fatal'));
      expect(
        () => isAheadMain.exec(directory: d, ggLog: ggLog),
        throwsA(isA<Exception>()),
      );
    });

    test('compares against the default branch of the repository', () async {
      mockDefaultBranch(defaultBranch, 'develop');
      mockRevList('0 1');
      final result = await isAheadMain.get(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      verify(
        () => processWrapper.run(
          'git',
          revListArgs('develop'),
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
    });

    test('compares against mainBranch when the caller names it', () async {
      mockRevList('0 1');
      final result = await isAheadMain.get(
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
      verify(
        () => processWrapper.run(
          'git',
          revListArgs('release'),
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
    });

    test('throws when the repository has no default branch', () async {
      mockDefaultBranch(defaultBranch, '');
      await expectLater(
        () => isAheadMain.get(directory: d, ggLog: ggLog),
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
        isAheadMain = IsAheadMain(ggLog: ggLog);
      });

      tearDown(() async {
        await local.delete(recursive: true);
        await remote.delete(recursive: true);
      });

      test('is false when the feature branch has no own commits', () async {
        await runGitOrThrow(local, ['checkout', '-b', 'feature']);
        final result = await isAheadMain.get(directory: local, ggLog: ggLog);
        expect(result, isFalse);
      });

      test('is true when the feature branch has a commit', () async {
        await runGitOrThrow(local, ['checkout', '-b', 'feature']);
        await addAndCommitSampleFile(local, fileName: 'work', content: 'x');
        final result = await isAheadMain.get(directory: local, ggLog: ggLog);
        expect(result, isTrue);
      });
    });
  });
}
