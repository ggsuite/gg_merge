// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';
import 'package:gg_args/gg_args.dart';
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
class WaitForMerge extends DirCommand<bool> {
  /// Creates a [WaitForMerge] command
  WaitForMerge({
    required super.ggLog,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    Duration pollInterval = const Duration(seconds: 15),
    Future<void> Function(Duration)? delay,
    super.name = 'wait-for-merge',
    super.description =
        'Waits until the pull request of the current branch is merged.',
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
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Waiting for pull request to be merged.',
      ggLog: ggLog,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog),
      success: (v) => v,
    );
  }

  /// Blocks until the pull request of the current branch is merged.
  @override
  Future<bool> get({required Directory directory, required GgLog ggLog}) async {
    final remoteUrl = await _readOriginUrl(directory);
    final provider = providerFromRemoteUrl(remoteUrl);
    final branch = await _currentBranch(directory);
    switch (provider) {
      case GitProvider.github:
        return _waitGitHub(directory, branch, ggLog);
      case GitProvider.azure:
        return _waitAzure(directory, branch, ggLog);
      case null:
        throw UnimplementedError('Unsupported git provider url: $remoteUrl');
    }
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

  // ...........................................................................
  Future<bool> _waitAzure(
    Directory directory,
    String branch,
    GgLog ggLog,
  ) async {
    while (true) {
      final status = await _azurePrStatus(directory, branch);
      if (status == 'completed') {
        ggLog('✅ Pull request for $branch merged.');
        return true;
      }
      if (status == 'abandoned') {
        throw Exception('Pull request for $branch was abandoned.');
      }
      if (status == null) {
        throw Exception('No pull request found for branch $branch.');
      }
      ggLog(
        '⌛️ Waiting for pull request ($branch) to be merged '
        '(status: $status)...',
      );
      await _delay(_pollInterval);
    }
  }

  Future<String?> _azurePrStatus(Directory directory, String branch) async {
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
      return null;
    }
    final decoded = jsonDecode(out);
    if (decoded is! List || decoded.isEmpty) {
      return null;
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
    return newest?['status']?.toString();
  }

  // ...........................................................................
  Future<bool> _waitGitHub(
    Directory directory,
    String branch,
    GgLog ggLog,
  ) async {
    while (true) {
      final state = await _gitHubPrState(directory, branch);
      if (state == 'MERGED') {
        ggLog('✅ Pull request for $branch merged.');
        return true;
      }
      if (state == 'CLOSED') {
        throw Exception('Pull request for $branch was closed without merging.');
      }
      if (state == null) {
        throw Exception('No pull request found for branch $branch.');
      }
      ggLog(
        '⌛️ Waiting for pull request ($branch) to be merged '
        '(state: $state)...',
      );
      await _delay(_pollInterval);
    }
  }

  Future<String?> _gitHubPrState(Directory directory, String branch) async {
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
        'state',
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
      return null;
    }
    final decoded = jsonDecode(out);
    if (decoded is! List || decoded.isEmpty) {
      return null;
    }
    final first = decoded.first;
    if (first is Map) {
      return first['state']?.toString();
    }
    return null;
  }
}

/// Mock for unit tests
class MockWaitForMerge extends MockDirCommand<bool> implements WaitForMerge {}
