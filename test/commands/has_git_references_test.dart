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

    test('throws ArgumentError if no manifest is found', () async {
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

    // -----------------------------------------------------------------------
    // TypeScript: package.json + tsconfig.json
    // -----------------------------------------------------------------------

    /// Writes the manifest pair (`package.json` + `tsconfig.json`) that
    /// `detectProjectType` requires to identify a directory as TypeScript.
    Future<void> writeTsProject(String packageJson) async {
      await File('${d.path}/package.json').writeAsString(packageJson);
      await File('${d.path}/tsconfig.json').writeAsString('{}');
    }

    test('TS: returns false when no git refs are present', () async {
      await writeTsProject('''
{
  "name": "demo",
  "dependencies": { "lodash": "^4.17.0" },
  "devDependencies": { "vitest": "^4.0.0" }
}
''');
      final result = await hasGitReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isFalse);
    });

    test('TS: detects git+https URL', () async {
      await writeTsProject('''
{
  "name": "demo",
  "dependencies": {
    "@me/forked": "git+https://github.com/me/forked.git#main"
  }
}
''');
      final result = await hasGitReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('TS: detects git:// URL', () async {
      await writeTsProject('''
{
  "name": "demo",
  "devDependencies": { "@me/git": "git://example.com/me/pkg.git" }
}
''');
      final result = await hasGitReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('TS: detects git@ scp-style URL', () async {
      await writeTsProject('''
{
  "name": "demo",
  "peerDependencies": { "@me/ssh": "git@github.com:me/pkg.git" }
}
''');
      final result = await hasGitReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('TS: detects github: shorthand', () async {
      await writeTsProject('''
{
  "name": "demo",
  "dependencies": { "@me/short": "github:me/pkg#v1.2.3" }
}
''');
      final result = await hasGitReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('TS: detects gitlab/bitbucket/gist shorthands', () async {
      for (final ref in const [
        'gitlab:me/pkg',
        'bitbucket:me/pkg',
        'gist:abcdef123456',
      ]) {
        final subDir = await Directory.systemTemp.createTemp(
          'ggmerge_git_test_sub_',
        );
        try {
          await File('${subDir.path}/package.json').writeAsString(
            '{"name": "demo", "dependencies": {"@me/pkg": "$ref"}}',
          );
          await File('${subDir.path}/tsconfig.json').writeAsString('{}');
          final result = await hasGitReferences.exec(
            directory: subDir,
            ggLog: ggLog,
          );
          expect(result, isTrue, reason: 'should detect git ref "$ref"');
        } finally {
          await subDir.delete(recursive: true);
        }
      }
    });
  });
}
