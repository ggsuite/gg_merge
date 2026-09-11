// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';

import '../util/command_helpers.dart';

/// Checks if the branch is behind the default branch.
class IsBehindMain extends DirCommand<bool> {
  /// Creates a [IsBehindMain] command
  IsBehindMain({
    required super.ggLog,
    this._processWrapper = const GgProcessWrapper(),
    DefaultBranch? defaultBranch,
    super.name = 'is-behind-main',
    super.description =
        'Checks if the current branch is behind the default branch.',
  }) : _defaultBranch =
           defaultBranch ??
           DefaultBranch(ggLog: ggLog, processWrapper: _processWrapper);

  final GgProcessWrapper _processWrapper;
  final DefaultBranch _defaultBranch;

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
    Map<String, dynamic> options = const {},
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Checking if branch is behind the default branch.',
      ggLog: ggLog,
      dark: true,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog),
      success: (v) => v,
    );
  }

  /// Returns true if the current branch is behind the default branch
  /// (B > 0). [mainBranch] names that branch; without it the name is read
  /// from the repository (`origin/HEAD`, else `main`, else `master`).
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    String? mainBranch,
  }) async {
    final branch = await resolveMainBranch(
      defaultBranch: _defaultBranch,
      directory: directory,
      ggLog: ggLog,
      mainBranch: mainBranch,
    );
    final result = await _processWrapper.run(
      'git',
      ['rev-list', '--left-right', '--count', 'origin/$branch...HEAD'],
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
