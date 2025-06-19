// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:io';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_merge/src/commands/is_ahead_main.dart';
import '../helpers.dart';

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('IsAheadMain', () {
    late Directory d;
    late IsAheadMain isAheadMain;
    late MockGgProcessWrapper processWrapper;
    final messages = <String>[];
    final ggLog = messages.add;

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      processWrapper = MockGgProcessWrapper();
      isAheadMain = IsAheadMain(ggLog: ggLog, processWrapper: processWrapper);
      messages.clear();
    });
    tearDown(() async => d.delete(recursive: true));

    test('returns true when ahead > 0', () async {
      when(
        () => processWrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '0 1', ''));
      final result = await isAheadMain.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });
    test('returns false when ahead == 0', () async {
      when(
        () => processWrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '5 0', ''));
      final result = await isAheadMain.exec(directory: d, ggLog: ggLog);
      expect(result, isFalse);
    });

    test('throws Exception if git rev-list fails', () async {
      when(
        () => processWrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(2, 2, '', 'fatal'));
      expect(
        () => isAheadMain.exec(directory: d, ggLog: ggLog),
        throwsA(isA<Exception>()),
      );
    });
  });
}
