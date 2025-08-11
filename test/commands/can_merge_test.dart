// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:io';
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
    final messages = <String>[];
    final ggLog = messages.add;

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      messages.clear();
    });
    tearDown(() async => d.delete(recursive: true));

    test('returns true if all checks pass (ok)', () async {
      // Arrange
      final local = _MockHasLocalRef();
      final behind = _MockIsBehind();
      final ahead = _MockIsAhead();
      final updGit = _MockUpdateGit();
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
      ).thenAnswer((_) async => false);
      when(
        () => behind.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => false);
      when(
        () => ahead.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);
      final canMerge = CanMerge(
        ggLog: ggLog,
        hasLocalReferences: local,
        isBehindMain: behind,
        isAheadMain: ahead,
        updateProjectGit: updGit,
      );
      final result = await canMerge.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
      expect(messages.last, contains('Checking if merge is allowed'));
    });
    test('throws if hasLocalReferences is true', () async {
      final local = _MockHasLocalRef();
      final behind = _MockIsBehind();
      final ahead = _MockIsAhead();
      final updGit = _MockUpdateGit();

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
      ).thenAnswer((_) async => true);
      when(
        () => behind.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => false);
      when(
        () => ahead.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);
      final canMerge = CanMerge(
        ggLog: ggLog,
        hasLocalReferences: local,
        isBehindMain: behind,
        isAheadMain: ahead,
        updateProjectGit: updGit,
      );
      expect(
        () => canMerge.exec(directory: d, ggLog: ggLog),
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
      final local = _MockHasLocalRef();
      final behind = _MockIsBehind();
      final ahead = _MockIsAhead();
      final updGit = _MockUpdateGit();
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
      ).thenAnswer((_) async => false);
      when(
        () => behind.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => ahead.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);
      final canMerge = CanMerge(
        ggLog: ggLog,
        hasLocalReferences: local,
        isBehindMain: behind,
        isAheadMain: ahead,
        updateProjectGit: updGit,
      );
      expect(
        () => canMerge.exec(directory: d, ggLog: ggLog),
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
      final local = _MockHasLocalRef();
      final behind = _MockIsBehind();
      final ahead = _MockIsAhead();
      final updGit = _MockUpdateGit();
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
      ).thenAnswer((_) async => false);
      when(
        () => behind.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => false);
      when(
        () => ahead.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => false);
      final canMerge = CanMerge(
        ggLog: ggLog,
        hasLocalReferences: local,
        isBehindMain: behind,
        isAheadMain: ahead,
        updateProjectGit: updGit,
      );
      expect(
        () => canMerge.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('nothing to merge'),
          ),
        ),
      );
    });
  });
}
