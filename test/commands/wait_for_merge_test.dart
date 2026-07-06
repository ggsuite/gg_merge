// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:io';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_merge/src/commands/wait_for_merge.dart';
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

    /// Returns the given results in sequence, repeating the last one.
    void stubSequence(String tool, String subCommand, List<ProcessResult> r) {
      var i = 0;
      when(
        () => processWrapper.run(
          tool,
          any(that: contains(subCommand)),
          runInShell: true,
          workingDirectory: d.path,
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
          messages.any((m) => m.contains('Waiting for pull request')),
          isTrue,
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
          messages.any((m) => m.contains('Waiting for pull request')),
          isTrue,
        );
      });

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
