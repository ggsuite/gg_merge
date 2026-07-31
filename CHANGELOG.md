# Changelog

## 2.0.0 - 2026-07-31

### Changed

- Prefix all gg-generated commit messages with "#gg: "; the unchanged-repo check treats such commits as not user generated

## 1.7.2 - 2026-07-30

### Changed

- Improve merge on github message

## 1.7.1 - 2026-07-29

### Changed

- Do not repeat poll messages while publishing or merging

## 1.7.0 - 2026-07-29

### Changed

- Support projects without manifest: ProjectType.none, checks skipped, version tracked as git tag only
- gg_multi: changed references to git

## 1.6.1 - 2026-07-29

### Added

- The pull request url is now surfaced everywhere the publish interacts with a PR: when it is created, when an existing PR is reused, and once at the start of the wait-for-merge poll ("Check the pull request status here: <url>", printed blue) — on GitHub from `gh`, on Azure DevOps built from `repository.webUrl`

### Changed

- Show the pull request url on create, reuse and while waiting for the merge
- "Created pull request" / "Reusing existing pull request" messages are printed dark gray (url blue)
- Reuse only open pull requests; print PR messages dark gray
- Fall back to a direct squash merge when auto-merge is not allowed
- Never merge a pull request automatically; pass the PR source branch to the wait
- Handle auto merge when github does not support auto merge

### Fixed

- gg never merges a pull request on its own: when the provider rejects auto-merge, the PR stays open and the publish waits for the manual merge (the merge stays an explicit human decision)
- WaitForMerge accepts the pull request's source branch, so the wait no longer looks for a pull request of the default branch when HEAD moved on ("No pull request found for branch main")
- PR reuse now only considers OPEN pull requests. Before, a merged pull request of an earlier release on the same branch was "reused", so wait-for-merge saw »merged« immediately although the new release content was never merged to main

## 1.6.0 - 2026-07-22

### Added

- Add --pr support: PR created plain with URL logged, auto-merge best-effort with strategy detection and squash retry, new --delete-source-branch flag

### Changed

- Always squash-merge pull requests and use the merge message as PR title and squash commit message
- Share the origin-url lookup, use named arguments in MergeGit internals and unify the best-effort automerge warning
- gg_multi: changed references to git

## 1.5.1 - 2026-07-20

### Changed

- gg_multi: changed references to git

## 1.5.0 - 2026-07-06

### Changed

- feat: merge via auto-complete pull request on protected main (Azure) and wait until merged

## 1.4.0 - 2026-07-01

### Changed

- feat(gg): do checkout + .gg/.ticket.json ticket marker; TS format no direct eslint & P:\programs\flutter/bin/internal/exit_with_errorlevel.bat
- gg_multi: changed references to git

## 1.3.1 - 2026-06-26

### Changed

- gg_multi: changed references to git

## 1.3.0 - 2026-06-19

### Changed

- gg_multi: changed references to git

## 1.2.0 - 2026-06-08

### Changed

- feat: TS-aware HasLocalReferences/HasGitReferences via gg_lang dispatch
- gg_multi: changed references to git
- Gg Multi: changed references to pub.dev
- gg_multi: changed references to git

## 1.1.0 - 2026-05-19

## 1.0.5 - 2026-05-19

### Added

- `LocalMerge` constructor: `runPubGet` flag (default `true`) to skip the
pub-get + lockfile staging step. Useful for tests that drive
`LocalMerge` through `DoMerge` with a real `GgProcessWrapper`

### Fixed

- `local-merge`: run `dart pub get` (or `flutter pub get`) and stage
`pubspec.lock` between the squash merge and the commit, so the updated
lockfile is part of the squash commit instead of being left dirty by
VS Code's auto pub get after the fact

## 1.0.4 - 2026-03-26

### Added

- Add .gitattributes file

### Removed

- Remove push to origin/main from local merge and related test

## 1.0.3 - 2025-08-11

- Update to gg_git 3.0.0

## 1.0.2 - 2025-08-05

### Removed

- remove has git references from can merge

## 1.0.1 - 2025-08-02

### Added

- add tests for local merge option
- Add merge message for squash
- Initial version of gg_merge

### Changed

- prepare version 1.0.1
