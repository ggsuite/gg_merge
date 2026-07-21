// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:io';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_merge/src/commands/merge_git.dart';
import '../helpers.dart';

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('MergeGit', () {
    late Directory d;
    late MergeGit mergeGit;
    late MockGgProcessWrapper processWrapper;
    final messages = <String>[];
    final ggLog = messages.add;

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      processWrapper = MockGgProcessWrapper();
      mergeGit = MergeGit(ggLog: ggLog, processWrapper: processWrapper);
      messages.clear();
    });
    tearDown(() async => d.delete(recursive: true));

    // .........................................................................
    // Helpers

    void stubOriginUrl(String url) {
      when(
        () => processWrapper.run(
          'git',
          ['config', '--get', 'remote.origin.url'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, url, ''));
    }

    void stubCurrentBranch(String branch) {
      when(
        () => processWrapper.run(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, branch, ''));
    }

    void stubGh(List<String> args, ProcessResult result) {
      when(
        () => processWrapper.run(
          'gh',
          args,
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => result);
    }

    /// Stubs the `gh repo view` merge-settings lookup.
    void stubGhRepoView(ProcessResult result) => stubGh([
      'repo',
      'view',
      '--json',
      'mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed',
    ], result);

    void stubAz(String subCommand, ProcessResult result) {
      when(
        () => processWrapper.run(
          'az',
          any(that: contains(subCommand)),
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => result);
    }

    /// Stubs an az call with exact [args] — needed when two calls share the
    /// same subcommand (e.g. the squash retry of `pr update`).
    void stubAzExact(List<String> args, ProcessResult result) {
      when(
        () => processWrapper.run(
          'az',
          args,
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => result);
    }

    List<String> azUpdateArgs({
      required String id,
      bool deleteSourceBranch = true,
      bool squash = false,
    }) => [
      'repos',
      'pr',
      'update',
      '--id',
      id,
      '--auto-complete',
      'true',
      if (deleteSourceBranch) ...['--delete-source-branch', 'true'],
      if (squash) ...['--squash', 'true'],
    ];

    // .........................................................................
    // GitHub

    group('GitHub', () {
      const mergeSettings =
          '{"mergeCommitAllowed":true,'
          '"squashMergeAllowed":true,"rebaseMergeAllowed":true}';

      test('creates a PR and sets automerge with branch delete', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        // No existing PR
        stubGh(['pr', 'view', '--json', 'number'], ProcessResult(1, 1, '', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, 'https://github.com/me/repo/pull/7', ''));
        stubGhRepoView(ProcessResult(0, 0, mergeSettings, ''));
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--merge',
          '--delete-branch',
        ], ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
        expect(
          messages.any(
            (m) => m.contains(
              'Created pull request: https://github.com/me/repo/pull/7',
            ),
          ),
          isTrue,
        );
      });

      test('omits --delete-branch when deleteSourceBranch is false', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubGh(['pr', 'view', '--json', 'number'], ProcessResult(1, 1, '', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, '', ''));
        stubGhRepoView(ProcessResult(0, 0, mergeSettings, ''));
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--merge',
        ], ProcessResult(0, 0, '', ''));

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
          deleteSourceBranch: false,
        );
        expect(result, isTrue);
        verify(
          () => processWrapper.run(
            'gh',
            ['pr', 'merge', '--auto', '--merge'],
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).called(1);
      });

      test('prefers squash when merge commits are not allowed', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubGh(['pr', 'view', '--json', 'number'], ProcessResult(1, 1, '', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, '', ''));
        stubGhRepoView(
          ProcessResult(
            0,
            0,
            '{"mergeCommitAllowed":false,'
                '"squashMergeAllowed":true,"rebaseMergeAllowed":true}',
            '',
          ),
        );
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--squash',
          '--delete-branch',
        ], ProcessResult(0, 0, '', ''));

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
      });

      test('falls back to rebase when only rebase is allowed', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubGh(['pr', 'view', '--json', 'number'], ProcessResult(1, 1, '', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, '', ''));
        stubGhRepoView(
          ProcessResult(
            0,
            0,
            '{"mergeCommitAllowed":false,'
                '"squashMergeAllowed":false,"rebaseMergeAllowed":true}',
            '',
          ),
        );
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--rebase',
          '--delete-branch',
        ], ProcessResult(0, 0, '', ''));

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
      });

      test('uses --merge when the settings lookup fails', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubGh(['pr', 'view', '--json', 'number'], ProcessResult(1, 1, '', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, '', ''));
        stubGhRepoView(ProcessResult(1, 1, '', 'no-settings'));
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--merge',
          '--delete-branch',
        ], ProcessResult(0, 0, '', ''));

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
      });

      test('uses --merge when the settings json is invalid or empty', () async {
        for (final settings in ['not-json', '[]', '{}']) {
          stubOriginUrl('https://github.com/me/repo.git');
          stubGh([
            'pr',
            'view',
            '--json',
            'number',
          ], ProcessResult(1, 1, '', ''));
          stubGh([
            'pr',
            'create',
            '--fill',
            '--web=false',
          ], ProcessResult(0, 0, '', ''));
          stubGhRepoView(ProcessResult(0, 0, settings, ''));
          stubGh([
            'pr',
            'merge',
            '--auto',
            '--merge',
            '--delete-branch',
          ], ProcessResult(0, 0, '', ''));

          final result = await mergeGit.get(
            directory: d,
            ggLog: ggLog,
            automerge: true,
          );
          expect(result, isTrue);
        }
      });

      test('reuses an existing PR instead of creating a duplicate', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        // Existing PR
        stubGh([
          'pr',
          'view',
          '--json',
          'number',
        ], ProcessResult(0, 0, '{"number":7}', ''));
        stubGhRepoView(ProcessResult(0, 0, mergeSettings, ''));
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--merge',
          '--delete-branch',
        ], ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
        expect(
          messages.any((m) => m.contains('Reusing existing pull request')),
          isTrue,
        );
      });

      test('does not merge when automerge is false', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubGh(['pr', 'view', '--json', 'number'], ProcessResult(1, 1, '', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: false,
        );
        expect(result, isTrue);
        verifyNever(
          () => processWrapper.run(
            'gh',
            any(that: contains('merge')),
            runInShell: true,
            workingDirectory: d.path,
          ),
        );
      });

      test('throws when gh pr create fails', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubGh(['pr', 'view', '--json', 'number'], ProcessResult(1, 1, '', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(1, 1, '', 'no-pr'));
        expect(
          () => mergeGit.get(directory: d, ggLog: ggLog, automerge: false),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('gh pr create failed'),
            ),
          ),
        );
      });

      test('warns instead of throwing when gh pr merge fails', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubGh(['pr', 'view', '--json', 'number'], ProcessResult(1, 1, '', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, '', ''));
        stubGhRepoView(ProcessResult(0, 0, mergeSettings, ''));
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--merge',
          '--delete-branch',
        ], ProcessResult(3, 3, '', 'auto-merge disabled'));

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
        expect(
          messages.any(
            (m) =>
                m.contains('Could not enable auto-merge') &&
                m.contains('auto-merge disabled'),
          ),
          isTrue,
        );
      });
    });

    // .........................................................................
    // Azure DevOps

    group('Azure DevOps', () {
      test('creates a PR and sets auto-complete when none exists', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '[]', ''));
        stubAz('create', ProcessResult(0, 0, '{"pullRequestId":99}', ''));
        stubAz('update', ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
        expect(
          messages.any((m) => m.contains('Created pull request !99')),
          isTrue,
        );
        verify(
          () => processWrapper.run(
            'az',
            azUpdateArgs(id: '99'),
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).called(1);
      });

      test('omits --delete-source-branch when disabled', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '[]', ''));
        stubAz('create', ProcessResult(0, 0, '{"pullRequestId":99}', ''));
        stubAz('update', ProcessResult(0, 0, '', ''));

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
          deleteSourceBranch: false,
        );
        expect(result, isTrue);
        verify(
          () => processWrapper.run(
            'az',
            azUpdateArgs(id: '99', deleteSourceBranch: false),
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).called(1);
      });

      test('creates a plain PR when automerge is false', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '', ''));
        stubAz('create', ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: false,
        );
        expect(result, isTrue);
        verifyNever(
          () => processWrapper.run(
            'az',
            any(that: contains('update')),
            runInShell: true,
            workingDirectory: d.path,
          ),
        );
      });

      test('retries auto-complete with squash on a policy rejection', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '[]', ''));
        stubAz('create', ProcessResult(0, 0, '{"pullRequestId":7}', ''));
        stubAzExact(
          azUpdateArgs(id: '7'),
          ProcessResult(
            1,
            1,
            '',
            'ERROR: Merge strategy is not alowed by '
                'policy',
          ),
        );
        stubAzExact(
          azUpdateArgs(id: '7', squash: true),
          ProcessResult(0, 0, '', ''),
        );

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
        expect(messages.any((m) => m.contains('retrying with squash')), isTrue);
      });

      test('warns when no merge strategy is accepted', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '[]', ''));
        stubAz('create', ProcessResult(0, 0, '{"pullRequestId":7}', ''));
        stubAzExact(
          azUpdateArgs(id: '7'),
          ProcessResult(1, 1, '', 'Merge strategy is not alowed by policy'),
        );
        stubAzExact(
          azUpdateArgs(id: '7', squash: true),
          ProcessResult(1, 1, '', 'Merge strategy is not alowed by policy'),
        );

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
        expect(
          messages.any((m) => m.contains('Could not enable auto-complete')),
          isTrue,
        );
      });

      test('warns instead of throwing on a generic update failure', () async {
        stubOriginUrl('https://dev.azure.com/xyz');
        stubCurrentBranch('feature');
        stubAz(
          'list',
          ProcessResult(0, 0, '[{"pullRequestId":42,"status":"active"}]', ''),
        );
        stubAz('update', ProcessResult(2, 2, '', 'update-fail'));

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
        expect(
          messages.any(
            (m) =>
                m.contains('Could not enable auto-complete') &&
                m.contains('update-fail'),
          ),
          isTrue,
        );
      });

      test('warns when the created PR id cannot be determined', () async {
        for (final stdout in ['', 'not-json', '{"other":1}']) {
          messages.clear();
          stubOriginUrl('https://dev.azure.com/you/project');
          stubCurrentBranch('feature');
          stubAz('list', ProcessResult(0, 0, '[]', ''));
          stubAz('create', ProcessResult(0, 0, stdout, ''));

          final result = await mergeGit.get(
            directory: d,
            ggLog: ggLog,
            automerge: true,
          );
          expect(result, isTrue);
          expect(
            messages.any(
              (m) => m.contains('Could not determine the pull request id'),
            ),
            isTrue,
          );
          verifyNever(
            () => processWrapper.run(
              'az',
              any(that: contains('update')),
              runInShell: true,
              workingDirectory: d.path,
            ),
          );
        }
      });

      test('reuses an existing PR and (re)sets auto-complete', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz(
          'list',
          ProcessResult(0, 0, '[{"pullRequestId":42,"status":"active"}]', ''),
        );
        stubAz('update', ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
        expect(
          messages.any((m) => m.contains('Reusing existing pull request !42')),
          isTrue,
        );
      });

      test('reuses an existing PR without touching auto-complete', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz(
          'list',
          ProcessResult(0, 0, '[{"pullRequestId":42,"status":"active"}]', ''),
        );

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: false,
        );
        expect(result, isTrue);
        verifyNever(
          () => processWrapper.run(
            'az',
            any(that: contains('update')),
            runInShell: true,
            workingDirectory: d.path,
          ),
        );
      });

      test('creates a PR when the list lookup fails', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(1, 1, '', 'list-fail'));
        stubAz('create', ProcessResult(0, 0, '{"pullRequestId":1}', ''));
        stubAz('update', ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
      });

      test('creates a PR when list returns a non-list json', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '{}', ''));
        stubAz('create', ProcessResult(0, 0, '{"pullRequestId":1}', ''));
        stubAz('update', ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
      });

      test('creates a PR when list entry has no pullRequestId', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '[{"status":"active"}]', ''));
        stubAz('create', ProcessResult(0, 0, '{"pullRequestId":1}', ''));
        stubAz('update', ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
      });

      test('throws when az repos pr create fails', () async {
        stubOriginUrl('https://dev.azure.com/xyz');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '[]', ''));
        stubAz('create', ProcessResult(2, 2, '', 'fail-az'));
        expect(
          () => mergeGit.get(directory: d, ggLog: ggLog, automerge: true),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('az repos pr create failed'),
            ),
          ),
        );
      });

      test('throws when the current branch cannot be determined', () async {
        stubOriginUrl('https://dev.azure.com/xyz');
        when(
          () => processWrapper.run(
            'git',
            ['rev-parse', '--abbrev-ref', 'HEAD'],
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 1, '', 'no-branch'));
        expect(
          () => mergeGit.get(directory: d, ggLog: ggLog, automerge: true),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('git rev-parse failed'),
            ),
          ),
        );
      });
    });

    // .........................................................................
    // Generic

    test('throws UnimplementedError for unsupported provider', () async {
      stubOriginUrl('https://gitlab.com/xyz');
      expect(
        () => mergeGit.get(directory: d, ggLog: ggLog),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('throws when git config fails', () async {
      when(
        () => processWrapper.run(
          'git',
          ['config', '--get', 'remote.origin.url'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'fatal'));
      expect(
        () => mergeGit.get(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('git config failed'),
          ),
        ),
      );
    });
  });
}
