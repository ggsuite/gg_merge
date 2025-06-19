// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'has_local_references.dart';
import 'has_git_references.dart';
import 'is_behind_main.dart';
import 'is_ahead_main.dart';
import 'update_project_git.dart';

/// Determines if merging is allowed according to project rules.
class CanMerge extends DirCommand<bool> {
  /// Create a [CanMerge] command
  CanMerge({
    required super.ggLog,
    HasLocalReferences? hasLocalReferences,
    HasGitReferences? hasGitReferences,
    IsBehindMain? isBehindMain,
    IsAheadMain? isAheadMain,
    UpdateProjectGit? updateProjectGit,
    super.name = 'can-merge',
    super.description =
        'Checks if merge to main is allowed according to rules.',
    // coverage:ignore-start
  })  : _hasLocalReferences =
            hasLocalReferences ?? HasLocalReferences(ggLog: ggLog),
        _hasGitReferences = hasGitReferences ?? HasGitReferences(ggLog: ggLog),
        _isBehindMain = isBehindMain ?? IsBehindMain(ggLog: ggLog),
        _isAheadMain = isAheadMain ?? IsAheadMain(ggLog: ggLog),
        _updateProjectGit = updateProjectGit ?? UpdateProjectGit(ggLog: ggLog);
  // coverage:ignore-end

  final HasLocalReferences _hasLocalReferences;
  final HasGitReferences _hasGitReferences;
  final IsBehindMain _isBehindMain;
  final IsAheadMain _isAheadMain;
  final UpdateProjectGit _updateProjectGit;

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Checking if merge is allowed.',
      ggLog: ggLog,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog),
      success: (v) => v,
    );
  }

  /// Returns true iff all merge pre-conditions are met.
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    await _updateProjectGit.get(directory: directory, ggLog: ggLog);
    if (await _hasLocalReferences.get(directory: directory, ggLog: ggLog)) {
      throw Exception('Local (path:) references found in pubspec.yaml');
    }
    if (await _hasGitReferences.get(directory: directory, ggLog: ggLog)) {
      throw Exception('Git (git:) references found in pubspec.yaml');
    }
    if (await _isBehindMain.get(directory: directory, ggLog: ggLog)) {
      throw Exception(
        'Current branch is behind main. Please rebase or merge main first.',
      );
    }
    final isAhead = await _isAheadMain.get(directory: directory, ggLog: ggLog);
    if (!isAhead) {
      throw Exception(
        'Branch is not ahead of main; there is nothing to merge.',
      );
    }
    ggLog('✅ All merge conditions fulfilled.');
    return true;
  }
}

/// Mock for tests
class MockCanMerge extends MockDirCommand<bool> implements CanMerge {}
