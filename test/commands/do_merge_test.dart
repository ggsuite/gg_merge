// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:io';
import 'package:gg_merge/src/commands/do_merge.dart';
import 'package:gg_merge/src/commands/can_merge.dart';
import 'package:gg_merge/src/commands/merge_git.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import '../helpers.dart';

class _MockCanMerge extends Mock implements CanMerge {}

class _MockMergeGit extends Mock implements MergeGit {}

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('DoMerge', () {
    late Directory d;
    final messages = <String>[];
    final ggLog = messages.add;
    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      messages.clear();
    });
    tearDown(() async => d.delete(recursive: true));

    test('calls CanMerge then MergeGit with automerge', () async {
      final canMerge = _MockCanMerge();
      final mergeGit = _MockMergeGit();
      when(
        () => canMerge.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mergeGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          automerge: any(named: 'automerge'),
        ),
      ).thenAnswer((_) async => true);
      final doMerge = DoMerge(
        ggLog: ggLog,
        canMerge: canMerge,
        mergeGit: mergeGit,
      );
      final result =
          await doMerge.exec(directory: d, ggLog: ggLog, automerge: true);
      expect(result, isTrue);
      verify(() => canMerge.get(directory: d, ggLog: ggLog)).called(1);
      verify(() => mergeGit.get(directory: d, ggLog: ggLog, automerge: true))
          .called(1);
      expect(messages.last, contains('Performing final merge'));
    });
    test('throws if CanMerge fails, MergeGit not called', () async {
      final canMerge = _MockCanMerge();
      final mergeGit = _MockMergeGit();
      when(
        () => canMerge.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => false);
      final doMerge = DoMerge(
        ggLog: ggLog,
        canMerge: canMerge,
        mergeGit: mergeGit,
      );
      expect(
        () => doMerge.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('Not allowed to merge'),
          ),
        ),
      );
      verify(() => canMerge.get(directory: d, ggLog: ggLog)).called(1);
      verifyNever(
        () => mergeGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          automerge: any(named: 'automerge'),
        ),
      );
    });
    test('passes automerge param correctly', () async {
      final canMerge = _MockCanMerge();
      final mergeGit = _MockMergeGit();
      when(
        () => canMerge.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);
      bool paramReceived = false;
      when(
        () => mergeGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          automerge: any(named: 'automerge'),
        ),
      ).thenAnswer((invocation) async {
        paramReceived = invocation.namedArguments[#automerge] == true;
        return true;
      });
      final doMerge = DoMerge(
        ggLog: ggLog,
        canMerge: canMerge,
        mergeGit: mergeGit,
      );
      await doMerge.exec(directory: d, ggLog: ggLog, automerge: true);
      expect(paramReceived, isTrue);
    });
  });
}
