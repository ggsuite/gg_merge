// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';

/// Updates current Git project by fetch/pull all branches.
class UpdateProjectGit extends DirCommand<bool> {
  /// Creates a [UpdateProjectGit] command
  UpdateProjectGit({
    required super.ggLog,
    this._processWrapper = const GgProcessWrapper(),
    this._gitRetry = const GitRetry(),
    super.name = 'update-project-git',
    super.description = 'Fetches and pulls remote state for all branches.',
  });

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
    Map<String, dynamic> options = const {},
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Updating Git branches.',
      ggLog: ggLog,
      dark: true,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog),
      success: (b) => b,
    );
  }

  /// Runs `git fetch --all -p` and `git pull`, returns true iff both succeed.
  ///
  /// The pull is skipped when the current branch has no upstream left to
  /// pull from: none was ever set, or the remote branch was merged and
  /// deleted (e.g. by an auto-completed pull request) and the fetch just
  /// pruned it. `git pull` fails on such a branch (»Your configuration
  /// specifies to merge with the ref … but no such ref was fetched«)
  /// although nothing is left to bring in — the fetch already updated the
  /// other branches, the default branch included.
  ///
  /// Both commands are retried on transient network errors.
  @override
  Future<bool> get({required Directory directory, required GgLog ggLog}) async {
    final fetch = await _gitRetry.run(
      () => _run(directory, ['fetch', '--all', '-p']),
      ggLog: ggLog,
      description: 'git fetch --all -p',
    );
    if (fetch.exitCode != 0) {
      throw Exception('git fetch --all failed: ${fetch.stderr}');
    }

    if (!await _hasUpstream(directory)) {
      ggLog(
        cDetail(
          'The current branch has no upstream to pull from (never pushed, '
          'or merged and deleted on the remote). Skipping git pull.',
        ),
      );
      return true;
    }

    final pull = await _gitRetry.run(
      () => _run(directory, ['pull']),
      ggLog: ggLog,
      description: 'git pull',
    );
    if (pull.exitCode != 0) {
      throw Exception('git pull failed: ${pull.stderr}');
    }
    return true;
  }

  // ######################
  // Private
  // ######################

  final GgProcessWrapper _processWrapper;
  final GitRetry _gitRetry;

  // ...........................................................................
  /// Whether the current branch has an upstream whose ref still exists.
  Future<bool> _hasUpstream(Directory directory) async {
    final result = await _run(directory, [
      'rev-parse',
      '--verify',
      '--quiet',
      '@{u}',
    ]);
    return result.exitCode == 0;
  }

  // ...........................................................................
  Future<ProcessResult> _run(Directory directory, List<String> args) =>
      _processWrapper.run(
        'git',
        args,
        runInShell: true,
        workingDirectory: directory.path,
      );
}

/// Mock for unit tests
class MockUpdateProjectGit extends MockDirCommand<bool>
    implements UpdateProjectGit {}
