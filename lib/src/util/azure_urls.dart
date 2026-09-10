// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// The web page of the pull request `az repos pr list` describes —
/// `https://dev.azure.com/<org>/<project>/_git/<repo>/pullrequest/<id>` —
/// or null when [pullRequest] does not carry what the page is built from.
///
/// `az` reports the repository, not the pull request page: the page is the
/// repository's web url (see [azureRepositoryWebUrl]) plus the pull request
/// id.
String? azurePullRequestWebUrl(Map<dynamic, dynamic> pullRequest) {
  final id = pullRequest['pullRequestId'];
  final repository = pullRequest['repository'];
  if (id == null || repository is! Map) {
    return null;
  }

  final repositoryUrl = azureRepositoryWebUrl(repository);
  if (repositoryUrl == null) {
    return null;
  }

  return '$repositoryUrl/pullrequest/$id';
}

/// The web page of the [repository] `az repos pr list` describes —
/// `https://dev.azure.com/<org>/<project>/_git/<repo>`.
///
/// `az` does not report that url: `remoteUrl` is null on current versions
/// and there is no `webUrl` at all. What it does report is the rest api url
/// (`https://dev.azure.com/<org>/<projectId>/_apis/git/repositories/<id>`)
/// together with the project and repository names — the pieces the web url
/// is assembled from. `remoteUrl` is only the fallback: where `az` fills it,
/// it is the clone url and carries the organization as user info
/// (`https://<org>@dev.azure.com/…`), which is stripped here.
String? azureRepositoryWebUrl(Map<dynamic, dynamic> repository) {
  final project = repository['project'];
  final projectName = project is Map ? project['name']?.toString() : null;
  final repositoryName = repository['name']?.toString();
  final apiUrl = repository['url']?.toString();
  final organizationUrl = apiUrl == null ? null : azureOrganizationUrl(apiUrl);

  if (projectName != null &&
      projectName.isNotEmpty &&
      repositoryName != null &&
      repositoryName.isNotEmpty &&
      organizationUrl != null) {
    // Project and repository names may contain spaces — Azure DevOps allows
    // them, so they must survive into the url encoded.
    return '$organizationUrl/${Uri.encodeComponent(projectName)}'
        '/_git/${Uri.encodeComponent(repositoryName)}';
  }

  return _withoutUserInfo(repository['remoteUrl']?.toString());
}

/// The organization part of an Azure DevOps rest api [apiUrl]:
/// `https://dev.azure.com/<org>/<projectId>/_apis/…` becomes
/// `https://dev.azure.com/<org>`. The legacy host form
/// `https://<org>.visualstudio.com/<projectId>/_apis/…` becomes
/// `https://<org>.visualstudio.com`, which is its equivalent.
///
/// Returns null for urls that do not have this shape — the pull request url
/// is then unknown rather than guessed.
String? azureOrganizationUrl(String apiUrl) {
  final uri = Uri.tryParse(apiUrl);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }

  final segments = uri.pathSegments;
  final apiIndex = segments.indexOf('_apis');
  // The segment right before `_apis` is the project, everything before it
  // the organization. Without both the url is not the expected one.
  if (apiIndex < 1) {
    return null;
  }

  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: segments.take(apiIndex - 1),
  ).toString();
}

/// [url] without its user info part, or null when there is no [url]. Azure
/// DevOps clone urls carry the organization as user info
/// (`https://<org>@dev.azure.com/…`); the web url does not.
String? _withoutUserInfo(String? url) {
  if (url == null || url.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.userInfo.isEmpty) {
    return url;
  }
  return uri.replace(userInfo: '').toString();
}
