// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_merge/src/commands/local_merge.dart';
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
    });

    tearDown(() async => d.delete(recursive: true));

    test('performs successful local merge', () async {
      when(
        () => processWrapper.run(
          any(),
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'feature-branch', ''));
      when(
        () => processWrapper.run(
          any(),
          ['checkout', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['merge', 'feature-branch', '--squash'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['commit', '-m', 'Merged feature-branch into main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['push', 'origin', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      final result = await localMerge.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      expect(messages, contains('✅ Local merge successful.'));
    });

    test('performs successful local merge with custom message', () async {
      when(
        () => processWrapper.run(
          any(),
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'feature-branch', ''));
      when(
        () => processWrapper.run(
          any(),
          ['checkout', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['merge', 'feature-branch', '--squash'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['commit', '-m', 'Custom merge message'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['push', 'origin', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      final result = await localMerge.get(
        directory: d,
        ggLog: ggLog,
        message: 'Custom merge message',
      );
      expect(result, isTrue);
      expect(messages, contains('✅ Local merge successful.'));
    });

    test('uses default message if no custom message provided', () async {
      when(
        () => processWrapper.run(
          any(),
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'feature-branch', ''));
      when(
        () => processWrapper.run(
          any(),
          ['checkout', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['merge', 'feature-branch', '--squash'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['commit', '-m', 'Merged feature-branch into main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['push', 'origin', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      final result = await localMerge.get(
        directory: d,
        ggLog: ggLog,
      );
      expect(result, isTrue);
    });

    test('throws if already on main', () async {
      when(
        () => processWrapper.run(
          any(),
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'main', ''));
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
      when(
        () => processWrapper.run(
          any(),
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'feature', ''));
      when(
        () => processWrapper.run(
          any(),
          ['checkout', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['merge', 'feature', '--squash'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'conflict'));
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
      when(
        () => processWrapper.run(
          any(),
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'feature', ''));
      when(
        () => processWrapper.run(
          any(),
          ['checkout', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['merge', 'feature', '--squash'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['commit', '-m', 'Merged feature into main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'commit error'));
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

    test('throws on push failure', () async {
      when(
        () => processWrapper.run(
          any(),
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'feature', ''));
      when(
        () => processWrapper.run(
          any(),
          ['checkout', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['merge', 'feature', '--squash'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['commit', '-m', 'Merged feature into main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          any(),
          ['push', 'origin', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'push error'));
      expect(
        () => localMerge.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Push failed'),
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
      when(
        () => processWrapper.run(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'feature', ''));
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
