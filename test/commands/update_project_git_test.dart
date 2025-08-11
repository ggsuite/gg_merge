// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:io';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_merge/src/commands/update_project_git.dart';
import '../helpers.dart';

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('UpdateProjectGit', () {
    late Directory d;
    late UpdateProjectGit updateProjectGit;
    late MockGgProcessWrapper processWrapper;
    final messages = <String>[];
    final ggLog = messages.add;

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      processWrapper = MockGgProcessWrapper();
      updateProjectGit = UpdateProjectGit(
        ggLog: ggLog,
        processWrapper: processWrapper,
      );
      messages.clear();
    });
    tearDown(() async => d.delete(recursive: true));

    test('runs fetch and pull successfully', () async {
      when(
        () => processWrapper.run(
          'git',
          ['fetch', '--all', '-p'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          'git',
          ['pull', '--all'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      final result = await updateProjectGit.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });
    test('throws Exception if fetch fails', () async {
      when(
        () => processWrapper.run(
          'git',
          ['fetch', '--all', '-p'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'fail-fetch'));
      expect(
        () => updateProjectGit.exec(directory: d, ggLog: ggLog),
        throwsA(isA<Exception>()),
      );
    });
    test('throws Exception if pull fails', () async {
      when(
        () => processWrapper.run(
          'git',
          ['fetch', '--all', '-p'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => processWrapper.run(
          'git',
          ['pull', '--all'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'fail-pull'));
      expect(
        () => updateProjectGit.exec(directory: d, ggLog: ggLog),
        throwsA(isA<Exception>()),
      );
    });
  });
}
