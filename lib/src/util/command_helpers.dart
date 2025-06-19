// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Parses a string of format 'A B' (e.g., '3 2') to (behind, ahead) tuple.
(int behind, int ahead) parseGitAheadBehind(String output) {
  final trimmed = output.trim();
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length != 2) {
    throw FormatException('Could not parse behind/ahead output: $output');
  }
  final behind = int.tryParse(parts[0]) ?? 0;
  final ahead = int.tryParse(parts[1]) ?? 0;
  return (behind, ahead);
}

/// Supported git providers.
enum GitProvider {
  /// GitHub provider.
  github,

  /// Azure DevOps provider.
  azure
}

/// Determines the provider from the remote.origin.url
GitProvider? providerFromRemoteUrl(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('github.com')) {
    return GitProvider.github;
  }
  if (lower.contains('dev.azure.com') || lower.contains('visualstudio.com')) {
    return GitProvider.azure;
  }
  return null;
}
