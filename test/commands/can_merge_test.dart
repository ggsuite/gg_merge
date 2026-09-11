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
import 'package:gg_merge/src/commands/can_merge.dart';
import 'package:gg_merge/src/commands/has_local_references.dart';
import 'package:gg_merge/src/commands/is_behind_main.dart';
import 'package:gg_merge/src/commands/is_ahead_main.dart';
import 'package:gg_merge/src/commands/update_project_git.dart';

import '../helpers.dart';

// Mock classes for each dependency
class _MockHasLocalRef extends Mock implements HasLocalReferences {}

class _MockIsBehind extends Mock implements IsBehindMain {}

class _MockIsAhead extends Mock implements IsAheadMain {}

class _MockUpdateGit extends Mock implements UpdateProjectGit {}

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('CanMerge', () {
    late Directory d;
    late _MockHasLocalRef local;
    late _MockIsBehind behind;
    late _MockIsAhead ahead;
    late _MockUpdateGit updGit;
    late MockDefaultBranch defaultBranch;
    final messages = <String>[];
    final ggLog = messages.add;

    /// Stubs every dependency for the given outcome.
    void arrange({
      bool hasLocalReferences = false,
      bool isBehind = false,
      bool isAhead = true,
      String defaultBranchName = 'main',
    }) {
      when(
        () => updGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => local.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => hasLocalReferences);
      when(
        () => behind.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          mainBranch: any(named: 'mainBranch'),
        ),
      ).thenAnswer((_) async => isBehind);
      when(
        () => ahead.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          mainBranch: any(named: 'mainBranch'),
        ),
      ).thenAnswer((_) async => isAhead);
      mockDefaultBranch(defaultBranch, defaultBranchName);
    }

    CanMerge createCanMerge() => CanMerge(
      ggLog: ggLog,
      hasLocalReferences: local,
      isBehindMain: behind,
      isAheadMain: ahead,
      updateProjectGit: updGit,
      defaultBranch: defaultBranch,
    );

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      local = _MockHasLocalRef();
      behind = _MockIsBehind();
      ahead = _MockIsAhead();
      updGit = _MockUpdateGit();
      defaultBranch = MockDefaultBranch();
      messages.clear();
    });
    tearDown(() async => d.delete(recursive: true));

    test('returns true if all checks pass (ok)', () async {
      arrange();
      final result = await createCanMerge().exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      expect(messages.last, contains('Checking if merge is allowed'));
    });

    test('throws if hasLocalReferences is true', () async {
      arrange(hasLocalReferences: true);
      expect(
        () => createCanMerge().exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('path:'),
          ),
        ),
      );
    });

    test('throws if isBehindMain is true', () async {
      arrange(isBehind: true);
      expect(
        () => createCanMerge().exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('behind main'),
          ),
        ),
      );
    });

    test('throws if isAheadMain is false', () async {
      arrange(isAhead: false);
      expect(
        () => createCanMerge().exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('nothing to merge'),
          ),
        ),
      );
    });

    test('resolves the default branch once and hands it on', () async {
      arrange(defaultBranchName: 'develop');
      final result = await createCanMerge().get(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      verify(() => defaultBranch.get(directory: d, ggLog: ggLog)).called(1);
      verify(
        () => behind.get(directory: d, ggLog: ggLog, mainBranch: 'develop'),
      ).called(1);
      verify(() => ahead.get(directory: d, ggLog: ggLog, mainBranch: 'develop'))
          .called(1);
    });

    test('names the default branch in the behind message', () async {
      arrange(defaultBranchName: 'develop', isBehind: true);
      await expectLater(
        () => createCanMerge().get(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('behind develop. Please rebase or merge develop first'),
          ),
        ),
      );
    });

    test('names the default branch in the not-ahead message', () async {
      arrange(defaultBranchName: 'develop', isAhead: false);
      await expectLater(
        () => createCanMerge().get(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('not ahead of develop'),
          ),
        ),
      );
    });

    test('uses mainBranch when the caller names it', () async {
      arrange();
      final result = await createCanMerge().get(
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
        () => behind.get(directory: d, ggLog: ggLog, mainBranch: 'release'),
      ).called(1);
      verify(() => ahead.get(directory: d, ggLog: ggLog, mainBranch: 'release'))
          .called(1);
    });

    test('throws when the repository has no default branch', () async {
      arrange(defaultBranchName: '');
      await expectLater(
        () => createCanMerge().get(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('No default branch found (origin/HEAD, main, master)'),
          ),
        ),
      );
      verifyNever(
        () => behind.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          mainBranch: any(named: 'mainBranch'),
        ),
      );
    });

    group('with a repository whose default branch is develop', () {
      late Directory localRepo;
      late Directory remote;
      late CanMerge canMerge;

      setUp(() async {
        (localRepo, remote) = await initLocalAndRemoteGitWithDefault('develop');
        arrange();
        // Real default-branch, behind and ahead checks; the manifest and
        // remote-update steps stay mocked.
        canMerge = CanMerge(
          ggLog: ggLog,
          hasLocalReferences: local,
          updateProjectGit: updGit,
        );
        await runGitOrThrow(localRepo, ['checkout', '-b', 'feature']);
      });

      tearDown(() async {
        await localRepo.delete(recursive: true);
        await remote.delete(recursive: true);
      });

      test('allows merging a feature branch ahead of develop', () async {
        await addAndCommitSampleFile(localRepo, fileName: 'work', content: 'x');
        final result = await canMerge.get(directory: localRepo, ggLog: ggLog);
        expect(result, isTrue);
      });

      test('rejects a feature branch without own commits', () async {
        await expectLater(
          () => canMerge.get(directory: localRepo, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('not ahead of develop'),
            ),
          ),
        );
      });

      test('rejects a feature branch behind develop', () async {
        await runGitOrThrow(localRepo, ['checkout', 'develop']);
        await addAndCommitSampleFile(
          localRepo,
          fileName: 'later',
          content: 'x',
        );
        await runGitOrThrow(localRepo, ['push']);
        await runGitOrThrow(localRepo, ['checkout', 'feature']);
        await expectLater(
          () => canMerge.get(directory: localRepo, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('behind develop'),
            ),
          ),
        );
      });
    });
  });
}
