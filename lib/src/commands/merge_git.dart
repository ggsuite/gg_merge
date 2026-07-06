// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';
import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:gg_process/gg_process.dart';
import '../util/command_helpers.dart';

/// Performs a merge/pull-request on GitHub or Azure DevOps.
class MergeGit extends DirCommand<bool> {
  /// Creates a [MergeGit] command
  MergeGit({
    required super.ggLog,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    super.name = 'merge-git',
    super.description =
        'Creates a PR (merge request) and can set automerge if enabled.',
  }) : _processWrapper = processWrapper {
    _addArgs();
  }

  final GgProcessWrapper _processWrapper;

  /// If --automerge is passed
  bool get _automergeOption => argResults?['automerge'] as bool? ?? false;

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Create merge request.',
      ggLog: ggLog,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog, automerge: automerge),
      success: (b) => b,
    );
  }

  /// Tries to create a PR/MR on supported git providers.
  ///
  /// Re-running is safe: when an open pull request already exists for the
  /// current branch it is reused instead of creating a duplicate. This keeps
  /// `gg do publish` resumable when a previous run was interrupted while
  /// waiting for the PR to be merged.
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
  }) async {
    automerge ??= _automergeOption;
    final remoteUrl = await _readOriginUrl(directory);
    final provider = providerFromRemoteUrl(remoteUrl);
    switch (provider) {
      case GitProvider.github:
        await _createGitHubPR(directory, automerge, ggLog);
        break;
      case GitProvider.azure:
        await _createAzureDevOpsPR(directory, automerge, ggLog);
        break;
      case null:
        throw UnimplementedError('Unsupported git provider url: $remoteUrl');
    }
    return true;
  }

  Future<String> _readOriginUrl(Directory directory) async {
    final result = await _processWrapper.run(
      'git',
      ['config', '--get', 'remote.origin.url'],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result.exitCode != 0) {
      throw Exception('git config failed: ${result.stderr}');
    }
    return result.stdout.toString().trim();
  }

  Future<String> _currentBranch(Directory directory) async {
    final result = await _processWrapper.run(
      'git',
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result.exitCode != 0) {
      throw Exception('git rev-parse failed: ${result.stderr}');
    }
    return result.stdout.toString().trim();
  }

  Future<void> _createGitHubPR(
    Directory directory,
    bool automerge,
    GgLog ggLog,
  ) async {
    // Reuse an existing PR for the current branch to stay idempotent.
    if (await _gitHubPrExists(directory)) {
      ggLog('Reusing existing pull request for the current branch.');
    } else {
      final result = await _processWrapper.run(
        'gh',
        ['pr', 'create', '--fill', '--web=false'],
        runInShell: true,
        workingDirectory: directory.path,
      );
      if (result.exitCode != 0) {
        throw Exception('gh pr create failed: ${result.stderr}');
      }
    }

    // Merge if automerge
    if (automerge) {
      final mergeResult = await _processWrapper.run(
        'gh',
        ['pr', 'merge', '--auto', '--delete-branch'],
        runInShell: true,
        workingDirectory: directory.path,
      );
      if (mergeResult.exitCode != 0) {
        throw Exception('gh pr merge failed: ${mergeResult.stderr}');
      }
    }
  }

  Future<bool> _gitHubPrExists(Directory directory) async {
    final result = await _processWrapper.run(
      'gh',
      ['pr', 'view', '--json', 'number'],
      runInShell: true,
      workingDirectory: directory.path,
    );
    return result.exitCode == 0;
  }

  Future<void> _createAzureDevOpsPR(
    Directory directory,
    bool automerge,
    GgLog ggLog,
  ) async {
    // The az cli must be installed.
    final branch = await _currentBranch(directory);
    final existingId = await _existingAzurePrId(directory, branch);

    if (existingId != null) {
      ggLog('Reusing existing pull request !$existingId for $branch.');
      if (automerge) {
        await _setAzureAutoComplete(directory, existingId);
      }
      return;
    }

    final result = await _processWrapper.run(
      'az',
      [
        'repos',
        'pr',
        'create',
        '--source-branch',
        'refs/heads/$branch',
        if (automerge) '--auto-complete',
        if (automerge) 'true',
        if (automerge) '--delete-source-branch',
        if (automerge) 'true',
      ],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result.exitCode != 0) {
      throw Exception('az repos pr create failed: ${result.stderr}');
    }
  }

  /// Returns the id of an active Azure DevOps PR for [branch], or null.
  Future<String?> _existingAzurePrId(Directory directory, String branch) async {
    final result = await _processWrapper.run(
      'az',
      [
        'repos',
        'pr',
        'list',
        '--source-branch',
        'refs/heads/$branch',
        '--status',
        'active',
        '--output',
        'json',
      ],
      runInShell: true,
      workingDirectory: directory.path,
    );
    // A failing lookup must not block PR creation; fall through to create.
    if (result.exitCode != 0) {
      return null;
    }
    final out = result.stdout.toString().trim();
    if (out.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(out);
    if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first;
      if (first is Map && first['pullRequestId'] != null) {
        return first['pullRequestId'].toString();
      }
    }
    return null;
  }

  Future<void> _setAzureAutoComplete(Directory directory, String id) async {
    final result = await _processWrapper.run(
      'az',
      [
        'repos',
        'pr',
        'update',
        '--id',
        id,
        '--auto-complete',
        'true',
        '--delete-source-branch',
        'true',
      ],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result.exitCode != 0) {
      throw Exception('az repos pr update failed: ${result.stderr}');
    }
  }

  void _addArgs() {
    argParser.addFlag(
      'automerge',
      abbr: 'a',
      help: 'Set PR/MR to automerge after CI.',
      negatable: true,
      defaultsTo: false,
    );
  }
}

/// Mock for unit tests
class MockMergeGit extends MockDirCommand<bool> implements MergeGit {}
