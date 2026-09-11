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
import 'package:gg_status_printer/gg_status_printer.dart';

import 'has_local_references.dart';
import 'is_ahead_main.dart';
import 'is_behind_main.dart';
import 'update_project_git.dart';
import '../util/command_helpers.dart';

/// Determines if merging is allowed according to project rules.
class CanMerge extends DirCommand<bool> {
  /// Create a [CanMerge] command
  CanMerge({
    required super.ggLog,
    HasLocalReferences? hasLocalReferences,
    IsBehindMain? isBehindMain,
    IsAheadMain? isAheadMain,
    UpdateProjectGit? updateProjectGit,
    DefaultBranch? defaultBranch,
    super.name = 'can-merge',
    super.description =
        'Checks if merging into the default branch is allowed '
        'according to rules.',
    // coverage:ignore-start
  }) : _hasLocalReferences =
           hasLocalReferences ?? HasLocalReferences(ggLog: ggLog),
       _isBehindMain = isBehindMain ?? IsBehindMain(ggLog: ggLog),
       _isAheadMain = isAheadMain ?? IsAheadMain(ggLog: ggLog),
       _updateProjectGit = updateProjectGit ?? UpdateProjectGit(ggLog: ggLog),
       _defaultBranch = defaultBranch ?? DefaultBranch(ggLog: ggLog);
  // coverage:ignore-end

  final HasLocalReferences _hasLocalReferences;
  final IsBehindMain _isBehindMain;
  final IsAheadMain _isAheadMain;
  final UpdateProjectGit _updateProjectGit;
  final DefaultBranch _defaultBranch;

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
    Map<String, dynamic> options = const {},
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
  ///
  /// [mainBranch] names the branch the merge targets. Without it the
  /// repository's default branch is used (`origin/HEAD`, else `main`, else
  /// `master`). The name is resolved once and handed to the behind/ahead
  /// checks.
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    String? mainBranch,
  }) async {
    await _updateProjectGit.get(directory: directory, ggLog: ggLog);
    if (await _hasLocalReferences.get(directory: directory, ggLog: ggLog)) {
      throw Exception(
        'Local references found in the package manifest '
        '(pubspec.yaml path: / package.json file:|link:|workspace:).',
      );
    }
    final branch = await resolveMainBranch(
      defaultBranch: _defaultBranch,
      directory: directory,
      ggLog: ggLog,
      mainBranch: mainBranch,
    );
    final isBehind = await _isBehindMain.get(
      directory: directory,
      ggLog: ggLog,
      mainBranch: branch,
    );
    if (isBehind) {
      throw Exception(
        'Current branch is behind $branch. '
        'Please rebase or merge $branch first.',
      );
    }
    final isAhead = await _isAheadMain.get(
      directory: directory,
      ggLog: ggLog,
      mainBranch: branch,
    );
    if (!isAhead) {
      throw Exception(
        'Branch is not ahead of $branch; there is nothing to merge.',
      );
    }
    ggLog(cDetail('✓ All merge conditions fulfilled.'));
    return true;
  }
}

/// Mock for tests
class MockCanMerge extends MockDirCommand<bool> implements CanMerge {}
