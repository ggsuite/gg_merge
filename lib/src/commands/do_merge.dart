// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:gg_merge/gg_merge.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';

/// Orchestrates check/merge.
class DoMerge extends DirCommand<bool> {
  /// Create a [DoMerge] command
  DoMerge({
    required super.ggLog,
    CanMerge? canMerge,
    MergeGit? mergeGit,
    LocalMerge? localMerge,
    super.name = 'do-merge',
    super.description = 'Checks pre-conditions and performs merge request/PR '
        '(optionally with automerge) or local merge with --local.',
    // coverage:ignore-start
  })  : _canMerge = canMerge ?? CanMerge(ggLog: ggLog),
        _mergeGit = mergeGit ?? MergeGit(ggLog: ggLog),
        _localMerge = localMerge ?? LocalMerge(ggLog: ggLog) {
    // coverage:ignore-end
    _addArgs();
  }

  final CanMerge _canMerge;
  final MergeGit _mergeGit;
  final LocalMerge _localMerge;

  String? get _messageOption => argResults?['message'] as String?;
  bool get _automergeOption => argResults?['automerge'] as bool? ?? false;
  bool get _localOption => argResults?['local'] as bool? ?? false;

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
    bool? local,
    String? message,
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Performing final merge.',
      ggLog: ggLog,
    ).logTask(
      task: () => get(
        directory: directory,
        ggLog: ggLog,
        automerge: automerge,
        local: local,
        message: message,
      ),
      success: (v) => v,
    );
  }

  /// Runs can-merge, then runs merge-git if allowed
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
    bool? local,
    String? message,
  }) async {
    automerge ??= _automergeOption;
    local ??= _localOption;
    message ??= _messageOption;

    if (local && automerge) {
      throw Exception('Automerge not supported for local merges.');
    }

    if (!local && message != null) {
      ggLog('Warning: --message is ignored for remote merges.');
    }

    final ok = await _canMerge.get(
      directory: directory,
      ggLog: ggLog,
    );
    if (!ok) {
      throw Exception('Not allowed to merge.');
    }

    if (local) {
      await _localMerge.get(
        directory: directory,
        ggLog: ggLog,
        message: message,
      );
      ggLog('✅ Local merge operation successfully completed.');
    } else {
      await _mergeGit.get(
        directory: directory,
        ggLog: ggLog,
        automerge: automerge,
      );
      ggLog('✅ Merge operation successfully started.');
    }
    return true;
  }

  void _addArgs() {
    argParser.addFlag(
      'automerge',
      abbr: 'a',
      help: 'Set PR/MR to automerge after CI.',
      negatable: true,
      defaultsTo: false,
    );
    argParser.addFlag(
      'local',
      abbr: 'l',
      help: 'Perform a local merge instead of remote PR/MR.',
      negatable: true,
      defaultsTo: false,
    );
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'Custom commit message for local squash merges.',
    );
  }
}

/// Mock for tests
class MockDoMerge extends MockDirCommand<bool> implements DoMerge {}
