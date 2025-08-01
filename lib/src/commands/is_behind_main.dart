// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:gg_process/gg_process.dart';
import '../util/command_helpers.dart';

/// Checks if the branch is behind main.
class IsBehindMain extends DirCommand<bool> {
  /// Creates a [IsBehindMain] command
  IsBehindMain({
    required super.ggLog,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    super.name = 'is-behind-main',
    super.description = 'Checks if the current branch is behind main.',
  }) : _processWrapper = processWrapper;

  final GgProcessWrapper _processWrapper;

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Checking if branch is behind main.',
      ggLog: ggLog,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog),
      success: (v) => v,
    );
  }

  /// Returns true if the current branch is behind main (B > 0)
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final result = await _processWrapper.run(
      'git',
      [
        'rev-list',
        '--left-right',
        '--count',
        'origin/main...HEAD',
      ],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result.exitCode != 0) {
      throw Exception('git rev-list failed: ${result.stderr}');
    }
    final (behind, ahead) = parseGitAheadBehind(result.stdout.toString());
    return behind > 0;
  }
}

/// Mock for unit tests
class MockIsBehindMain extends MockDirCommand<bool> implements IsBehindMain {}
