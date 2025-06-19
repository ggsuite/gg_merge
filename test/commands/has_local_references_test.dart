// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
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

    test('throws ArgumentError if pubspec.yaml is missing', () async {
      expect(
        () => hasLocalReferences.exec(directory: d, ggLog: ggLog),
        throwsA(isA<ArgumentError>()),
      );
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
  });
}
