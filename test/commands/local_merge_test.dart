// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_is_flutter/gg_is_flutter.dart';
import 'package:gg_merge/src/commands/local_merge.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('LocalMerge', () {
    late Directory d;
    late LocalMerge localMerge;
    late MockGgProcessWrapper processWrapper;
    final messages = <String>[];
    final ggLog = messages.add;

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      processWrapper = MockGgProcessWrapper();
      localMerge = LocalMerge(ggLog: ggLog, processWrapper: processWrapper);
      messages.clear();
      testIsFlutter = false;
    });

    tearDown(() async {
      testResetIsFlutter();
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

    void mockCheckoutMain({int exitCode = 0, String stderr = ''}) {
      when(
        () => processWrapper.run(
          any(),
          ['checkout', 'main'],
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

    void mockPubGet({
      String executable = 'dart',
      int exitCode = 0,
      String stderr = '',
    }) {
      when(
        () => processWrapper.run(
          executable,
          ['pub', 'get'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, exitCode, '', stderr));
    }

    void mockAddLock({int exitCode = 0, String stderr = ''}) {
      when(
        () => processWrapper.run(
          any(),
          ['add', 'pubspec.lock'],
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
      mockPubGet();
      mockAddLock();
      mockCommit('Merged feature-branch into main');

      final result = await localMerge.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      expect(messages, contains('✅ Local merge successful.'));
    });

    test('performs successful local merge with custom message', () async {
      mockCurrentBranch('feature-branch');
      mockCheckoutMain();
      mockSquash('feature-branch');
      mockPubGet();
      mockAddLock();
      mockCommit('Custom merge message');

      final result = await localMerge.get(
        directory: d,
        ggLog: ggLog,
        message: 'Custom merge message',
      );
      expect(result, isTrue);
      expect(messages, contains('✅ Local merge successful.'));
    });

    test('uses default message if no custom message provided', () async {
      mockCurrentBranch('feature-branch');
      mockCheckoutMain();
      mockSquash('feature-branch');
      mockPubGet();
      mockAddLock();
      mockCommit('Merged feature-branch into main');

      final result = await localMerge.get(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('skips pub get and lock-staging when runPubGet is false', () async {
      final noPubGetMerge = LocalMerge(
        ggLog: ggLog,
        processWrapper: processWrapper,
        runPubGet: false,
      );
      mockCurrentBranch('feature-branch');
      mockCheckoutMain();
      mockSquash('feature-branch');
      mockCommit('Merged feature-branch into main');

      final result = await noPubGetMerge.exec(directory: d, ggLog: ggLog);
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

    test('uses flutter pub get on flutter projects', () async {
      testIsFlutter = true;
      mockCurrentBranch('feature-branch');
      mockCheckoutMain();
      mockSquash('feature-branch');
      mockPubGet(executable: 'flutter');
      mockAddLock();
      mockCommit('Merged feature-branch into main');

      final result = await localMerge.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      verify(
        () => processWrapper.run(
          'flutter',
          ['pub', 'get'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
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

    test('throws on pub get failure', () async {
      mockCurrentBranch('feature');
      mockCheckoutMain();
      mockSquash('feature');
      mockPubGet(exitCode: 1, stderr: 'pub error');
      expect(
        () => localMerge.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('dart pub get failed: pub error'),
          ),
        ),
      );
    });

    test('throws on git add pubspec.lock failure', () async {
      mockCurrentBranch('feature');
      mockCheckoutMain();
      mockSquash('feature');
      mockPubGet();
      mockAddLock(exitCode: 1, stderr: 'add error');
      expect(
        () => localMerge.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to stage pubspec.lock: add error'),
          ),
        ),
      );
    });

    test('throws on commit failure', () async {
      mockCurrentBranch('feature');
      mockCheckoutMain();
      mockSquash('feature');
      mockPubGet();
      mockAddLock();
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
  });
}
