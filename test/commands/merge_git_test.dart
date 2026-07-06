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

    // .........................................................................
    // GitHub

    group('GitHub', () {
      test('creates a PR and sets automerge with branch delete', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        // No existing PR
        stubGh(['pr', 'view', '--json', 'number'], ProcessResult(1, 1, '', ''));
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
          '--delete-branch',
        ], ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
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
        stubGh([
          'pr',
          'merge',
          '--auto',
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
            ['pr', 'merge', '--auto', '--delete-branch'],
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

      test('throws when gh pr merge fails', () async {
        stubOriginUrl('https://github.com/me/repo.git');
        stubGh(['pr', 'view', '--json', 'number'], ProcessResult(1, 1, '', ''));
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
          '--delete-branch',
        ], ProcessResult(3, 3, '', 'mergeError'));
        expect(
          () => mergeGit.get(directory: d, ggLog: ggLog, automerge: true),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('gh pr merge failed'),
            ),
          ),
        );
      });
    });

    // .........................................................................
    // Azure DevOps

    group('Azure DevOps', () {
      test('creates an auto-complete PR when none exists', () async {
        stubOriginUrl('https://dev.azure.com/you/project');
        stubCurrentBranch('feature');
        stubAz('list', ProcessResult(0, 0, '[]', ''));
        stubAz('create', ProcessResult(0, 0, '', ''));

        final result = await mergeGit.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
        );
        expect(result, isTrue);
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
        stubAz('create', ProcessResult(0, 0, '', ''));

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
        stubAz('create', ProcessResult(0, 0, '', ''));

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
        stubAz('create', ProcessResult(0, 0, '', ''));

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

      test('throws when az repos pr update fails', () async {
        stubOriginUrl('https://dev.azure.com/xyz');
        stubCurrentBranch('feature');
        stubAz(
          'list',
          ProcessResult(0, 0, '[{"pullRequestId":42,"status":"active"}]', ''),
        );
        stubAz('update', ProcessResult(2, 2, '', 'update-fail'));
        expect(
          () => mergeGit.get(directory: d, ggLog: ggLog, automerge: true),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'msg',
              contains('az repos pr update failed'),
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
