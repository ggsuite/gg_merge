// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
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
    final remoteUrl = await readOriginUrl(
      directory: directory,
      processWrapper: _processWrapper,
    );
    if (remoteUrl == null) {
      throw Exception('git config failed: could not read remote.origin.url');
    }
    final provider = providerFromRemoteUrl(remoteUrl);
    switch (provider) {
      case GitProvider.github:
        await _createGitHubPR(
          directory,
          ggLog,
          automerge: automerge,
          deleteSourceBranch: deleteSourceBranch,
          message: message,
        );
        break;
      case GitProvider.azure:
        await _createAzureDevOpsPR(
          directory,
          ggLog,
          automerge: automerge,
          deleteSourceBranch: deleteSourceBranch,
          message: message,
        );
        break;
      case null:
        throw UnimplementedError('Unsupported git provider url: $remoteUrl');
    }
    return true;
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
    GgLog ggLog, {
    required bool automerge,
    required bool deleteSourceBranch,
    required String? message,
  }) async {
    // Reuse an existing OPEN PR for the current branch to stay idempotent.
    // Merged/closed PRs of the same branch (an earlier release of a reused
    // ticket branch) must not be reused: the wait-for-merge step would see
    // »merged« immediately although the new release content never made it
    // to main.
    final branch = await _currentBranch(directory);
    final existingUrl = await _gitHubOpenPrUrl(directory, branch);
    if (existingUrl != null) {
      // Surface the PR page so its status can be monitored directly.
      final urlHint = existingUrl.isEmpty ? '' : ' ${blue(existingUrl)}';
      ggLog('${darkGray('Reusing existing pull request:')}$urlHint');
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
      // gh prints the PR url — surface it so its status can be monitored
      // directly and a manual merge is one click away.
      final url = result.stdout.toString().trim();
      if (url.isNotEmpty) {
        ggLog('${darkGray('Created pull request:')} ${blue(url)}');
      }
    }

    // Merge if automerge
    if (automerge) {
      await _processWrapper.run(
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
      // A failing `gh pr merge --auto` is not an error: auto-merge can be
      // unavailable (repo setting "Allow auto-merge" off, squash merges
      // disabled, or no pending requirements). gg never merges such a pull
      // request on its own — the merge stays an explicit human decision.
      // The PR is left open and [WaitForMerge] blocks until it is merged
      // manually, asking the user for exactly that. Logging the reason here
      // would only duplicate that request.
    }
  }

  /// Returns the web url of an OPEN pull request for [branch], or null when
  /// no open PR exists (a new one must be created then). An unreadable
  /// `gh pr list` output is treated as "no open PR" — creating the PR then
  /// surfaces the actual problem with a precise error.
  Future<String?> _gitHubOpenPrUrl(Directory directory, String branch) async {
    final result = await _processWrapper.run(
      'gh',
      [
        'pr',
        'list',
        '--head',
        branch,
        '--state',
        'open',
        '--json',
        'url',
        '--limit',
        '1',
      ],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result.exitCode != 0) {
      return null;
    }
    try {
      final decoded = jsonDecode(result.stdout.toString().trim());
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        return (decoded.first as Map)['url']?.toString() ?? '';
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _createAzureDevOpsPR(
    Directory directory,
    GgLog ggLog, {
    required bool automerge,
    required bool deleteSourceBranch,
    required String? message,
  }) async {
    // The az cli must be installed.
    final branch = await _currentBranch(directory);
    var prId = await _existingAzurePrId(directory, branch);

    if (prId != null) {
      ggLog(darkGray('Reusing existing pull request !$prId for $branch.'));
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
        ggLog(darkGray('Created pull request !$prId for $branch.'));
      }
    }

    if (automerge) {
      // Without the pull request id auto-complete cannot be set. Like a
      // failing auto-merge on GitHub this is not an error: the PR stays open
      // and [WaitForMerge] asks the user to merge it.
      if (prId == null) {
        return;
      }
      await _setAzureAutoComplete(
        directory,
        prId,
        ggLog,
        deleteSourceBranch: deleteSourceBranch,
        message: message,
      );
    }
  }

  /// Extracts the pullRequestId from `az repos pr create` JSON output.
  /// An empty stdout throws the same [FormatException] as malformed JSON.
  String? _prIdFromCreateOutput(String stdout) {
    try {
      final decoded = jsonDecode(stdout.trim());
      return decoded is Map ? decoded['pullRequestId']?.toString() : null;
    } on FormatException {
      return null;
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

  /// Sets auto-complete on PR [id], always with the squash strategy and
  /// [message] as the merge commit message. When the policy rejects it (e.g.
  /// squash is forbidden) a warning is logged and the PR stays open for a
  /// manual merge.
  Future<void> _setAzureAutoComplete(
    Directory directory,
    String id,
    GgLog ggLog, {
    required bool deleteSourceBranch,
    required String? message,
  }) async {
    await _processWrapper.run(
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
    // A failing auto-complete leaves the pull request open for a manual
    // merge — [WaitForMerge] asks for it. No extra log needed here.
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
