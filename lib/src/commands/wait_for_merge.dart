// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';

import '../util/command_helpers.dart';

/// Polls the pull request of the current branch until it has been merged.
///
/// Used after [MergeGit] created an auto-complete pull request: on providers
/// that forbid direct pushes to `main` (e.g. Azure DevOps branch policies) the
/// release cannot continue until the server merged the PR. This command blocks
/// — polling in [pollInterval] steps — until the PR is completed/merged. It
/// throws when the PR was abandoned/closed without merging.
///
/// A still-open pull request asks the user to merge it — once, together with
/// the pull request url. The polling itself stays silent from there on.
class WaitForMerge extends DirCommand<bool> {
  /// Creates a [WaitForMerge] command
  WaitForMerge({
    required super.ggLog,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    Duration pollInterval = const Duration(seconds: 15),
    Future<void> Function(Duration)? delay,
    super.name = 'wait-for-merge',
    super.description = 'Wait until the pull request is merged',
  }) : _processWrapper = processWrapper,
       _pollInterval = pollInterval,
       _delay = delay ?? Future<void>.delayed;

  final GgProcessWrapper _processWrapper;
  final Duration _pollInterval;
  final Future<void> Function(Duration) _delay;

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
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    String? branch,
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
        return _waitGitHub(directory, branch, ggLog);
      case GitProvider.azure:
        return _waitAzure(directory, branch, ggLog);
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

  /// Asks the user to merge the pull request of [branch] and points to its
  /// web page, so the merge can be done right away in the browser.
  ///
  /// Called once per wait, not on every poll: gg has no way to speed the
  /// merge up, so repeating the same request every [pollInterval] only
  /// buries the rest of the publish output.
  void _askToMerge(GgLog ggLog, String branch, String? url) {
    final target = url != null && url.isNotEmpty
        ? cCmd(url)
        : 'the pull request of $branch';
    ggLog('${cAction('Please open and merge ')}$target');
  }

  // ...........................................................................
  Future<bool> _waitAzure(
    Directory directory,
    String branch,
    GgLog ggLog,
  ) async {
    var asked = false;
    while (true) {
      final pr = await _azurePr(directory, branch);
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
      if (!asked) {
        asked = true;
        _askToMerge(ggLog, branch, pr.url);
      }
      await _delay(_pollInterval);
    }
  }

  Future<({String? status, String? url})> _azurePr(
    Directory directory,
    String branch,
  ) async {
    final result = await _processWrapper.run(
      'az',
      [
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
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result.exitCode != 0) {
      throw Exception('az repos pr list failed: ${result.stderr}');
    }
    final out = result.stdout.toString().trim();
    if (out.isEmpty) {
      return (status: null, url: null);
    }
    final decoded = jsonDecode(out);
    if (decoded is! List || decoded.isEmpty) {
      return (status: null, url: null);
    }
    // Pick the newest PR (highest id) matching the branch.
    Map<dynamic, dynamic>? newest;
    var newestId = -1;
    for (final entry in decoded) {
      if (entry is Map && entry['pullRequestId'] is int) {
        final id = entry['pullRequestId'] as int;
        if (id > newestId) {
          newestId = id;
          newest = entry;
        }
      }
    }

    // The web page of the PR: <repository.webUrl>/pullrequest/<id>.
    final repository = newest?['repository'];
    final webUrl = repository is Map ? repository['webUrl']?.toString() : null;
    final url = (webUrl == null || newest == null)
        ? null
        : '$webUrl/pullrequest/${newest['pullRequestId']}';

    return (status: newest?['status']?.toString(), url: url);
  }

  // ...........................................................................
  Future<bool> _waitGitHub(
    Directory directory,
    String branch,
    GgLog ggLog,
  ) async {
    var asked = false;
    while (true) {
      final pr = await _gitHubPr(directory, branch);
      final state = pr.state;
      if (state == 'MERGED') {
        ggLog(cDetail('✓ Pull request for $branch merged.'));
        return true;
      }
      if (state == 'CLOSED') {
        throw Exception('Pull request for $branch was closed without merging.');
      }
      if (state == null) {
        throw Exception('No pull request found for branch $branch.');
      }
      if (!asked) {
        asked = true;
        _askToMerge(ggLog, branch, pr.url);
      }
      await _delay(_pollInterval);
    }
  }

  Future<({String? state, String? url})> _gitHubPr(
    Directory directory,
    String branch,
  ) async {
    final result = await _processWrapper.run(
      'gh',
      [
        'pr',
        'list',
        '--head',
        branch,
        '--state',
        'all',
        '--json',
        'state,url',
        '--limit',
        '1',
      ],
      runInShell: true,
      workingDirectory: directory.path,
    );
    if (result.exitCode != 0) {
      throw Exception('gh pr list failed: ${result.stderr}');
    }
    final out = result.stdout.toString().trim();
    if (out.isEmpty) {
      return (state: null, url: null);
    }
    final decoded = jsonDecode(out);
    if (decoded is! List || decoded.isEmpty) {
      return (state: null, url: null);
    }
    final first = decoded.first;
    if (first is Map) {
      return (state: first['state']?.toString(), url: first['url']?.toString());
    }
    return (state: null, url: null);
  }
}

/// Mock for unit tests
class MockWaitForMerge extends MockDirCommand<bool> implements WaitForMerge {}
