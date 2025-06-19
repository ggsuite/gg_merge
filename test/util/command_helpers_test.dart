// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:test/test.dart';
import 'package:gg_merge/src/util/command_helpers.dart';

void main() {
  group('parseGitAheadBehind', () {
    test('parses string of format "A B" into tuple of ints', () {
      expect(parseGitAheadBehind('3 2'), (3, 2));
      expect(parseGitAheadBehind('0 0'), (0, 0));
      expect(parseGitAheadBehind('10 5'), (10, 5));
      expect(parseGitAheadBehind('   1   4   '), (1, 4));
    });
    test('throws FormatException for invalid input', () {
      expect(() => parseGitAheadBehind(''), throwsA(isA<FormatException>()));
      expect(
        () => parseGitAheadBehind('onlyone'),
        throwsA(isA<FormatException>()),
      );
      expect(() => parseGitAheadBehind('a b'), returnsNormally);
    });
    test('returns 0 if cannot parse int', () {
      expect(parseGitAheadBehind('x 1'), (0, 1));
      expect(parseGitAheadBehind('2 x'), (2, 0));
    });
    // Additional edge cases
    test('parses negative ints correctly', () {
      expect(parseGitAheadBehind(' -3  7 '), (-3, 7));
      expect(parseGitAheadBehind('-2 -5'), (-2, -5));
    });
    test('parses tabs and mixed whitespace', () {
      expect(parseGitAheadBehind('2\t9'), (2, 9));
      expect(parseGitAheadBehind('  2\t  9\n'), (2, 9));
    });
    test('parses irrelevant string as 0s', () {
      expect(parseGitAheadBehind('foo bar'), (0, 0));
      expect(parseGitAheadBehind('foo 1'), (0, 1));
    });
  });

  group('providerFromRemoteUrl', () {
    test('detects GitHub urls', () {
      expect(
        providerFromRemoteUrl('https://github.com/abc/def.git'),
        GitProvider.github,
      );
      expect(
        providerFromRemoteUrl('git@github.com:abc/def.git'),
        GitProvider.github,
      );
      expect(
        providerFromRemoteUrl('GITHUB.com/abc/def.git'),
        GitProvider.github,
      );
    });
    test('detects Azure urls', () {
      expect(
        providerFromRemoteUrl('https://dev.azure.com/you/project'),
        GitProvider.azure,
      );
      expect(
        providerFromRemoteUrl('https://your.visualstudio.com/project'),
        GitProvider.azure,
      );
      expect(
        providerFromRemoteUrl('dev.azure.com/org/proj'),
        GitProvider.azure,
      );
      // Edge case: SSH Azure URL
      expect(
        providerFromRemoteUrl('git@vs-ssh.visualstudio.com:v3/org/proj/repo'),
        GitProvider.azure,
      );
    });
    test('detects more SSH github url', () {
      expect(
        providerFromRemoteUrl('git@github.com:user/repo.git'),
        GitProvider.github,
      );
    });
    test('returns null for unknown or unsupported hosts', () {
      expect(providerFromRemoteUrl('https://bitbucket.org/x/y'), isNull);
      expect(providerFromRemoteUrl(''), isNull);
    });
  });
}
