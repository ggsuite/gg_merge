// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:gg_args/gg_args.dart';
import 'package:gg_merge/gg_merge.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];

  setUp(() {
    messages.clear();
  });

  group('GgMerge()', () {
    // #########################################################################
    group('GgMerge', () {
      final ggMerge = GgMerge(ggLog: (msg) => messages.add(msg));

      // .......................................................................
      test('should show all sub commands', () async {
        final (subCommands, errorMessage) = await missingSubCommands(
          directory: Directory('lib/src/commands'),
          command: ggMerge,
        );

        expect(subCommands, isEmpty, reason: errorMessage);
      });
    });
  });
}
