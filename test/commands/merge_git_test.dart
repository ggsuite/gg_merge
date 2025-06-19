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

    test('detects GitHub and runs gh pr create, merge', () async {
      // Simulate git config returning a GitHub URL
      when(
        () => processWrapper.run(
          'git',
          ['config', '--get', 'remote.origin.url'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, 'https://github.com/me/repo.git', ''),
      );
      // gh pr create
      when(
        () => processWrapper.run(
          'gh',
          ['pr', 'create', '--fill', '--web=false'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      // gh pr merge only if automerge
      when(
        () => processWrapper.run(
          'gh',
          ['pr', 'merge', '--merge'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      final result =
          await mergeGit.exec(directory: d, ggLog: ggLog, automerge: true);
      expect(result, isTrue);
    });
    test('detects Azure and runs az repos pr create', () async {
      when(
        () => processWrapper.run(
          'git',
          ['config', '--get', 'remote.origin.url'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer(
        (_) async =>
            ProcessResult(0, 0, 'https://dev.azure.com/you/project', ''),
      );
      when(
        () => processWrapper.run(
          'az',
          any(),
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      final result =
          await mergeGit.exec(directory: d, ggLog: ggLog, automerge: false);
      expect(result, isTrue);
    });
    test('throws UnimplementedError for unsupported provider', () async {
      when(
        () => processWrapper.run(
          'git',
          ['config', '--get', 'remote.origin.url'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, 'https://gitlab.com/xyz', ''),
      );
      expect(
        () => mergeGit.exec(directory: d, ggLog: ggLog),
        throwsA(isA<UnimplementedError>()),
      );
    });
    test('throws Exception if gh pr create fails', () async {
      when(
        () => processWrapper.run(
          'git',
          ['config', '--get', 'remote.origin.url'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, 'https://github.com/me/repo.git', ''),
      );
      when(
        () => processWrapper.run(
          'gh',
          ['pr', 'create', '--fill', '--web=false'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'no-pr'));
      expect(
        () => mergeGit.exec(directory: d, ggLog: ggLog, automerge: false),
        throwsA(isA<Exception>()),
      );
    });
    test('throws Exception if az repos pr create fails', () async {
      when(
        () => processWrapper.run(
          'git',
          ['config', '--get', 'remote.origin.url'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, 'https://dev.azure.com/xyz', ''),
      );
      when(
        () => processWrapper.run(
          'az',
          any(),
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(2, 2, '', 'fail-az'));
      expect(
        () => mergeGit.exec(directory: d, ggLog: ggLog, automerge: true),
        throwsA(isA<Exception>()),
      );
    });

    test('throws Exception if git config fails', () async {
      // Simulate git config failing
      when(
        () => processWrapper.run(
          'git',
          ['config', '--get', 'remote.origin.url'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'fatal'));
      // The code should throw because git config exits non-zero
      expect(
        () => mergeGit.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('git config failed'),
          ),
        ),
      );
    });

    test('throws Exception if gh pr merge fails', () async {
      // Covers error branch after gh pr merge (automerge = true)
      when(
        () => processWrapper.run(
          'git',
          ['config', '--get', 'remote.origin.url'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, 'https://github.com/x/y.git', ''),
      );
      when(
        () => processWrapper.run(
          'gh',
          ['pr', 'create', '--fill', '--web=false'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          'gh',
          ['pr', 'merge', '--merge'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(3, 3, '', 'mergeError'));
      expect(
        () => mergeGit.exec(directory: d, ggLog: ggLog, automerge: true),
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
}
