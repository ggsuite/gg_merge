// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';

void main() {
  group('bin/gg_merge.dart', () {
    test('should be executable', () async {
      final result = await Process.run(
        'dart',
        ['./bin/gg_merge.dart', 'can-merge', '--help'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final stdout = result.stdout as String;
      expect(stdout.toLowerCase(), contains('can-merge'));
      expect(stdout, contains('Checks if merge to main is allowed'));
    });
  });
}
