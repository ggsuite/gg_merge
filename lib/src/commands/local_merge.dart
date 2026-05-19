// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_is_flutter/gg_is_flutter.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';

/// Performs a local merge into main without remote providers.
class LocalMerge extends DirCommand<bool> {
  /// Creates a [LocalMerge] command
  LocalMerge({
    required super.ggLog,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    bool runPubGet = true,
    super.name = 'local-merge',
    super.description =
        'Performs a local merge into '
        'main without remote providers.',
  }) : _processWrapper = processWrapper,
       _runPubGet = runPubGet;

  final GgProcessWrapper _processWrapper;
  final bool _runPubGet;

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

    if (_runPubGet) {
      // Run pub get so pubspec.lock is up-to-date before the squash commit.
      // Otherwise VS Code's auto pub get races the commit and leaves
      // pubspec.lock dirty afterwards.
      final pubExecutable = isFlutterDir(directory) ? 'flutter' : 'dart';
      final pubGetResult = await _processWrapper.run(
        pubExecutable,
        ['pub', 'get'],
        runInShell: true,
        workingDirectory: directory.path,
      );
      if (pubGetResult.exitCode != 0) {
        throw Exception(
          '$pubExecutable pub get failed: ${pubGetResult.stderr}',
        );
      }

      // Stage pubspec.lock so its update is part of the squash commit.
      final addLockResult = await _processWrapper.run(
        'git',
        ['add', 'pubspec.lock'],
        runInShell: true,
        workingDirectory: directory.path,
      );
      if (addLockResult.exitCode != 0) {
        throw Exception(
          'Failed to stage pubspec.lock: ${addLockResult.stderr}',
        );
      }
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

    ggLog('✅ Local merge successful.');
    return true;
  }
}

/// Mock for unit tests
class MockLocalMerge extends MockDirCommand<bool> implements LocalMerge {}
