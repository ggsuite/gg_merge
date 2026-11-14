// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:io';

import 'package:gg_git/gg_git.dart' show GitRetry;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_merge/src/commands/merge_git.dart';
import 'package:gg_merge/src/util/request_limit.dart';

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

    void stubAz(String subCommand, ProcessResult result) {
      when(
        () => processWrapper.run(
          'az',
          any(that: contains(subCommand)),
          runInShell: true,
          workingDirectory: d.path,
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => result);
    }

    /// Stubs an az call with exact [args].
    void stubAzExact(List<String> args, ProcessResult result) {
      when(
        () => processWrapper.run(
          'az',
          args,
          runInShell: true,
          workingDirectory: d.path,
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => result);
    }

    List<String> azUpdateArgs({
      required String id,
      bool deleteSourceBranch = true,
      String? message,
    }) => [
      'repos',
      'pr',
      'update',
      '--id',
      id,
      '--auto-complete',
      'true',
      '--squash',
      'true',
      if (deleteSourceBranch) ...['--delete-source-branch', 'true'],
      if (message != null) ...['--merge-commit-message', message],
    ];

    // .........................................................................
    // GitHub

    group('GitHub', () {
      test('creates a PR and sets squash automerge with branch '
          'delete', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        // No existing PR
        stubGh([
          'pr',
          'list',
          '--head',
          'feature',
          '--state',
          'open',
          '--json',
          'url',
          '--limit',
          '1',
        ], ProcessResult(0, 0, '[]', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, 'https://github.com/me/repo/pull/7', ''));
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--squash',
          '--delete-branch',
        ], ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
        // The url is printed blue, so match the parts around the color code.
        expect(
          messages.any(
            (m) =>
                m.contains('Created pull request:') &&
                m.contains('https://github.com/me/repo/pull/7'),
          ),
          isTrue,
        );
      });

      test('omits --delete-branch when deleteSourceBranch is false', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubGh([
          'pr',
          'list',
          '--head',
          'feature',
          '--state',
          'open',
          '--json',
          'url',
          '--limit',
          '1',
        ], ProcessResult(0, 0, '[]', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, '', ''));
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--squash',
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
            ['pr', 'merge', '--auto', '--squash'],
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).called(1);
      });

      test('uses the message as PR title, body and squash subject', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubGh([
          'pr',
          'list',
          '--head',
          'feature',
          '--state',
          'open',
          '--json',
          'url',
          '--limit',
          '1',
        ], ProcessResult(0, 0, '[]', ''));
        stubGh([
          'pr',
          'create',
          '--title',
          'Release 1.2.3',
          '--body',
          'Release 1.2.3',
          '--web=false',
        ], ProcessResult(0, 0, 'https://github.com/me/repo/pull/8', ''));
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--squash',
          '--subject',
          'Release 1.2.3',
          '--delete-branch',
        ], ProcessResult(0, 0, '', ''));

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
          message: 'Release 1.2.3',
        );
        expect(result, isTrue);
        verify(
          () => processWrapper.run(
            'gh',
            [
              'pr',
              'create',
              '--title',
              'Release 1.2.3',
              '--body',
              'Release 1.2.3',
              '--web=false',
            ],
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).called(1);
        verify(
          () => processWrapper.run(
            'gh',
            [
              'pr',
              'merge',
              '--auto',
              '--squash',
              '--subject',
              'Release 1.2.3',
              '--delete-branch',
            ],
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).called(1);
      });

      test('uses the body as PR description when one is given', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubGh([
          'pr',
          'list',
          '--head',
          'feature',
          '--state',
          'open',
          '--json',
          'url',
          '--limit',
          '1',
        ], ProcessResult(0, 0, '[]', ''));
        stubGh([
          'pr',
          'create',
          '--title',
          'Release 1.2.3',
          '--body',
          '- Add tracking\n- Fix typo',
          '--web=false',
        ], ProcessResult(0, 0, 'https://github.com/me/repo/pull/8', ''));

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          message: 'Release 1.2.3',
          body: '- Add tracking\n- Fix typo',
        );
        expect(result, isTrue);
        verify(
          () => processWrapper.run(
            'gh',
            [
              'pr',
              'create',
              '--title',
              'Release 1.2.3',
              '--body',
              '- Add tracking\n- Fix typo',
              '--web=false',
            ],
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).called(1);
      });

      test('reuses an existing PR instead of creating a duplicate', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        // Existing OPEN PR
        stubGh(
          [
            'pr',
            'list',
            '--head',
            'feature',
            '--state',
            'open',
            '--json',
            'url',
            '--limit',
            '1',
          ],
          ProcessResult(
            0,
            0,
            '[{"url":"https://github.com/me/repo/pull/7"}]',
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
        expect(
          messages.any((m) => m.contains('https://github.com/me/repo/pull/7')),
          isTrue,
        );
      });

      test('creates a new PR when gh pr list output is malformed', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubGh([
          'pr',
          'list',
          '--head',
          'feature',
          '--state',
          'open',
          '--json',
          'url',
          '--limit',
          '1',
        ], ProcessResult(0, 0, 'not json', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, 'https://github.com/me/repo/pull/8\n', ''));
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--squash',
          '--delete-branch',
        ], ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
        expect(
          messages.any((m) => m.contains('https://github.com/me/repo/pull/8')),
          isTrue,
        );
      });

      test('does not merge when automerge is false', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubGh([
          'pr',
          'list',
          '--head',
          'feature',
          '--state',
          'open',
          '--json',
          'url',
          '--limit',
          '1',
        ], ProcessResult(0, 0, '[]', ''));
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
        stubCurrentBranch('feature');
        stubGh([
          'pr',
          'list',
          '--head',
          'feature',
          '--state',
          'open',
          '--json',
          'url',
          '--limit',
          '1',
        ], ProcessResult(0, 0, '[]', ''));
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
        stubCurrentBranch('feature');
        stubGh([
          'pr',
          'list',
          '--head',
          'feature',
          '--state',
          'open',
          '--json',
          'url',
          '--limit',
          '1',
        ], ProcessResult(0, 0, '[]', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, '', ''));
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--squash',
          '--delete-branch',
        ], ProcessResult(3, 3, '', 'auto-merge disabled\nmore details'));
        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
        // Not an error, but the user has to know that the merge is theirs.
        expect(
          messages,
          contains(
            contains(
              'Auto-merge is not available: auto-merge disabled\n'
              'Merge the pull request manually once its checks pass.',
            ),
          ),
        );
        expect(messages.any((m) => m.contains('more details')), isFalse);
      });

      test('never merges the pull request itself when auto-merge '
          'is rejected', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubGh([
          'pr',
          'list',
          '--head',
          'feature',
          '--state',
          'open',
          '--json',
          'url',
          '--limit',
          '1',
        ], ProcessResult(0, 0, '[]', ''));
        stubGh([
          'pr',
          'create',
          '--fill',
          '--web=false',
        ], ProcessResult(0, 0, '', ''));
        stubGh([
          'pr',
          'merge',
          '--auto',
          '--squash',
          '--delete-branch',
        ], ProcessResult(1, 1, '', 'Auto merge is not allowed'));

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);

        // Merging stays a human decision: no plain »gh pr merge« is run.
        verifyNever(
          () => processWrapper.run(
            'gh',
            any(
              that: predicate<List<String>>(
                (args) =>
                    args.length > 1 &&
                    args[0] == 'pr' &&
                    args[1] == 'merge' &&
                    !args.contains('--auto'),
              ),
            ),
            runInShell: any(named: 'runInShell'),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        );
        expect(messages, hasLength(1));
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
            environment: any(named: 'environment'),
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
            environment: any(named: 'environment'),
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
            environment: any(named: 'environment'),
          ),
        );
      });

      test(
        'does not fail when the policy rejects the squash strategy',
        () async {
          stubOriginUrl('https://dev.azure.com/you/project');
          stubCurrentBranch('feature');
          stubAz('list', ProcessResult(0, 0, '[]', ''));
          stubAz('create', ProcessResult(0, 0, '{"pullRequestId":7}', ''));
          stubAzExact(
            azUpdateArgs(id: '7'),
            ProcessResult(1, 1, '', 'Merge strategy is not alowed by policy'),
          );

          final result = await mergeGit.get(
            directory: d,
            ggLog: ggLog,
            automerge: true,
          );
          expect(result, isTrue);
          expect(messages.any((m) => m.contains('auto-complete')), isFalse);
        },
      );

      test('passes the message as PR title and merge commit message', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '[]', ''));
        stubAzExact([
          'repos',
          'pr',
          'create',
          '--source-branch',
          'refs/heads/feature',
          '--title',
          'Release 1.2.3',
        ], ProcessResult(0, 0, '{"pullRequestId":11}', ''));
        stubAzExact(
          azUpdateArgs(id: '11', message: 'Release 1.2.3'),
          ProcessResult(0, 0, '', ''),
        );

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
          message: 'Release 1.2.3',
        );
        expect(result, isTrue);
        verify(
          () => processWrapper.run(
            'az',
            [
              'repos',
              'pr',
              'create',
              '--source-branch',
              'refs/heads/feature',
              '--title',
              'Release 1.2.3',
            ],
            runInShell: true,
            workingDirectory: d.path,
            environment: any(named: 'environment'),
          ),
        ).called(1);
        verify(
          () => processWrapper.run(
            'az',
            azUpdateArgs(id: '11', message: 'Release 1.2.3'),
            runInShell: true,
            workingDirectory: d.path,
            environment: any(named: 'environment'),
          ),
        ).called(1);
      });

      test('passes the body as PR description', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '[]', ''));
        stubAzExact([
          'repos',
          'pr',
          'create',
          '--source-branch',
          'refs/heads/feature',
          '--title',
          'Release 1.2.3',
          '--description',
          '- Add tracking',
        ], ProcessResult(0, 0, '{"pullRequestId":11}', ''));

        final result = await mergeGit.get(
          directory: d,
          ggLog: ggLog,
          message: 'Release 1.2.3',
          body: '- Add tracking',
        );
        expect(result, isTrue);
        verify(
          () => processWrapper.run(
            'az',
            [
              'repos',
              'pr',
              'create',
              '--source-branch',
              'refs/heads/feature',
              '--title',
              'Release 1.2.3',
              '--description',
              '- Add tracking',
            ],
            runInShell: true,
            workingDirectory: d.path,
            environment: any(named: 'environment'),
          ),
        ).called(1);
      });

      test('does not throw on a generic update failure', () async {
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
        expect(messages.any((m) => m.contains('update-fail')), isFalse);
      });

      test(
        'skips auto-complete when the created PR id cannot be determined',
        () async {
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
            expect(messages.any((m) => m.contains('pull request id')), isFalse);
            verifyNever(
              () => processWrapper.run(
                'az',
                any(that: contains('update')),
                runInShell: true,
                workingDirectory: d.path,
                environment: any(named: 'environment'),
              ),
            );
          }
        },
      );

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
            environment: any(named: 'environment'),
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

      test('creates a PR when list returns malformed json', () async {
        // A zero exit code with unparsable stdout — some az CLI versions
        // print a banner on stdout instead of the requested json — must not
        // crash the lookup; it falls through to create the PR like an empty
        // or failing list.
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, 'not-json', ''));
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

    // .........................................................................
    // A provider counts the requests that create something per client and
    // turns a client away for a while when it sends too many. Waiting is
    // all that helps then — the request is right.
    group('when the provider limits the requests', () {
      const limited =
          'HTTP 403: You have exceeded a secondary rate limit. Please wait a '
          'few minutes before you try again.';

      late MergeGit patient;

      setUp(() {
        // Retries like the default, without the minutes of waiting.
        patient = MergeGit(
          ggLog: ggLog,
          processWrapper: processWrapper,
          gitRetry: GitRetry.example,
        );
      });

      /// Makes `gh pr create` answer with [results], one per call, the last
      /// one for every further call. Returns the number of calls so far.
      int Function() stubGhCreate(List<ProcessResult> results) {
        var calls = 0;
        when(
          () => processWrapper.run(
            'gh',
            ['pr', 'create', '--fill', '--web=false'],
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).thenAnswer(
          (_) async =>
              results[calls++ < results.length
                  ? calls - 1
                  : results.length - 1],
        );
        return () => calls;
      }

      void stubNoOpenGitHubPr() {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubGh([
          'pr',
          'list',
          '--head',
          'feature',
          '--state',
          'open',
          '--json',
          'url',
          '--limit',
          '1',
        ], ProcessResult(0, 0, '[]', ''));
      }

      test('asks GitHub again and creates the pull request', () async {
        stubNoOpenGitHubPr();
        final calls = stubGhCreate([
          ProcessResult(1, 1, '', limited),
          ProcessResult(0, 0, 'https://github.com/me/repo/pull/7', ''),
        ]);

        final result = await patient.get(
          directory: d,
          ggLog: ggLog,
          automerge: false,
        );

        expect(result, isTrue);
        expect(calls(), 2);
        expect(
          messages,
          contains(contains('gh pr create was turned away: the remote limits')),
        );
        expect(
          messages,
          contains(contains('https://github.com/me/repo/pull/7')),
        );
      });

      test('gives up when GitHub keeps turning the request away', () async {
        stubNoOpenGitHubPr();
        final calls = stubGhCreate([ProcessResult(1, 1, '', limited)]);

        await expectLater(
          patient.get(directory: d, ggLog: ggLog, automerge: false),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              allOf(
                contains('gh pr create failed'),
                contains('secondary rate limit'),
              ),
            ),
          ),
        );

        expect(calls(), GitRetry.example.attempts);
      });

      test('asks GitHub again to merge the pull request on its own', () async {
        stubNoOpenGitHubPr();
        stubGhCreate([
          ProcessResult(0, 0, 'https://github.com/me/repo/pull/7', ''),
        ]);
        var merges = 0;
        when(
          () => processWrapper.run(
            'gh',
            any(that: contains('merge')),
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).thenAnswer(
          (_) async => merges++ == 0
              ? ProcessResult(1, 1, '', limited)
              : ProcessResult(0, 0, '', ''),
        );

        await patient.get(directory: d, ggLog: ggLog, automerge: true);

        expect(merges, 2);
        // The second answer was fine: nobody is told to merge by hand.
        expect(messages, isNot(contains(contains('Auto-merge is not'))));
      });

      test('asks Azure DevOps again and creates the pull request', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '[]', ''));
        var creates = 0;
        when(
          () => processWrapper.run(
            'az',
            any(that: contains('create')),
            runInShell: true,
            workingDirectory: d.path,
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async => creates++ == 0
              ? ProcessResult(1, 1, '', 'HTTP 429: Too Many Requests')
              : ProcessResult(0, 0, '{"pullRequestId":99}', ''),
        );

        final result = await patient.get(
          directory: d,
          ggLog: ggLog,
          automerge: false,
        );

        expect(result, isTrue);
        expect(creates, 2);
        expect(
          messages,
          contains(contains('az repos pr create was turned away')),
        );
      });

      group('and gg counts the new pull requests itself', () {
        const minute = Duration(minutes: 1);
        late DateTime now;
        late List<Duration> waits;
        late MergeGit counting;

        setUp(() {
          now = DateTime(2026, 11, 14, 12);
          waits = [];

          // One new pull request a minute, on a clock only waiting moves.
          counting = MergeGit(
            ggLog: ggLog,
            processWrapper: processWrapper,
            gitRetry: GitRetry.example,
            pullRequestLimit: RequestLimit(
              limits: const [(within: minute, requests: 1)],
              now: () => now,
              wait: (duration) async {
                waits.add(duration);
                now = now.add(duration);
              },
            ),
          );
        });

        test('creates a pull request on GitHub right away while the limit '
            'allows it', () async {
          stubNoOpenGitHubPr();
          final calls = stubGhCreate([ProcessResult(0, 0, 'url', '')]);

          await counting.get(directory: d, ggLog: ggLog, automerge: false);

          expect(calls(), 1);
          expect(waits, isEmpty);
        });

        test('waits before the next pull request on GitHub', () async {
          stubNoOpenGitHubPr();
          final calls = stubGhCreate([ProcessResult(0, 0, 'url', '')]);

          await counting.get(directory: d, ggLog: ggLog, automerge: false);
          await counting.get(directory: d, ggLog: ggLog, automerge: false);

          expect(calls(), 2);
          expect(waits, [minute]);
          expect(
            messages,
            contains(contains('1 new pull requests started within a minute')),
          );
        });

        test('counts every attempt to create a pull request', () async {
          stubNoOpenGitHubPr();
          final calls = stubGhCreate([
            ProcessResult(1, 1, '', limited),
            ProcessResult(0, 0, 'url', ''),
          ]);

          await counting.get(directory: d, ggLog: ggLog, automerge: false);

          // The attempt GitHub turned away was a request as well.
          expect(calls(), 2);
          expect(waits, [minute]);
        });

        test('does not count a pull request that is there already', () async {
          stubOriginUrl('https://github.com/me/repo.git');
          stubCurrentBranch('feature');
          stubGh([
            'pr',
            'list',
            '--head',
            'feature',
            '--state',
            'open',
            '--json',
            'url',
            '--limit',
            '1',
          ], ProcessResult(0, 0, '[{"url":"https://x/pull/1"}]', ''));

          await counting.get(directory: d, ggLog: ggLog, automerge: false);
          await counting.get(directory: d, ggLog: ggLog, automerge: false);

          expect(waits, isEmpty);
        });

        test('waits before the next pull request on Azure DevOps', () async {
          stubOriginUrl('https://dev.azure.com/you/project');
          stubCurrentBranch('feature');
          stubAz('list', ProcessResult(0, 0, '[]', ''));
          stubAz('create', ProcessResult(0, 0, '{"pullRequestId":99}', ''));

          await counting.get(directory: d, ggLog: ggLog, automerge: false);
          await counting.get(directory: d, ggLog: ggLog, automerge: false);

          expect(waits, [minute]);
        });
      });
    });

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
