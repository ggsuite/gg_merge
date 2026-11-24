// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';

import '../util/azure_urls.dart';
import '../util/command_helpers.dart';

/// Polls the pull request of the current branch until it has been merged.
///
/// Used after [MergeGit] created an auto-complete pull request: on providers
/// that forbid direct pushes to `main` (e.g. Azure DevOps branch policies) the
/// release cannot continue until the server merged the PR. This command blocks
/// — polling quickly at first, then in [pollInterval] steps (see
/// [pollDelay]) — until the PR is completed/merged. It throws when the PR
/// was abandoned/closed without merging, and when it cannot merge without
/// help: a merge conflict, a failed required check or policy, a branch that
/// must be brought up to date. Such a reason has to show in
/// [stuckPollsBeforeGivingUp] polls in a row: right after a push the
/// provider may still report the state of the commit before. A poll that
/// fails with a transient network error is simply repeated.
///
/// A pull request that only waits — for its checks to finish, for a review —
/// is waited for without a time limit: it merges once that is done.
///
/// A still-open pull request asks the user to merge it — once, together with
/// the pull request url. The polling itself stays silent from there on.
class WaitForMerge extends DirCommand<bool> {
  /// Creates a [WaitForMerge] command
  WaitForMerge({
    required super.ggLog,
    this._processWrapper = const GgProcessWrapper(),
    this._pollInterval = const Duration(seconds: 15),
    Future<void> Function(Duration)? delay,
    super.name = 'wait-for-merge',
    super.description = 'Wait until the pull request is merged',
  }) : _delay = delay ?? Future<void>.delayed;

  final GgProcessWrapper _processWrapper;
  final Duration _pollInterval;
  final Future<void> Function(Duration) _delay;

  /// The wait before the second poll, see [pollDelay].
  static const Duration firstPollDelay = Duration(seconds: 2);

  // ...........................................................................
  /// How long to wait before the next poll, after [polls] polls that found
  /// the pull request not merged yet.
  ///
  /// A pull request nothing holds back — no required checks, or checks that
  /// passed before — merges within seconds, so the first polls follow each
  /// other quickly: after 2 s, 4 s and 8 s. A pull request that is still
  /// open then is waiting for the server, and the poll interval is short
  /// enough from there on.
  Duration pollDelay(int polls) {
    // Beyond a few doublings the interval is reached anyway.
    if (polls > 16) {
      return _pollInterval;
    }
    final quick = firstPollDelay * (1 << polls);
    return quick < _pollInterval ? quick : _pollInterval;
  }

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
    Map<String, dynamic> options = const {},
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Waiting for pull request to be merged.',
      ggLog: ggLog,
      dark: true,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog),
      success: (v) => v,
    );
  }

  /// Blocks until the pull request of the current branch is merged.
  ///
  /// [branch] names the source branch of the pull request. Pass it whenever
  /// the caller knows it — HEAD may have moved on to the default branch by
  /// the time the wait starts (e.g. a merge that deleted the feature branch
  /// checked out main), and searching for a pull request of the default
  /// branch would fail with a misleading "no pull request found".
  ///
  /// [autoMerge] says the pull request completes itself once its policies
  /// pass. The wait then only *names* it — asking the user to merge a pull
  /// request that merges on its own sends them to do work that is not theirs.
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    String? branch,
    bool autoMerge = false,
  }) async {
    final remoteUrl = await readOriginUrl(
      directory: directory,
      processWrapper: _processWrapper,
    );
    if (remoteUrl == null) {
      throw Exception('git config failed: could not read remote.origin.url');
    }
    final provider = providerFromRemoteUrl(remoteUrl);
    branch ??= await _currentBranch(directory);
    switch (provider) {
      case GitProvider.github:
        return _waitGitHub(directory, branch, ggLog, autoMerge);
      case GitProvider.azure:
        return _waitAzure(directory, branch, ggLog, autoMerge);
      case null:
        throw UnimplementedError('Unsupported git provider url: $remoteUrl');
    }
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

  /// Names the pull request of [branch] and points to its web page.
  ///
  /// Without [autoMerge] the merge is the user's job, so this asks for it.
  /// An auto-merge pull request completes on its own — then the url is
  /// reported and nothing is asked, because there is nothing to do.
  ///
  /// Called once per wait, not on every poll: gg has no way to speed the
  /// merge up, so repeating the same line with every poll only buries the
  /// rest of the publish output.
  void _askToMerge(GgLog ggLog, String branch, String? url, bool autoMerge) {
    final target = url != null && url.isNotEmpty
        ? cCmd(url)
        : cCmd('the pull request of $branch');
    ggLog(
      autoMerge
          ? '${cDetail('Pull request:')} $target'
          : '${cAction('Please open and merge ')}$target',
    );
  }

  // ...........................................................................
  Future<bool> _waitAzure(
    Directory directory,
    String branch,
    GgLog ggLog,
    bool autoMerge,
  ) async {
    var asked = false;
    var stuckPolls = 0;
    for (var polls = 0; ; polls++) {
      final pr = await _azurePr(directory, branch, ggLog);
      final status = pr.status;
      if (status == 'completed') {
        ggLog(cDetail('✓ Pull request for $branch merged.'));
        return true;
      }
      if (status == 'abandoned') {
        throw Exception(cError('Pull request for $branch was abandoned.'));
      }
      if (status == null) {
        throw Exception(cError('No pull request found for branch $branch.'));
      }
      stuckPolls = _countStuck(
        stuckPolls,
        branch: branch,
        url: pr.url,
        // A merge that succeeds on the server leaves only the policies to
        // hold the pull request back — only then are they looked up.
        reason:
            _azureMergeStatusReason(pr.mergeStatus) ??
            (pr.mergeStatus == 'succeeded'
                ? await _azurePolicyReason(directory, pr.id)
                : null),
      );
      if (!asked) {
        asked = true;
        if (pr.url == null || pr.url!.isEmpty) {
          ggLog(
            cWarn(
              'Warning: Could not determine the Azure DevOps pull request '
              'URL because `az repos pr list` returned no usable repository '
              'metadata.',
            ),
          );
        }
        _askToMerge(ggLog, branch, pr.url, autoMerge);
      }
      await _delay(pollDelay(polls));
    }
  }

  Future<_AzurePr> _azurePr(
    Directory directory,
    String branch,
    GgLog ggLog,
  ) async {
    final result = await _listPullRequests(
      directory: directory,
      ggLog: ggLog,
      description: 'az repos pr list',
      executable: 'az',
      arguments: [
        'repos',
        'pr',
        'list',
        '--source-branch',
        'refs/heads/$branch',
        '--status',
        'all',
        '--output',
        'json',
      ],
    );
    // Pick the newest PR (highest id) matching the branch.
    Map<dynamic, dynamic>? newest;
    var newestId = -1;
    for (final entry in _jsonList(result.stdout) ?? const <dynamic>[]) {
      if (entry is Map && entry['pullRequestId'] is int) {
        final id = entry['pullRequestId'] as int;
        if (id > newestId) {
          newestId = id;
          newest = entry;
        }
      }
    }

    // `az` reports no web url of the pull request — the page is assembled
    // from the repository it does report, the same way the review does.
    final url = newest == null ? null : azurePullRequestWebUrl(newest);

    return (
      status: newest?['status']?.toString(),
      url: url,
      id: newest?['pullRequestId'] as int?,
      mergeStatus: newest?['mergeStatus']?.toString(),
    );
  }

  /// Why an Azure DevOps pull request with [mergeStatus] cannot merge, or
  /// null when nothing in it says so.
  ///
  /// `conflicts`, `failure` and `rejectedByPolicy` are final: the server does
  /// not retry the merge before somebody changed the branch or the policy.
  static String? _azureMergeStatusReason(String? mergeStatus) =>
      switch (mergeStatus) {
        'conflicts' => 'it has merge conflicts',
        'failure' => 'the merge failed',
        'rejectedByPolicy' => 'a branch policy rejected the merge',
        _ => null,
      };

  /// Why a blocking build or status policy of the Azure DevOps pull request
  /// [id] keeps it from merging, or null when none does.
  ///
  /// Only those two policy types count: their `rejected` is a failed run.
  /// Reviewer and comment policies report `rejected` as well while a vote or
  /// a resolved comment is missing — that is a review still to come, which
  /// is waited for. A policy that is running, queued or approved is no
  /// reason either. The policies are an extra lookup; when it fails the wait
  /// goes on — it only ends a hopeless wait early.
  Future<String?> _azurePolicyReason(Directory directory, int? id) async {
    if (id == null) {
      return null;
    }
    final result = await _processWrapper.run(
      'az',
      ['repos', 'pr', 'policy', 'list', '--id', '$id', '--output', 'json'],
      runInShell: true,
      workingDirectory: directory.path,
      environment: azCliEnvironment,
    );
    final evaluations = result.exitCode == 0 ? _jsonList(result.stdout) : null;
    final failed = [
      for (final evaluation in evaluations ?? const <dynamic>[])
        if (evaluation
            case {
              'status': 'rejected' || 'broken',
              'configuration':
                  {'isBlocking': true, 'type': {'id': final String typeId}} &&
                  final Map<dynamic, dynamic> configuration,
            }
            when _azureRunPolicyTypes.containsKey(typeId))
          '${switch (configuration['settings']) {
            {'displayName': final Object name} => name,
            _ => _azureRunPolicyTypes[typeId],
          }}',
    ];
    return failed.isEmpty
        ? null
        : 'a required policy failed: ${failed.join(', ')}';
  }

  /// The Azure DevOps policy types whose `rejected` means a failed run, by
  /// their fixed type id.
  static const _azureRunPolicyTypes = {
    '0609b952-1397-4640-95ec-e00a01b2c241': 'Build',
    'cbdc66da-9728-4af8-aada-9a5a32e4a226': 'Status',
  };

  /// The json array in [stdout], or null when it holds something else.
  static List<dynamic>? _jsonList(Object? stdout) {
    try {
      final decoded = jsonDecode('$stdout'.trim());
      return decoded is List ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Counts one more poll that found [reason] the pull request of [branch]
  /// cannot merge — or resets the count when there is none — and returns
  /// the new count. Throws once the reason showed in
  /// [stuckPollsBeforeGivingUp] polls in a row.
  static int _countStuck(
    int stuckPolls, {
    required String branch,
    required String? url,
    required String? reason,
  }) {
    if (reason == null) {
      return 0;
    }
    if (stuckPolls + 1 < stuckPollsBeforeGivingUp) {
      return stuckPolls + 1;
    }
    throw Exception(
      cError(
        'The pull request for $branch cannot be merged: $reason. '
        '${url == null || url.isEmpty ? '' : 'See $url. '}'
        'Fix it on the branch, then wait for the merge again.',
      ),
    );
  }

  // ...........................................................................
  Future<bool> _waitGitHub(
    Directory directory,
    String branch,
    GgLog ggLog,
    bool autoMerge,
  ) async {
    var asked = false;
    var closedPolls = 0;
    var stuckPolls = 0;
    for (var polls = 0; ; polls++) {
      final pr = await _gitHubPr(directory, branch, ggLog);
      final state = pr.state;
      if (state == 'MERGED' || (state == 'CLOSED' && pr.merged)) {
        ggLog(cDetail('✓ Pull request for $branch merged.'));
        return true;
      }
      if (state == 'CLOSED') {
        // GitHub reports a pull request its auto-merge just completed as
        // `CLOSED` for a moment — `mergedAt` still empty — before it turns
        // `MERGED`. One such poll is no abandoned pull request; only a
        // `CLOSED` that stays through [closedPollsBeforeGivingUp] polls is.
        closedPolls++;
        if (closedPolls >= closedPollsBeforeGivingUp) {
          throw Exception(
            'Pull request for $branch was closed without merging.',
          );
        }
        await _delay(pollDelay(polls));
        continue;
      }
      closedPolls = 0;
      if (state == null) {
        throw Exception('No pull request found for branch $branch.');
      }
      stuckPolls = _countStuck(
        stuckPolls,
        branch: branch,
        url: pr.url,
        reason:
            _gitHubMergeStateReason(
              mergeable: pr.mergeable,
              mergeStateStatus: pr.mergeStateStatus,
            ) ??
            (pr.mergeStateStatus == 'BLOCKED'
                ? await _gitHubRequiredCheckReason(directory, branch)
                : null),
      );
      if (!asked) {
        asked = true;
        _askToMerge(ggLog, branch, pr.url, autoMerge);
      }
      await _delay(pollDelay(polls));
    }
  }

  /// Why an open GitHub pull request cannot merge without help, as far as
  /// its [mergeable] and [mergeStateStatus] tell, or null when they do not.
  ///
  /// - `CONFLICTING` / `DIRTY`: the branch conflicts with its base.
  /// - `BEHIND`: the branch protection wants the branch up to date with its
  ///   base, and auto-merge does not update it.
  ///
  /// `BLOCKED` is decided by the required checks (see
  /// [_gitHubRequiredCheckReason]); everything else — `UNKNOWN` not computed
  /// yet, `UNSTABLE` with a failed optional check — is waited for.
  static String? _gitHubMergeStateReason({
    required String? mergeable,
    required String? mergeStateStatus,
  }) {
    if (mergeable == 'CONFLICTING' || mergeStateStatus == 'DIRTY') {
      return 'it has merge conflicts';
    }
    if (mergeStateStatus == 'BEHIND') {
      return 'it is behind its base branch and has to be updated';
    }
    return null;
  }

  /// Why a required check keeps the pull request of [branch] from merging —
  /// the names of the required checks that failed — or null when none did.
  ///
  /// `gh pr checks --required` lists only the checks the branch protection
  /// requires, the latest run of each: a failed optional check, or a run
  /// cancelled and replaced by a newer one, is no reason. A pending check is
  /// waited for. When the lookup fails the wait goes on — it only ends a
  /// hopeless wait early.
  Future<String?> _gitHubRequiredCheckReason(
    Directory directory,
    String branch,
  ) async {
    final result = await _processWrapper.run(
      'gh',
      ['pr', 'checks', branch, '--required', '--json', 'name,bucket'],
      runInShell: true,
      workingDirectory: directory.path,
    );
    // `gh pr checks` ends with 1 when a check failed and 8 while one is
    // pending — the json it prints is valid either way.
    final failed = [
      for (final check in _jsonList(result.stdout) ?? const <dynamic>[])
        if (check is Map && check['bucket'] == 'fail') '${check['name']}',
    ];
    return failed.isEmpty
        ? null
        : 'a required check failed: ${failed.join(', ')}';
  }

  /// How many polls in a row must show a reason the pull request cannot
  /// merge before the wait gives up: right after a push the provider may
  /// still report the state of the commit before.
  static const int stuckPollsBeforeGivingUp = 3;

  /// How many consecutive `CLOSED` polls a GitHub pull request may show
  /// before it counts as closed without merging — see [_waitGitHub].
  static const int closedPollsBeforeGivingUp = 4;

  /// How many polls in a row may fail with a transient network error before
  /// the wait gives up — see [_listPullRequests].
  static const int failedPollsBeforeGivingUp = 10;

  // ...........................................................................
  /// Runs the pull request lookup [executable] [arguments] and returns its
  /// successful result.
  ///
  /// A failed lookup is one missed poll, not a failed merge: the pull request
  /// keeps merging on the server while DNS or the connection hiccups, and
  /// aborting then leaves a publish to resume by hand. So a transient network
  /// error ([GitRetry.isTransient]) waits one poll interval and asks again,
  /// up to [failedPollsBeforeGivingUp] times in a row. Anything else — no
  /// login, an unknown repository — fails at once.
  Future<ProcessResult> _listPullRequests({
    required Directory directory,
    required GgLog ggLog,
    required String description,
    required String executable,
    required List<String> arguments,
  }) async {
    for (var failed = 1; ; failed++) {
      final result = await _processWrapper.run(
        executable,
        arguments,
        runInShell: true,
        workingDirectory: directory.path,
        environment: executable == 'az' ? azCliEnvironment : null,
      );
      if (result.exitCode == 0) {
        return result;
      }
      if (!GitRetry.isTransient('${result.stderr}') ||
          failed >= failedPollsBeforeGivingUp) {
        throw Exception('$description failed: ${result.stderr}');
      }
      ggLog(
        cDetail(
          '$description failed with a transient network error. '
          'Polling again in ${_pollInterval.inSeconds}s '
          '(attempt ${failed + 1} of $failedPollsBeforeGivingUp).',
        ),
      );
      await _delay(_pollInterval);
    }
  }

  /// The state of the pull request of [branch]: its `state`, its web url,
  /// whether GitHub has a merge date for it — a `CLOSED` pull request with
  /// one was merged, whatever the state says — and what
  /// [_gitHubMergeStateReason] needs to tell whether it can still merge.
  Future<_GitHubPr> _gitHubPr(
    Directory directory,
    String branch,
    GgLog ggLog,
  ) async {
    final result = await _listPullRequests(
      directory: directory,
      ggLog: ggLog,
      description: 'gh pr list',
      executable: 'gh',
      arguments: [
        'pr',
        'list',
        '--head',
        branch,
        '--state',
        'all',
        '--json',
        'state,url,mergedAt,mergeable,mergeStateStatus',
        '--limit',
        '1',
      ],
    );
    final first = _jsonList(result.stdout)?.firstOrNull;
    if (first is! Map) {
      return (
        state: null,
        url: null,
        merged: false,
        mergeable: null,
        mergeStateStatus: null,
      );
    }
    final mergedAt = first['mergedAt']?.toString() ?? '';
    return (
      state: first['state']?.toString(),
      url: first['url']?.toString(),
      merged: mergedAt.isNotEmpty && mergedAt != 'null',
      mergeable: first['mergeable']?.toString(),
      mergeStateStatus: first['mergeStateStatus']?.toString(),
    );
  }
}

/// An Azure DevOps pull request as [WaitForMerge] polls it.
typedef _AzurePr = ({
  String? status,
  String? url,
  int? id,
  String? mergeStatus,
});

/// A GitHub pull request as [WaitForMerge] polls it.
typedef _GitHubPr = ({
  String? state,
  String? url,
  bool merged,
  String? mergeable,
  String? mergeStateStatus,
});

/// Mock for unit tests
class MockWaitForMerge extends MockDirCommand<bool> implements WaitForMerge {}
