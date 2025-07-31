// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_merge/src/commands/has_local_references.dart';
import 'package:gg_merge/src/commands/has_git_references.dart';
import 'package:gg_merge/src/commands/is_behind_main.dart';
import 'package:gg_merge/src/commands/is_ahead_main.dart';
import 'package:gg_merge/src/commands/update_project_git.dart';
import 'package:gg_merge/src/commands/merge_git.dart';
import 'package:gg_merge/src/commands/can_merge.dart';
import 'package:gg_merge/src/commands/do_merge.dart';
import 'package:gg_merge/src/commands/local_merge.dart';

/// The root command for git merge automation and publication
class GgMerge extends Command<dynamic> {
  /// Creates a [GgMerge] command with all subcommands
  GgMerge({required this.ggLog}) {
    addSubcommand(HasLocalReferences(ggLog: ggLog));
    addSubcommand(HasGitReferences(ggLog: ggLog));
    addSubcommand(IsBehindMain(ggLog: ggLog));
    addSubcommand(IsAheadMain(ggLog: ggLog));
    addSubcommand(UpdateProjectGit(ggLog: ggLog));
    addSubcommand(MergeGit(ggLog: ggLog));
    addSubcommand(CanMerge(ggLog: ggLog));
    addSubcommand(DoMerge(ggLog: ggLog));
    addSubcommand(LocalMerge(ggLog: ggLog));
  }

  /// The log function
  final GgLog ggLog;

  // ...........................................................................
  @override
  final String name = 'ggMerge';
  @override
  final String description = 'Git merge helper and publishing toolbox.';
}
