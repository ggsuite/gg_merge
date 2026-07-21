# Changelog

## [Unreleased]

### Added

- Add --pr support: PR created plain with URL logged, auto-merge best-effort with strategy detection and squash retry, new --delete-source-branch flag

## [1.5.1] - 2026-07-20

### Changed

- gg\_multi: changed references to git

## [1.5.0] - 2026-07-06

### Changed

- feat: merge via auto-complete pull request on protected main (Azure) and wait until merged

## [1.4.0] - 2026-07-01

### Changed

- feat(gg): do checkout + .gg/.ticket.json ticket marker; TS format no direct eslint & P:\programs\flutter/bin/internal/exit\_with\_errorlevel.bat
- gg\_multi: changed references to git

## [1.3.1] - 2026-06-26

### Changed

- gg\_multi: changed references to git

## [1.3.0] - 2026-06-19

### Changed

- gg\_multi: changed references to git

## [1.2.0] - 2026-06-08

### Changed

- feat: TS-aware HasLocalReferences/HasGitReferences via gg\_lang dispatch
- gg\_multi: changed references to git
- Gg Multi: changed references to pub.dev
- gg\_multi: changed references to git

## [1.1.0] - 2026-05-19

## [1.0.5] - 2026-05-19

### Added

- `LocalMerge` constructor: `runPubGet` flag (default `true`) to skip the
pub-get + lockfile staging step. Useful for tests that drive
`LocalMerge` through `DoMerge` with a real `GgProcessWrapper`

### Fixed

- `local-merge`: run `dart pub get` (or `flutter pub get`) and stage
`pubspec.lock` between the squash merge and the commit, so the updated
lockfile is part of the squash commit instead of being left dirty by
VS Code's auto pub get after the fact

## [1.0.4] - 2026-03-26

### Added

- Add .gitattributes file

### Removed

- Remove push to origin/main from local merge and related test

## [1.0.3] - 2025-08-11

- Update to gg\_git 3.0.0

## [1.0.2] - 2025-08-05

### Removed

- remove has git references from can merge

## [1.0.1] - 2025-08-02

### Added

- add tests for local merge option
- Add merge message for squash
- Initial version of gg\_merge

### Changed

- prepare version 1.0.1

[Unreleased]: https://github.com/ggsuite/gg_merge/compare/1.5.1...HEAD
[1.5.1]: https://github.com/ggsuite/gg_merge/compare/1.5.0...1.5.1
[1.5.0]: https://github.com/ggsuite/gg_merge/compare/1.4.0...1.5.0
[1.4.0]: https://github.com/ggsuite/gg_merge/compare/1.3.1...1.4.0
[1.3.1]: https://github.com/ggsuite/gg_merge/compare/1.3.0...1.3.1
[1.3.0]: https://github.com/ggsuite/gg_merge/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/ggsuite/gg_merge/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/inlavigo/gg_merge/compare/1.0.5...1.1.0
[1.0.5]: https://github.com/inlavigo/gg_merge/compare/1.0.4...1.0.5
[1.0.4]: https://github.com/inlavigo/gg_merge/compare/1.0.3...1.0.4
[1.0.3]: https://github.com/inlavigo/gg_merge/compare/1.0.2...1.0.3
[1.0.2]: https://github.com/inlavigo/gg_merge/compare/1.0.1...1.0.2
[1.0.1]: https://github.com/inlavigo/gg_merge/tag/%tag
