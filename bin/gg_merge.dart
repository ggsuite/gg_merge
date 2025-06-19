#!/usr/bin/env dart
// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_merge/gg_merge.dart';

// .............................................................................
Future<void> run({
  required List<String> args,
  required GgLog ggLog,
}) =>
    GgCommandRunner(
      ggLog: ggLog,
      command: GgMerge(ggLog: ggLog),
    ).run(args: args);

// .............................................................................
Future<void> main(List<String> args) async {
  await run(
    args: args,
    ggLog: (msg) => print(msg),
  );
}
