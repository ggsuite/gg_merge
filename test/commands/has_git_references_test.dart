// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:test/test.dart';
import 'package:gg_merge/src/commands/has_git_references.dart';
import '../helpers.dart';

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('HasGitReferences', () {
    late Directory d;
    late HasGitReferences hasGitReferences;
    final messages = <String>[];
    final ggLog = messages.add;

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      hasGitReferences = HasGitReferences(ggLog: ggLog);
      messages.clear();
    });
    tearDown(() async => d.delete(recursive: true));

    test('throws ArgumentError if pubspec.yaml is missing', () async {
      expect(
        () => hasGitReferences.exec(directory: d, ggLog: ggLog),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('returns false if no git: references are found', () async {
      final pubspec = File('${d.path}/pubspec.yaml');
      await pubspec.writeAsString('name: test\ndependencies:\n  git: ^1.0.0');
      final result = await hasGitReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isFalse);
    });

    test('returns true if git: reference is in dependencies', () async {
      final pubspec = File('${d.path}/pubspec.yaml');
      await pubspec.writeAsString('''
dependencies:
  gg_git:
    git:
      url: git@github.com:test/gg_git.git
''');
      final result = await hasGitReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('returns true if git: reference is in dev_dependencies', () async {
      final pubspec = File('${d.path}/pubspec.yaml');
      await pubspec.writeAsString('''
dev_dependencies:
  gg_git:
    git:
      url: git@github.com:test/gg_git.git
''');
      final result = await hasGitReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });
  });
}
