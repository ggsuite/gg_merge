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

import '../util/command_helpers.dart';

/// Performs a local merge into the default branch without remote providers.
class LocalMerge extends DirCommand<bool> {
  /// Creates a [LocalMerge] command
  LocalMerge({
    required super.ggLog,
    this._processWrapper = const GgProcessWrapper(),
    DefaultBranch? defaultBranch,
    super.name = 'local-merge',
    super.description =
        'Performs a local merge into '
        'the default branch without remote providers.',
  }) : _defaultBranch =
           defaultBranch ??
           DefaultBranch(ggLog: ggLog, processWrapper: _processWrapper) {
    _addArgs();
  }

  final GgProcessWrapper _processWrapper;
  final DefaultBranch _defaultBranch;

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
    Map<String, dynamic> options = const {},
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Performing local merge into the default branch.',
      ggLog: ggLog,
      dark: true,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog),
      success: (v) => v,
    );
  }

  /// Squash-merges the current branch into the default branch.
  ///
  /// [mainBranch] names the target branch. Without it the repository's
  /// default branch is used (`origin/HEAD`, else `main`, else `master`).
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    String? message,
    bool? verbose,
    String? mainBranch,
  }) async {
    final isVerbose = verbose ?? _verboseFromArgs;
    final targetBranch = await resolveMainBranch(
      defaultBranch: _defaultBranch,
      directory: directory,
      ggLog: ggLog,
      mainBranch: mainBranch,
    );

    // Get current branch
    final currentBranchResult = await _run(
      'git',
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      directory: directory,
      ggLog: ggLog,
      verbose: isVerbose,
    );
    if (currentBranchResult.exitCode != 0) {
      throw Exception(
        'Failed to get current branch: ${currentBranchResult.stderr}',
      );
    }
    final currentBranch = currentBranchResult.stdout.toString().trim();
    if (currentBranch == targetBranch) {
      throw Exception('Already on $targetBranch branch; nothing to merge.');
    }

    // Checkout the default branch
    final checkoutResult = await _run(
      'git',
      ['checkout', targetBranch],
      directory: directory,
      ggLog: ggLog,
      verbose: isVerbose,
    );
    if (checkoutResult.exitCode != 0) {
      throw Exception(
        'Failed to checkout $targetBranch: ${checkoutResult.stderr}',
      );
    }

    // Merge current branch with squash
    final mergeResult = await _run(
      'git',
      ['merge', currentBranch, '--squash'],
      directory: directory,
      ggLog: ggLog,
      verbose: isVerbose,
    );
    if (mergeResult.exitCode != 0) {
      throw Exception('Merge failed: ${mergeResult.stderr}');
    }

    // No gg prefix, even in the fallback: this commit lands on the default
    // branch, and a »#gg: « subject there would claim it is gg bookkeeping —
    // the default branch carries releases and tags only.
    final commitMessage = message ?? 'Merged $currentBranch into $targetBranch';
    final commitResult = await _run(
      'git',
      ['commit', '-m', commitMessage],
      directory: directory,
      ggLog: ggLog,
      verbose: isVerbose,
    );
    if (commitResult.exitCode != 0) {
      throw Exception('Commit failed: ${commitResult.stderr}');
    }

    ggLog(cDetail('✓ Local merge successful.'));
    return true;
  }

  // ...........................................................................
  void _addArgs() {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Prints each executed command before running it.',
      defaultsTo: false,
      negatable: false,
    );
  }

  bool get _verboseFromArgs => argResults?['verbose'] as bool? ?? false;

  Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    required Directory directory,
    required GgLog ggLog,
    required bool verbose,
  }) {
    if (verbose) {
      ggLog('\$ $executable ${arguments.join(' ')}');
    }
    return _processWrapper.run(
      executable,
      arguments,
      runInShell: true,
      workingDirectory: directory.path,
    );
  }
}

/// Mock for unit tests
class MockLocalMerge extends MockDirCommand<bool> implements LocalMerge {}
