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

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
    bool? deleteSourceBranch,
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
  /// Enabling automerge is best-effort: when the provider rejects it (e.g.
  /// GitHub's "Allow auto-merge" is off, or an Azure policy forbids every
  /// strategy the CLI can request) the PR stays open and a warning is logged
  /// instead of failing — [WaitForMerge] still completes once the PR is
  /// merged manually.
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
    bool? deleteSourceBranch,
  }) async {
    automerge ??= _automergeOption;
    deleteSourceBranch ??= _deleteSourceBranchOption;
    final remoteUrl = await _readOriginUrl(directory);
    final provider = providerFromRemoteUrl(remoteUrl);
    switch (provider) {
      case GitProvider.github:
        await _createGitHubPR(directory, automerge, deleteSourceBranch, ggLog);
        break;
      case GitProvider.azure:
        await _createAzureDevOpsPR(
          directory,
          automerge,
          deleteSourceBranch,
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
      // gh prints the PR url — surface it so a manual merge is one click away.
      final url = result.stdout.toString().trim();
      if (url.isNotEmpty) {
        ggLog('Created pull request: $url');
      }
    }

    // Merge if automerge
    if (automerge) {
      final methodFlag = await _gitHubMergeMethodFlag(directory);
      final mergeResult = await _processWrapper.run(
        'gh',
        [
          'pr',
          'merge',
          '--auto',
          methodFlag,
          if (deleteSourceBranch) '--delete-branch',
        ],
        runInShell: true,
        workingDirectory: directory.path,
      );
      if (mergeResult.exitCode != 0) {
        // Auto-merge can be unavailable (repo setting "Allow auto-merge" off,
        // or no pending requirements). The PR stays open and the publish
        // keeps waiting — merge it on GitHub to continue.
        ggLog(
          '⚠️ Could not enable auto-merge '
          '(${mergeResult.stderr.toString().trim()}). '
          'The pull request stays open — merge it on GitHub; '
          'the publish waits for the merge.',
        );
      }
    }
  }

  /// Returns the `gh pr merge` method flag allowed by the repository,
  /// preferring a merge commit over squash over rebase. Falls back to
  /// `--merge` when the settings cannot be read.
  Future<String> _gitHubMergeMethodFlag(Directory directory) async {
    final result = await _processWrapper.run(
      'gh',
      [
        'repo',
        'view',
        '--json',
        'mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed',
      ],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result.exitCode != 0) {
      return '--merge';
    }
    try {
      final decoded = jsonDecode(result.stdout.toString().trim());
      if (decoded is Map) {
        if (decoded['mergeCommitAllowed'] == true) return '--merge';
        if (decoded['squashMergeAllowed'] == true) return '--squash';
        if (decoded['rebaseMergeAllowed'] == true) return '--rebase';
      }
    } on FormatException {
      // Fall through to the default below.
    }
    return '--merge';
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
        ['repos', 'pr', 'create', '--source-branch', 'refs/heads/$branch'],
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
      await _setAzureAutoComplete(directory, prId, deleteSourceBranch, ggLog);
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

  /// Sets auto-complete on PR [id]. Azure branch policies can restrict the
  /// allowed merge strategy; the CLI only exposes squash vs. the default
  /// no-fast-forward merge, so the default is tried first and a policy
  /// rejection ("merge strategy … not allowed") is retried with
  /// `--squash true`. When no strategy is accepted a warning is logged and
  /// the PR stays open for a manual merge.
  Future<void> _setAzureAutoComplete(
    Directory directory,
    String id,
    bool deleteSourceBranch,
    GgLog ggLog,
  ) async {
    List<String> args({required bool squash}) => [
      'repos',
      'pr',
      'update',
      '--id',
      id,
      '--auto-complete',
      'true',
      if (deleteSourceBranch) ...['--delete-source-branch', 'true'],
      if (squash) ...['--squash', 'true'],
    ];

    final first = await _processWrapper.run(
      'az',
      args(squash: false),
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (first.exitCode == 0) {
      return;
    }

    var stderr = first.stderr.toString();
    if (_isMergeStrategyRejection(stderr)) {
      ggLog('Merge strategy rejected by policy — retrying with squash.');
      final second = await _processWrapper.run(
        'az',
        args(squash: true),
        runInShell: true,
        workingDirectory: directory.path,
      );
      if (second.exitCode == 0) {
        return;
      }
      stderr = second.stderr.toString();
    }

    ggLog(
      '⚠️ Could not enable auto-complete (${stderr.trim()}). '
      'The pull request stays open — merge it on Azure DevOps; '
      'the publish waits for the merge.',
    );
  }

  /// Whether [stderr] indicates that the requested merge strategy is
  /// forbidden by a branch policy. Matched loosely because the server
  /// message is not stable (it even contains typos like "not alowed").
  bool _isMergeStrategyRejection(String stderr) =>
      stderr.toLowerCase().contains('merge strategy');

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
  }
}

/// Mock for unit tests
class MockMergeGit extends MockDirCommand<bool> implements MergeGit {}
