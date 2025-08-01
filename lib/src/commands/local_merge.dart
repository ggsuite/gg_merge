// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:gg_process/gg_process.dart';

/// Performs a local merge into main without remote providers.
class LocalMerge extends DirCommand<bool> {
  /// Creates a [LocalMerge] command
  LocalMerge({
    required super.ggLog,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    super.name = 'local-merge',
    super.description = 'Performs a local merge into '
        'main without remote providers.',
  }) : _processWrapper = processWrapper;

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
  }) async {
    // Get current branch
    final currentBranchResult = await _processWrapper.run(
      'git',
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      runInShell: true,
      workingDirectory: directory.path,
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
    final checkoutResult = await _processWrapper.run(
      'git',
      ['checkout', 'main'],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (checkoutResult.exitCode != 0) {
      throw Exception('Failed to checkout main: ${checkoutResult.stderr}');
    }

    // Merge current branch with squash
    final mergeResult = await _processWrapper.run(
      'git',
      ['merge', currentBranch, '--squash'],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (mergeResult.exitCode != 0) {
      throw Exception('Merge failed: ${mergeResult.stderr}');
    }

    // Commit with provided message or default
    final commitMessage = message ?? 'Merged $currentBranch into main';
    final commitResult = await _processWrapper.run(
      'git',
      ['commit', '-m', commitMessage],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (commitResult.exitCode != 0) {
      throw Exception('Commit failed: ${commitResult.stderr}');
    }

    // Push to origin/main
    final pushResult = await _processWrapper.run(
      'git',
      ['push', 'origin', 'main'],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (pushResult.exitCode != 0) {
      throw Exception('Push failed: ${pushResult.stderr}');
    }

    ggLog('✅ Local merge successful.');
    return true;
  }
}

/// Mock for unit tests
class MockLocalMerge extends MockDirCommand<bool> implements LocalMerge {}
