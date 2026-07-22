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

  /// If --delete-source-branch is passed (default true)
  bool get _deleteSourceBranchOption =>
      argResults?['delete-source-branch'] as bool? ?? true;

  /// The --message option
  String? get _messageOption => argResults?['message'] as String?;

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
    bool? deleteSourceBranch,
    String? message,
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Create merge request.',
      ggLog: ggLog,
    ).logTask(
      task: () => get(
        directory: directory,
        ggLog: ggLog,
        automerge: automerge,
        deleteSourceBranch: deleteSourceBranch,
        message: message,
      ),
      success: (b) => b,
    );
  }

  /// Tries to create a PR/MR on supported git providers.
  ///
  /// Re-running is safe: when an open pull request already exists for the
  /// current branch it is reused instead of creating a duplicate. This keeps
  /// `gg do publish` resumable when a previous run was interrupted while
  /// waiting for the PR to be merged.
  ///
  /// [deleteSourceBranch] controls whether the provider deletes the source
  /// branch when it completes the pull request (default true).
  ///
  /// [message] becomes the pull-request title and the squash merge commit
  /// message. The merge always uses the squash strategy.
  ///
  /// Enabling automerge is best-effort: when the provider rejects it (e.g.
  /// GitHub's "Allow auto-merge" is off, or an Azure policy forbids the
  /// squash strategy) the PR stays open and a warning is logged instead of
  /// failing — [WaitForMerge] still completes once the PR is merged manually.
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
    bool? deleteSourceBranch,
    String? message,
  }) async {
    automerge ??= _automergeOption;
    deleteSourceBranch ??= _deleteSourceBranchOption;
    message ??= _messageOption;
    final remoteUrl = await _readOriginUrl(directory);
    final provider = providerFromRemoteUrl(remoteUrl);
    switch (provider) {
      case GitProvider.github:
        await _createGitHubPR(
          directory,
          automerge,
          deleteSourceBranch,
          message,
          ggLog,
        );
        break;
      case GitProvider.azure:
        await _createAzureDevOpsPR(
          directory,
          automerge,
          deleteSourceBranch,
          message,
          ggLog,
        );
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
    bool deleteSourceBranch,
    String? message,
    GgLog ggLog,
  ) async {
    // Reuse an existing PR for the current branch to stay idempotent.
    if (await _gitHubPrExists(directory)) {
      ggLog('Reusing existing pull request for the current branch.');
    } else {
      final result = await _processWrapper.run(
        'gh',
        [
          'pr',
          'create',
          // The merge message becomes title and body; without one gh derives
          // both from the commits (--fill).
          if (message != null) ...['--title', message, '--body', message],
          if (message == null) '--fill',
          '--web=false',
        ],
        runInShell: true,
        workingDirectory: directory.path,
      );
      if (result.exitCode != 0) {
        throw Exception('gh pr create failed: ${result.stderr}');
      }
      // gh prints the PR url — surface it so a manual merge is one click away.
      final url = result.stdout.toString().trim();
      if (url.isNotEmpty) {
        ggLog('Created pull request: $url');
      }
    }

    // Merge if automerge
    if (automerge) {
      final mergeResult = await _processWrapper.run(
        'gh',
        [
          'pr',
          'merge',
          '--auto',
          '--squash',
          if (message != null) ...['--subject', message],
          if (deleteSourceBranch) '--delete-branch',
        ],
        runInShell: true,
        workingDirectory: directory.path,
      );
      if (mergeResult.exitCode != 0) {
        // Auto-merge can be unavailable (repo setting "Allow auto-merge" off,
        // squash merges disabled, or no pending requirements). The PR stays
        // open and the publish keeps waiting — merge it on GitHub to continue.
        ggLog(
          '⚠️ Could not enable auto-merge '
          '(${mergeResult.stderr.toString().trim()}). '
          'The pull request stays open — merge it on GitHub; '
          'the publish waits for the merge.',
        );
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
    bool deleteSourceBranch,
    String? message,
    GgLog ggLog,
  ) async {
    // The az cli must be installed.
    final branch = await _currentBranch(directory);
    var prId = await _existingAzurePrId(directory, branch);

    if (prId != null) {
      ggLog('Reusing existing pull request !$prId for $branch.');
    } else {
      // Create the PR plain and set auto-complete separately: completion
      // options on `az repos pr create` fail as a whole when the policy
      // rejects the merge strategy, which would leave no PR at all.
      final result = await _processWrapper.run(
        'az',
        [
          'repos',
          'pr',
          'create',
          '--source-branch',
          'refs/heads/$branch',
          if (message != null) ...['--title', message],
        ],
        runInShell: true,
        workingDirectory: directory.path,
      );
      if (result.exitCode != 0) {
        throw Exception('az repos pr create failed: ${result.stderr}');
      }
      prId = _prIdFromCreateOutput(result.stdout.toString());
      if (prId != null) {
        ggLog('Created pull request !$prId for $branch.');
      }
    }

    if (automerge) {
      if (prId == null) {
        ggLog(
          '⚠️ Could not determine the pull request id — auto-complete was '
          'not set. Merge the pull request on Azure DevOps; the publish '
          'waits for the merge.',
        );
        return;
      }
      await _setAzureAutoComplete(
        directory,
        prId,
        deleteSourceBranch,
        message,
        ggLog,
      );
    }
  }

  /// Extracts the pullRequestId from `az repos pr create` JSON output.
  String? _prIdFromCreateOutput(String stdout) {
    final out = stdout.trim();
    if (out.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(out);
      if (decoded is Map && decoded['pullRequestId'] != null) {
        return decoded['pullRequestId'].toString();
      }
    } on FormatException {
      return null;
    }
    return null;
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

  /// Sets auto-complete on PR [id], always with the squash strategy and
  /// [message] as the merge commit message. When the policy rejects it (e.g.
  /// squash is forbidden) a warning is logged and the PR stays open for a
  /// manual merge.
  Future<void> _setAzureAutoComplete(
    Directory directory,
    String id,
    bool deleteSourceBranch,
    String? message,
    GgLog ggLog,
  ) async {
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
        '--squash',
        'true',
        if (deleteSourceBranch) ...['--delete-source-branch', 'true'],
        if (message != null) ...['--merge-commit-message', message],
      ],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result.exitCode == 0) {
      return;
    }

    ggLog(
      '⚠️ Could not enable auto-complete '
      '(${result.stderr.toString().trim()}). '
      'The pull request stays open — merge it on Azure DevOps; '
      'the publish waits for the merge.',
    );
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
      'delete-source-branch',
      help: 'Let the provider delete the source branch after the merge.',
      negatable: true,
      defaultsTo: true,
    );
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'The pull-request title and squash merge commit message.',
    );
  }
}

/// Mock for unit tests
class MockMergeGit extends MockDirCommand<bool> implements MergeGit {}
