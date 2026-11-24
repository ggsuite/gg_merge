// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_merge/src/commands/wait_for_merge.dart';
import 'package:gg_status_printer/gg_status_printer.dart';

import '../helpers.dart';

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('WaitForMerge', () {
    late Directory d;
    late WaitForMerge waitForMerge;
    late MockGgProcessWrapper processWrapper;
    final messages = <String>[];
    final ggLog = messages.add;

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggwait_test_');
      processWrapper = MockGgProcessWrapper();
      // No-op delay so the poll loop does not actually wait.
      waitForMerge = WaitForMerge(
        ggLog: ggLog,
        processWrapper: processWrapper,
        delay: (_) async {},
      );
      messages.clear();
    });
    tearDown(() async => d.delete(recursive: true));

    // .........................................................................
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

    /// Answers the policy lookup of an Azure DevOps pull request with
    /// [policies] — no policy unless a test says otherwise.
    void stubPolicies(String policies, {int exitCode = 0}) {
      when(
        () => processWrapper.run(
          'az',
          any(that: contains('policy')),
          runInShell: true,
          workingDirectory: d.path,
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, exitCode, policies, ''));
    }

    /// Returns the given results in sequence, repeating the last one. The
    /// policy lookup is answered by [stubPolicies] instead.
    void stubSequence(String tool, String subCommand, List<ProcessResult> r) {
      stubPolicies('[]');
      var i = 0;
      when(
        () => processWrapper.run(
          tool,
          any(that: allOf(contains(subCommand), isNot(contains('policy')))),
          runInShell: true,
          workingDirectory: d.path,
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async {
        final result = r[i < r.length ? i : r.length - 1];
        i++;
        return result;
      });
    }

    // .........................................................................
    group('Azure DevOps', () {
      test('returns when the PR is completed (via exec)', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubSequence('az', 'list', [
          ProcessResult(0, 0, '[{"pullRequestId":1,"status":"completed"}]', ''),
        ]);
        final result = await waitForMerge.exec(directory: d, ggLog: ggLog);
        expect(result, isTrue);
        expect(messages.any((m) => m.contains('merged')), isTrue);
      });

      test('logs the PR web page assembled from the repository az '
          'reports — it carries no web url', () async {
        // One pull request as `az repos pr list` prints it on current `az`
        // versions: the rest api url plus project and repository names, no
        // `webUrl`, `remoteUrl` null.
        String azurePr(String status) =>
            '[{"pullRequestId":138,"status":"$status","repository":{'
            '"name":"r","project":{"name":"p"},"remoteUrl":null,'
            '"url":"https://dev.azure.com/o/902c4d10'
            '/_apis/git/repositories/e8321401"}}]';
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('138');
        stubSequence('az', 'list', [
          ProcessResult(0, 0, azurePr('active'), ''),
          ProcessResult(0, 0, azurePr('completed'), ''),
        ]);
        final result = await waitForMerge.get(
          directory: d,
          ggLog: ggLog,
          autoMerge: true,
        );
        expect(result, isTrue);
        expect(
          messages.any(
            (m) =>
                m.contains('https://dev.azure.com/o/p/_git/r/pullrequest/138'),
          ),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('the pull request of 138')),
          isFalse,
        );
        expect(
          messages.any((m) => m.contains('no usable repository metadata')),
          isFalse,
        );
      });

      test('warns when repository metadata cannot provide a PR url', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('138');
        stubSequence('az', 'list', [
          ProcessResult(0, 0, '[{"pullRequestId":138,"status":"active"}]', ''),
          ProcessResult(
            0,
            0,
            '[{"pullRequestId":138,"status":"completed"}]',
            '',
          ),
        ]);
        final result = await waitForMerge.get(
          directory: d,
          ggLog: ggLog,
          autoMerge: true,
        );
        expect(result, isTrue);
        expect(
          messages.any((m) => m.contains('the pull request of 138')),
          isTrue,
        );
        expect(
          messages.where(
            (m) =>
                m.contains('Warning:') &&
                m.contains('Azure DevOps pull request URL') &&
                m.contains('no usable repository metadata'),
          ),
          hasLength(1),
        );
      });

      test('logs the PR web page built from repository.remoteUrl', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubSequence('az', 'list', [
          ProcessResult(
            0,
            0,
            '[{"pullRequestId":42,"status":"active",'
                '"repository":{"remoteUrl":"https://o@dev.azure.com/o/p/_git/r"}}]',
            '',
          ),
          ProcessResult(
            0,
            0,
            '[{"pullRequestId":42,"status":"completed",'
                '"repository":{"remoteUrl":"https://o@dev.azure.com/o/p/_git/r"}}]',
            '',
          ),
        ]);
        final result = await waitForMerge.get(directory: d, ggLog: ggLog);
        expect(result, isTrue);
        expect(
          messages.any(
            (m) =>
                m.contains('https://dev.azure.com/o/p/_git/r/pullrequest/42'),
          ),
          isTrue,
        );
      });

      test('polls until the PR is completed', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubSequence('az', 'list', [
          ProcessResult(0, 0, '[{"pullRequestId":1,"status":"active"}]', ''),
          ProcessResult(0, 0, '[{"pullRequestId":1,"status":"completed"}]', ''),
        ]);
        final result = await waitForMerge.get(directory: d, ggLog: ggLog);
        expect(result, isTrue);
        expect(
          messages.any(
            (m) =>
                m.contains('Please open and merge') &&
                m.contains('the pull request of feature'),
          ),
          isTrue,
        );
      });

      test('asks to merge only once, no matter how long it polls', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubSequence('az', 'list', [
          ProcessResult(0, 0, '[{"pullRequestId":1,"status":"active"}]', ''),
          ProcessResult(0, 0, '[{"pullRequestId":1,"status":"active"}]', ''),
          ProcessResult(0, 0, '[{"pullRequestId":1,"status":"active"}]', ''),
          ProcessResult(0, 0, '[{"pullRequestId":1,"status":"completed"}]', ''),
        ]);
        final result = await waitForMerge.get(directory: d, ggLog: ggLog);
        expect(result, isTrue);
        expect(
          messages.where((m) => m.contains('Please open and merge')),
          hasLength(1),
        );
      });

      test('picks the newest PR by id', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubSequence('az', 'list', [
          ProcessResult(
            0,
            0,
            '[{"pullRequestId":1,"status":"abandoned"},'
                '{"status":"active"},'
                '{"pullRequestId":2,"status":"completed"}]',
            '',
          ),
        ]);
        final result = await waitForMerge.get(directory: d, ggLog: ggLog);
        expect(result, isTrue);
      });

      test('throws when the PR was abandoned', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubSequence('az', 'list', [
          ProcessResult(0, 0, '[{"pullRequestId":1,"status":"abandoned"}]', ''),
        ]);
        expect(
          () => waitForMerge.get(directory: d, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('was abandoned'),
            ),
          ),
        );
      });

      test('throws when no PR is found (empty output)', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubSequence('az', 'list', [ProcessResult(0, 0, '', '')]);
        expect(
          () => waitForMerge.get(directory: d, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('No pull request found'),
            ),
          ),
        );
      });

      test('throws when no PR is found (non-list json)', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubSequence('az', 'list', [ProcessResult(0, 0, '{}', '')]);
        expect(
          () => waitForMerge.get(directory: d, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('No pull request found'),
            ),
          ),
        );
      });

      test('throws when az repos pr list fails', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubSequence('az', 'list', [ProcessResult(1, 1, '', 'list-fail')]);
        expect(
          () => waitForMerge.get(directory: d, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('az repos pr list failed'),
            ),
          ),
        );
      });

      test('polls on through a transient network error', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubSequence('az', 'list', [
          ProcessResult(
            0,
            1,
            '',
            'Failed to establish a new connection: '
                '[Errno -2] Name or service not known',
          ),
          ProcessResult(0, 0, '[{"pullRequestId":1,"status":"completed"}]', ''),
        ]);

        expect(await waitForMerge.get(directory: d, ggLog: ggLog), isTrue);
        expect(
          messages.any(
            (m) => m.contains('az repos pr list failed with a transient'),
          ),
          isTrue,
        );
      });
    });

    // .........................................................................
    group('GitHub', () {
      test('returns when the PR is merged', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubSequence('gh', 'list', [
          ProcessResult(0, 0, '[{"state":"MERGED"}]', ''),
        ]);
        final result = await waitForMerge.get(directory: d, ggLog: ggLog);
        expect(result, isTrue);
      });

      test('polls until the PR is merged', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubSequence('gh', 'list', [
          ProcessResult(0, 0, '[{"state":"OPEN"}]', ''),
          ProcessResult(0, 0, '[{"state":"MERGED"}]', ''),
        ]);
        final result = await waitForMerge.get(directory: d, ggLog: ggLog);
        expect(result, isTrue);
        expect(
          messages.any(
            (m) =>
                m.contains('Please open and merge') &&
                m.contains('the pull request of feature'),
          ),
          isTrue,
        );
      });

      test('asks to merge only once, no matter how long it polls', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubSequence('gh', 'list', [
          ProcessResult(0, 0, '[{"state":"OPEN"}]', ''),
          ProcessResult(0, 0, '[{"state":"OPEN"}]', ''),
          ProcessResult(0, 0, '[{"state":"OPEN"}]', ''),
          ProcessResult(0, 0, '[{"state":"MERGED"}]', ''),
        ]);
        final result = await waitForMerge.get(directory: d, ggLog: ggLog);
        expect(result, isTrue);
        expect(
          messages.where((m) => m.contains('Please open and merge')),
          hasLength(1),
        );
      });

      test('uses the given branch instead of HEAD', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        // HEAD already moved on to main — the explicit branch must win, so
        // the lookup does not search for a pull request of »main«.
        stubCurrentBranch('main');
        stubSequence('gh', 'list', [
          ProcessResult(0, 0, '[{"state":"MERGED"}]', ''),
        ]);

        final result = await waitForMerge.get(
          directory: d,
          ggLog: ggLog,
          branch: 'feature',
        );
        expect(result, isTrue);
        verify(
          () => processWrapper.run(
            'gh',
            any(that: contains('feature')),
            runInShell: any(named: 'runInShell'),
            workingDirectory: d.path,
            environment: any(named: 'environment'),
          ),
        ).called(1);
      });

      test('logs the PR url once, so the status can be monitored', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        const pr = '"url":"https://github.com/me/repo/pull/9"';
        stubSequence('gh', 'list', [
          ProcessResult(0, 0, '[{"state":"OPEN", $pr}]', ''),
          ProcessResult(0, 0, '[{"state":"OPEN", $pr}]', ''),
          ProcessResult(0, 0, '[{"state":"MERGED", $pr}]', ''),
        ]);
        final result = await waitForMerge.get(directory: d, ggLog: ggLog);
        expect(result, isTrue);

        // The url is logged exactly once — not repeated on every poll.
        final urlLines = messages
            .where((m) => m.contains('https://github.com/me/repo/pull/9'))
            .toList();
        expect(urlLines, hasLength(1));
        expect(urlLines.first, contains('Please open and merge'));
      });

      test('an auto-merge PR is only named, never asked for', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        const pr = '"url":"https://github.com/me/repo/pull/9"';
        stubSequence('gh', 'list', [
          ProcessResult(0, 0, '[{"state":"OPEN", $pr}]', ''),
          ProcessResult(0, 0, '[{"state":"MERGED", $pr}]', ''),
        ]);
        final result = await waitForMerge.get(
          directory: d,
          ggLog: ggLog,
          autoMerge: true,
        );
        expect(result, isTrue);

        final urlLines = messages
            .where((m) => m.contains('https://github.com/me/repo/pull/9'))
            .toList();
        expect(urlLines, hasLength(1));
        expect(
          rmControls(urlLines.first),
          'Pull request: https://github.com/me/repo/pull/9',
        );
        expect(
          messages.any((m) => m.contains('Please open and merge')),
          isFalse,
        );
      });

      // GitHub shows a pull request its auto-merge just completed as
      // `CLOSED` for a moment before it turns `MERGED`. That moment must not
      // abort the release.
      test(
        'keeps polling through a transient CLOSED and returns on MERGED',
        () async {
          stubOriginUrl('https://github.com/me/repo.git');
          stubCurrentBranch('feature');
          stubSequence('gh', 'list', [
            ProcessResult(0, 0, '[{"state":"OPEN"}]', ''),
            ProcessResult(0, 0, '[{"state":"CLOSED","mergedAt":null}]', ''),
            ProcessResult(0, 0, '[{"state":"MERGED"}]', ''),
          ]);
          final result = await waitForMerge.get(directory: d, ggLog: ggLog);
          expect(result, isTrue);
          expect(messages.any((m) => m.contains('merged')), isTrue);
        },
      );

      test(
        'treats a CLOSED pull request with a merge date as merged',
        () async {
          stubOriginUrl('https://github.com/me/repo.git');
          stubCurrentBranch('feature');
          stubSequence('gh', 'list', [
            ProcessResult(
              0,
              0,
              '[{"state":"CLOSED","mergedAt":"2026-09-11T00:05:00Z"}]',
              '',
            ),
          ]);
          final result = await waitForMerge.get(directory: d, ggLog: ggLog);
          expect(result, isTrue);
          expect(messages.any((m) => m.contains('merged')), isTrue);
        },
      );

      test(
        'gives up on a CLOSED pull request only after several polls',
        () async {
          stubOriginUrl('https://github.com/me/repo.git');
          stubCurrentBranch('feature');
          var polls = 0;
          when(
            () => processWrapper.run(
              'gh',
              any(that: contains('list')),
              runInShell: true,
              workingDirectory: d.path,
              environment: any(named: 'environment'),
            ),
          ).thenAnswer((_) async {
            polls++;
            return ProcessResult(0, 0, '[{"state":"CLOSED"}]', '');
          });
          await expectLater(
            () => waitForMerge.get(directory: d, ggLog: ggLog),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'msg',
                contains('closed without merging'),
              ),
            ),
          );
          expect(polls, WaitForMerge.closedPollsBeforeGivingUp);
        },
      );

      test('throws when the PR was closed without merging', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubSequence('gh', 'list', [
          ProcessResult(0, 0, '[{"state":"CLOSED"}]', ''),
        ]);
        expect(
          () => waitForMerge.get(directory: d, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('closed without merging'),
            ),
          ),
        );
      });

      test('throws when no PR is found (empty output)', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubSequence('gh', 'list', [ProcessResult(0, 0, '', '')]);
        expect(
          () => waitForMerge.get(directory: d, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('No pull request found'),
            ),
          ),
        );
      });

      test('throws when no PR is found (non-list json)', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubSequence('gh', 'list', [ProcessResult(0, 0, '{}', '')]);
        expect(
          () => waitForMerge.get(directory: d, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('No pull request found'),
            ),
          ),
        );
      });

      test('throws when no PR is found (first entry not a map)', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubSequence('gh', 'list', [ProcessResult(0, 0, '["x"]', '')]);
        expect(
          () => waitForMerge.get(directory: d, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('No pull request found'),
            ),
          ),
        );
      });

      test('throws when gh pr list fails', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubCurrentBranch('feature');
        stubSequence('gh', 'list', [ProcessResult(1, 1, '', 'gh-fail')]);
        expect(
          () => waitForMerge.get(directory: d, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('gh pr list failed'),
            ),
          ),
        );
      });

      group('on a transient network error', () {
        const offline =
            'error connecting to api.github.com\n'
            'check your internet connection or https://githubstatus.com';

        test('polls on and returns once the PR is merged', () async {
          stubOriginUrl('https://github.com/me/repo.git');
          stubCurrentBranch('feature');
          stubSequence('gh', 'list', [
            ProcessResult(0, 0, '[{"state":"OPEN"}]', ''),
            ProcessResult(0, 1, '', offline),
            ProcessResult(0, 1, '', offline),
            ProcessResult(0, 0, '[{"state":"MERGED"}]', ''),
          ]);

          final result = await waitForMerge.get(directory: d, ggLog: ggLog);

          expect(result, isTrue);
          expect(
            messages
                .where((m) => m.contains('transient network error'))
                .map(rmControls),
            [
              'gh pr list failed with a transient network error. '
                  'Polling again in 15s (attempt 2 of 10).',
              'gh pr list failed with a transient network error. '
                  'Polling again in 15s (attempt 3 of 10).',
            ],
          );
        });

        test('gives up after too many failed polls in a row', () async {
          stubOriginUrl('https://github.com/me/repo.git');
          stubCurrentBranch('feature');
          var polls = 0;
          when(
            () => processWrapper.run(
              'gh',
              any(that: contains('list')),
              runInShell: true,
              workingDirectory: d.path,
              environment: any(named: 'environment'),
            ),
          ).thenAnswer((_) async {
            polls++;
            return ProcessResult(0, 1, '', offline);
          });

          await expectLater(
            () => waitForMerge.get(directory: d, ggLog: ggLog),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'msg',
                contains('gh pr list failed: error connecting to'),
              ),
            ),
          );
          expect(polls, WaitForMerge.failedPollsBeforeGivingUp);
        });
      });
    });

    // .........................................................................
    // A pull request nothing holds back merges within seconds, so the first
    // polls follow each other quickly. A fixed interval made every such
    // merge cost a full interval.
    group('pollDelay', () {
      test('grows from two seconds to the poll interval', () {
        expect(
          [
            for (var polls = 0; polls < 6; polls++)
              waitForMerge.pollDelay(polls),
          ],
          const [
            Duration(seconds: 2),
            Duration(seconds: 4),
            Duration(seconds: 8),
            Duration(seconds: 15),
            Duration(seconds: 15),
            Duration(seconds: 15),
          ],
        );
      });

      test('stays at the poll interval however long the wait takes', () {
        expect(waitForMerge.pollDelay(17), const Duration(seconds: 15));
        expect(waitForMerge.pollDelay(100000), const Duration(seconds: 15));
      });

      test('never exceeds a poll interval shorter than two seconds', () {
        final quick = WaitForMerge(
          ggLog: ggLog,
          processWrapper: processWrapper,
          pollInterval: const Duration(seconds: 1),
        );
        expect(quick.pollDelay(0), const Duration(seconds: 1));
        expect(quick.pollDelay(3), const Duration(seconds: 1));
      });

      for (final (provider, url, tool, open, merged) in [
        (
          'GitHub',
          'https://github.com/me/repo.git',
          'gh',
          '[{"state":"OPEN"}]',
          '[{"state":"MERGED"}]',
        ),
        (
          'Azure DevOps',
          'https://dev.azure.com/you/project',
          'az',
          '[{"pullRequestId":1,"status":"active"}]',
          '[{"pullRequestId":1,"status":"completed"}]',
        ),
      ]) {
        test('paces the polls of a $provider pull request', () async {
          final delays = <Duration>[];
          final waiting = WaitForMerge(
            ggLog: ggLog,
            processWrapper: processWrapper,
            delay: (duration) async => delays.add(duration),
          );
          stubOriginUrl(url);
          stubCurrentBranch('feature');
          stubSequence(tool, 'list', [
            for (var i = 0; i < 4; i++) ProcessResult(0, 0, open, ''),
            ProcessResult(0, 0, merged, ''),
          ]);

          expect(await waiting.get(directory: d, ggLog: ggLog), isTrue);
          expect(delays, const [
            Duration(seconds: 2),
            Duration(seconds: 4),
            Duration(seconds: 8),
            Duration(seconds: 15),
          ]);
        });
      }
    });

    // .........................................................................
    group('a pull request that cannot merge', () {
      Future<Object?> waitError() async {
        try {
          await waitForMerge.get(directory: d, ggLog: ggLog);
          return null;
        } catch (e) {
          return e;
        }
      }

      final merged = ProcessResult(0, 0, '[{"state":"MERGED"}]', '');

      group('on GitHub', () {
        ProcessResult open({
          String mergeable = 'MERGEABLE',
          String state = 'BLOCKED',
        }) => ProcessResult(
          0,
          0,
          '[{"state":"OPEN","url":"https://github.com/me/repo/pull/7",'
              '"mergeable":"$mergeable","mergeStateStatus":"$state"}]',
          '',
        );

        late List<List<String>> checkCalls;

        /// Answers `gh pr checks --required` with [checks] and [exitCode].
        void stubRequiredChecks(String checks, {int exitCode = 1}) {
          when(
            () => processWrapper.run(
              'gh',
              any(that: contains('checks')),
              runInShell: true,
              workingDirectory: d.path,
            ),
          ).thenAnswer((invocation) async {
            checkCalls.add(invocation.positionalArguments[1] as List<String>);
            return ProcessResult(0, exitCode, checks, '');
          });
        }

        setUp(() {
          checkCalls = [];
          stubOriginUrl('https://github.com/me/repo.git');
          stubCurrentBranch('feature');
          stubRequiredChecks('[]', exitCode: 0);
        });

        test('fails on a merge conflict, naming the pull request', () async {
          stubSequence('gh', 'list', [open(mergeable: 'CONFLICTING')]);
          final error = '${await waitError()}';
          expect(error, contains('cannot be merged: it has merge conflicts'));
          expect(error, contains('https://github.com/me/repo/pull/7'));
        });

        test('fails when the branch has to be brought up to date', () async {
          stubSequence('gh', 'list', [open(state: 'BEHIND')]);
          expect(
            '${await waitError()}',
            contains('it is behind its base branch'),
          );
        });

        test('fails when a required check failed, naming it', () async {
          stubSequence('gh', 'list', [open()]);
          stubRequiredChecks(
            '[{"name":"test","bucket":"fail"},'
            '{"name":"build","bucket":"pass"},'
            '{"name":"lint","bucket":"fail"}]',
          );
          expect(
            '${await waitError()}',
            contains('a required check failed: test, lint'),
          );
          expect(checkCalls.first, [
            'pr',
            'checks',
            'feature',
            '--required',
            '--json',
            'name,bucket',
          ]);
        });

        test('waits on while required checks run or a review is missing, '
            'and for an optional failed check', () async {
          stubSequence('gh', 'list', [
            open(),
            open(mergeable: 'UNKNOWN', state: 'UNKNOWN'),
            open(state: 'UNSTABLE'),
            merged,
          ]);
          stubRequiredChecks(
            '[{"name":"test","bucket":"pending"},'
            '{"name":"old","bucket":"cancel"}]',
            exitCode: 8,
          );
          expect(await waitError(), isNull);
          // Only a blocked pull request asks for its required checks.
          expect(checkCalls, hasLength(1));
        });

        test('waits on when the checks cannot be read', () async {
          stubSequence('gh', 'list', [open(), open(), open(), merged]);
          stubRequiredChecks('no json');
          expect(await waitError(), isNull);
        });

        test('waits on through a reason left over from the commit before '
            'the push', () async {
          stubSequence('gh', 'list', [
            open(mergeable: 'CONFLICTING'),
            open(mergeable: 'CONFLICTING'),
            open(),
            merged,
          ]);
          expect(await waitError(), isNull);
        });
      });

      group('on Azure DevOps', () {
        const build = '0609b952-1397-4640-95ec-e00a01b2c241';
        const status = 'cbdc66da-9728-4af8-aada-9a5a32e4a226';
        const reviewers = 'fa4e907d-c16b-4a4c-9dfa-4906e5d171dd';

        ProcessResult open(String mergeStatus) => ProcessResult(
          0,
          0,
          '[{"pullRequestId":5,"status":"active",'
              '"mergeStatus":"$mergeStatus"}]',
          '',
        );

        final completed = ProcessResult(
          0,
          0,
          '[{"pullRequestId":5,"status":"completed"}]',
          '',
        );

        String policy(
          String type,
          String status, {
          bool blocking = true,
          String? name,
        }) =>
            '{"status":"$status","configuration":{"isBlocking":$blocking,'
            '"type":{"id":"$type"},'
            '"settings":{${name == null ? '' : '"displayName":"$name"'}}}}';

        setUp(() {
          stubOriginUrl('https://dev.azure.com/you/project');
          stubCurrentBranch('feature');
        });

        for (final (mergeStatus, reason) in [
          ('conflicts', 'it has merge conflicts'),
          ('failure', 'the merge failed'),
          ('rejectedByPolicy', 'a branch policy rejected the merge'),
        ]) {
          test('fails on merge status $mergeStatus', () async {
            stubSequence('az', 'list', [open(mergeStatus)]);
            expect(
              '${await waitError()}',
              contains('cannot be merged: $reason'),
            );
          });
        }

        test('fails when a blocking build or status policy failed', () async {
          stubSequence('az', 'list', [open('succeeded')]);
          stubPolicies(
            '[${policy(build, 'rejected', name: 'CI')},'
            '${policy(status, 'broken')},'
            '${policy(build, 'rejected', blocking: false, name: 'Lint')},'
            '${policy(build, 'running', name: 'Tests')}]',
          );
          expect(
            '${await waitError()}',
            contains('a required policy failed: CI, Status'),
          );
        });

        test('looks the policies up only once the merge succeeds', () async {
          stubSequence('az', 'list', [open('queued'), completed]);
          stubPolicies('[${policy(build, 'rejected')}]');
          expect(await waitError(), isNull);
          verifyNever(
            () => processWrapper.run(
              'az',
              any(that: contains('policy')),
              runInShell: true,
              workingDirectory: d.path,
              environment: any(named: 'environment'),
            ),
          );
        });

        test('waits on for reviewers and running policies', () async {
          stubSequence('az', 'list', [open('succeeded'), completed]);
          stubPolicies(
            '[${policy(reviewers, 'rejected')},'
            '${policy(build, 'running')},'
            '{"status":"rejected","configuration":{"isBlocking":true}},'
            '"not a map"]',
          );
          expect(await waitError(), isNull);
        });

        for (final (name, output, exitCode) in [
          ('fails', '', 1),
          ('prints no json', 'oops', 0),
          ('prints no list', '{}', 0),
        ]) {
          test('waits on when the policy lookup $name', () async {
            stubSequence('az', 'list', [open('succeeded'), completed]);
            stubPolicies(output, exitCode: exitCode);
            expect(await waitError(), isNull);
          });
        }
      });
    });

    // .........................................................................
    group('generic', () {
      test('throws UnimplementedError for unsupported provider', () async {
        stubOriginUrl('https://gitlab.com/xyz');
        stubCurrentBranch('feature');
        expect(
          () => waitForMerge.get(directory: d, ggLog: ggLog),
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
          () => waitForMerge.get(directory: d, ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('git config failed'),
            ),
          ),
        );
      });

      test('throws when the current branch cannot be determined', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        when(
          () => processWrapper.run(
            'git',
            ['rev-parse', '--abbrev-ref', 'HEAD'],
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 1, '', 'no-branch'));
        expect(
          () => waitForMerge.get(directory: d, ggLog: ggLog),
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
  });
}
