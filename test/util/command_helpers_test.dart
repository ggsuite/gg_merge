// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_git/gg_git.dart';
import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_merge/src/util/command_helpers.dart';

import '../helpers.dart';

class _MockGgProcessWrapper extends Mock implements GgProcessWrapper {}

void main() {
  setUpAll(registerTestFallbacks);

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

  group('readOriginUrl', () {
    late Directory d;
    late _MockGgProcessWrapper processWrapper;

    setUp(() async {
      d = await Directory.systemTemp.createTemp('helpers_test_');
      processWrapper = _MockGgProcessWrapper();
    });

    tearDown(() async => d.delete(recursive: true));

    void stub(ProcessResult result) {
      when(
        () => processWrapper.run(
          'git',
          ['config', '--get', 'remote.origin.url'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).thenAnswer((_) async => result);
    }

    test('returns the trimmed origin url', () async {
      stub(ProcessResult(0, 0, 'https://github.com/me/repo.git\n', ''));
      expect(
        await readOriginUrl(directory: d, processWrapper: processWrapper),
        'https://github.com/me/repo.git',
      );
    });

    test('returns null when the remote cannot be read', () async {
      stub(ProcessResult(1, 1, '', 'no origin'));
      expect(
        await readOriginUrl(directory: d, processWrapper: processWrapper),
        isNull,
      );
    });
  });

  group('resolveMainBranch', () {
    late MockDefaultBranch defaultBranch;
    final messages = <String>[];
    final ggLog = messages.add;
    final d = Directory.current;

    setUp(() => defaultBranch = MockDefaultBranch());

    test('returns mainBranch without asking the repository', () async {
      final result = await resolveMainBranch(
        defaultBranch: defaultBranch,
        directory: d,
        ggLog: ggLog,
        mainBranch: 'release',
      );
      expect(result, 'release');
      verifyNever(
        () => defaultBranch.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      );
    });

    test('reads the default branch from the repository', () async {
      mockDefaultBranch(defaultBranch, 'develop');
      final result = await resolveMainBranch(
        defaultBranch: defaultBranch,
        directory: d,
        ggLog: ggLog,
      );
      expect(result, 'develop');
      verify(() => defaultBranch.get(directory: d, ggLog: ggLog)).called(1);
    });

    test('throws when the repository has no default branch', () async {
      mockDefaultBranch(defaultBranch, '');
      await expectLater(
        () => resolveMainBranch(
          defaultBranch: defaultBranch,
          directory: d,
          ggLog: ggLog,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('No default branch found (origin/HEAD, main, master)'),
          ),
        ),
      );
    });
  });
}
