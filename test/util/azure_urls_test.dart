// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_merge/gg_merge.dart';
import 'package:test/test.dart';

void main() {
  group('azurePullRequestWebUrl', () {
    test('assembles the page from the repository az reports', () {
      final url = azurePullRequestWebUrl({
        'pullRequestId': 138,
        'repository': {
          'name': 'r',
          'project': {'name': 'p'},
          'remoteUrl': null,
          'url': 'https://dev.azure.com/o/902c4d10/_apis/git/repositories/e8',
        },
      });
      expect(url, 'https://dev.azure.com/o/p/_git/r/pullrequest/138');
    });

    test('returns null without a pull request id', () {
      expect(
        azurePullRequestWebUrl({
          'repository': {'remoteUrl': 'https://dev.azure.com/o/p/_git/r'},
        }),
        isNull,
      );
    });

    test('returns null without a repository', () {
      expect(azurePullRequestWebUrl({'pullRequestId': 1}), isNull);
      expect(
        azurePullRequestWebUrl({'pullRequestId': 1, 'repository': 'x'}),
        isNull,
      );
    });

    test('returns null when the repository url is unknown', () {
      expect(
        azurePullRequestWebUrl({
          'pullRequestId': 1,
          'repository': {'name': 'r'},
        }),
        isNull,
      );
    });
  });

  group('azureRepositoryWebUrl', () {
    test('encodes project and repository names', () {
      final url = azureRepositoryWebUrl({
        'name': 'my repo',
        'project': {'name': 'my project'},
        'url': 'https://dev.azure.com/o/902c4d10/_apis/git/repositories/e8',
      });
      expect(url, 'https://dev.azure.com/o/my%20project/_git/my%20repo');
    });

    test('supports the legacy visualstudio.com host', () {
      final url = azureRepositoryWebUrl({
        'name': 'r',
        'project': {'name': 'p'},
        'url': 'https://o.visualstudio.com/902c4d10/_apis/git/repositories/e8',
      });
      expect(url, 'https://o.visualstudio.com/p/_git/r');
    });

    test('falls back to remoteUrl without its user info', () {
      expect(
        azureRepositoryWebUrl({
          'remoteUrl': 'https://o@dev.azure.com/o/p/_git/r',
        }),
        'https://dev.azure.com/o/p/_git/r',
      );
    });

    test('keeps a remoteUrl that has no user info', () {
      expect(
        azureRepositoryWebUrl({
          'remoteUrl': 'https://dev.azure.com/o/p/_git/r',
        }),
        'https://dev.azure.com/o/p/_git/r',
      );
    });

    test('falls back to remoteUrl when a name is empty', () {
      expect(
        azureRepositoryWebUrl({
          'name': '',
          'project': {'name': 'p'},
          'url': 'https://dev.azure.com/o/x/_apis/git/repositories/y',
          'remoteUrl': 'https://dev.azure.com/o/p/_git/r',
        }),
        'https://dev.azure.com/o/p/_git/r',
      );
    });

    test('returns null when nothing is known', () {
      expect(azureRepositoryWebUrl({}), isNull);
      expect(azureRepositoryWebUrl({'remoteUrl': ''}), isNull);
    });

    test('passes a remoteUrl through that is no url', () {
      // Not decided here: the caller reports what az reported.
      expect(azureRepositoryWebUrl({'remoteUrl': 'not a url'}), 'not a url');
    });
  });

  group('azureOrganizationUrl', () {
    test('strips project and api path', () {
      expect(
        azureOrganizationUrl('https://dev.azure.com/o/p/_apis/git/x'),
        'https://dev.azure.com/o',
      );
    });

    test('keeps an explicit port', () {
      expect(
        azureOrganizationUrl('https://host:8080/o/p/_apis/git/x'),
        'https://host:8080/o',
      );
    });

    test('returns null for urls without _apis or without a project', () {
      expect(azureOrganizationUrl('https://dev.azure.com/o/p'), isNull);
      expect(azureOrganizationUrl('https://dev.azure.com/_apis/x'), isNull);
    });

    test('returns null for urls without scheme or host', () {
      expect(azureOrganizationUrl('o/_apis/git/x'), isNull);
      expect(
        azureOrganizationUrl('https://dev.azure.com:port/o/_apis'),
        isNull,
      );
    });
  });
}
