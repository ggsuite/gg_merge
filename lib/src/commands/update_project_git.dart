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

/// Updates current Git project by fetch/pull all branches.
class UpdateProjectGit extends DirCommand<bool> {
  /// Creates a [UpdateProjectGit] command
  UpdateProjectGit({
    required super.ggLog,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    super.name = 'update-project-git',
    super.description = 'Fetches and pulls remote state for all branches.',
  }) : _processWrapper = processWrapper;

  final GgProcessWrapper _processWrapper;

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Updating Git branches.',
      ggLog: ggLog,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog),
      success: (b) => b,
    );
  }

  /// Runs git fetch --all -p and git pull --all, returns true iff all succeed
  @override
  Future<bool> get({required Directory directory, required GgLog ggLog}) async {
    final result1 = await _processWrapper.run(
      'git',
      ['fetch', '--all', '-p'],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result1.exitCode != 0) {
      throw Exception('git fetch --all failed: ${result1.stderr}');
    }
    final result2 = await _processWrapper.run(
      'git',
      ['pull', '--all'],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result2.exitCode != 0) {
      throw Exception('git pull --all failed: ${result2.stderr}');
    }
    return true;
  }
}

/// Mock for unit tests
class MockUpdateProjectGit extends MockDirCommand<bool>
    implements UpdateProjectGit {}
