// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';

/// Performs a local merge into main without remote providers.
class LocalMerge extends DirCommand<bool> {
  /// Creates a [LocalMerge] command
  LocalMerge({
    required super.ggLog,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    super.name = 'local-merge',
    super.description =
        'Performs a local merge into '
        'main without remote providers.',
  }) : _processWrapper = processWrapper {
    _addArgs();
  }

  final GgProcessWrapper _processWrapper;

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Performing local merge into main.',
      ggLog: ggLog,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog),
      success: (v) => v,
    );
  }

  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    String? message,
    bool? verbose,
  }) async {
    final isVerbose = verbose ?? _verboseFromArgs;

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
    if (currentBranch == 'main') {
      throw Exception('Already on main branch; nothing to merge.');
    }

    // Checkout main
    final checkoutResult = await _run(
      'git',
      ['checkout', 'main'],
      directory: directory,
      ggLog: ggLog,
      verbose: isVerbose,
    );
    if (checkoutResult.exitCode != 0) {
      throw Exception('Failed to checkout main: ${checkoutResult.stderr}');
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

    // Commit with provided message or default
    final commitMessage = message ?? 'Merged $currentBranch into main';
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

    ggLog('✅ Local merge successful.');
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
