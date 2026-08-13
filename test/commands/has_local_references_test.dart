// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:test/test.dart';
import 'package:gg_merge/src/commands/has_local_references.dart';
import '../helpers.dart';

void main() {
  setUpAll(() {
    registerTestFallbacks();
  });

  group('HasLocalReferences', () {
    late Directory d;
    late HasLocalReferences hasLocalReferences;
    final messages = <String>[];
    final ggLog = messages.add;

    setUp(() async {
      d = await Directory.systemTemp.createTemp('ggmerge_test_');
      hasLocalReferences = HasLocalReferences(ggLog: ggLog);
      messages.clear();
    });
    tearDown(() async => d.delete(recursive: true));

    test('returns false if no manifest is found', () async {
      final result = await hasLocalReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isFalse);
    });

    test('returns false if no path: references are found', () async {
      final pubspec = File('${d.path}/pubspec.yaml');
      await pubspec.writeAsString('name: test\ndependencies:\n  path: ^1.0.0');
      final result = await hasLocalReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isFalse);
    });

    test('returns true if path: reference is in dependencies', () async {
      final pubspec = File('${d.path}/pubspec.yaml');
      await pubspec.writeAsString('''
dependencies:
  local:
    path: ../local_package
''');
      final result = await hasLocalReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('returns true if path: reference is in dev_dependencies', () async {
      final pubspec = File('${d.path}/pubspec.yaml');
      await pubspec.writeAsString('''
dev_dependencies:
  local:
    path: ../local_package
''');
      final result = await hasLocalReferences.exec(directory: d, ggLog: ggLog);
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

    test('TS: returns false when no local refs are present', () async {
      await writeTsProject('''
{
  "name": "demo",
  "dependencies": { "lodash": "^4.17.0" },
  "devDependencies": { "vitest": "^4.0.0" }
}
''');
      final result = await hasLocalReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isFalse);
    });

    test('TS: detects file: protocol in dependencies', () async {
      await writeTsProject('''
{
  "name": "demo",
  "dependencies": { "@me/local": "file:../local_pkg" }
}
''');
      final result = await hasLocalReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('TS: detects link: protocol in devDependencies', () async {
      await writeTsProject('''
{
  "name": "demo",
  "devDependencies": { "@me/linked": "link:../linked_pkg" }
}
''');
      final result = await hasLocalReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('TS: detects workspace: protocol in peerDependencies', () async {
      await writeTsProject('''
{
  "name": "demo",
  "peerDependencies": { "@me/sibling": "workspace:*" }
}
''');
      final result = await hasLocalReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('TS: detects bare relative paths', () async {
      await writeTsProject('''
{
  "name": "demo",
  "dependencies": { "@me/rel": "../some_pkg" }
}
''');
      final result = await hasLocalReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('TS: detects absolute Windows paths', () async {
      await writeTsProject(r'''
{
  "name": "demo",
  "optionalDependencies": { "@me/win": "C:\\repos\\pkg" }
}
''');
      final result = await hasLocalReferences.exec(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    // -----------------------------------------------------------------------
    // Hybrid: pubspec.yaml + package.json
    // -----------------------------------------------------------------------

    /// A hybrid carries both manifests. detectProjectType gives pubspec.yaml
    /// precedence, so the npm side used to be invisible here.
    Future<void> writeHybrid({
      required String pubspec,
      required String packageJson,
    }) async {
      await File('${d.path}/pubspec.yaml').writeAsString(pubspec);
      await File('${d.path}/package.json').writeAsString(packageJson);
    }

    test('hybrid: returns false when neither side is localized', () async {
      await writeHybrid(
        pubspec: 'name: demo\ndependencies:\n  foo: ^1.0.0\n',
        packageJson:
            '{"name": "@me/demo", '
            '"dependencies": {"lodash": "^4.17.0"}}',
      );
      expect(
        await hasLocalReferences.exec(directory: d, ggLog: ggLog),
        isFalse,
      );
    });

    test('hybrid: detects a link: in package.json', () async {
      // The blind spot: a clean pubspec used to hide a localized npm
      // dependency, which would then have been published unresolvable.
      await writeHybrid(
        pubspec: 'name: demo\ndependencies:\n  foo: ^1.0.0\n',
        packageJson:
            '{"name": "@me/demo", '
            '"dependencies": {"@me/sibling": "link:../sibling"}}',
      );
      expect(await hasLocalReferences.exec(directory: d, ggLog: ggLog), isTrue);
    });

    test('hybrid: detects a path: in pubspec.yaml', () async {
      await writeHybrid(
        pubspec:
            'name: demo\ndependencies:\n'
            '  foo:\n    path: ../foo\n',
        packageJson:
            '{"name": "@me/demo", '
            '"dependencies": {"lodash": "^4.17.0"}}',
      );
      expect(await hasLocalReferences.exec(directory: d, ggLog: ggLog), isTrue);
    });
  });
}
