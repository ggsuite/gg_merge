# Changelog

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

[1.0.5]: https://github.com/inlavigo/gg_merge/compare/1.0.4...1.0.5
[1.0.4]: https://github.com/inlavigo/gg_merge/compare/1.0.3...1.0.4
[1.0.3]: https://github.com/inlavigo/gg_merge/compare/1.0.2...1.0.3
[1.0.2]: https://github.com/inlavigo/gg_merge/compare/1.0.1...1.0.2
[1.0.1]: https://github.com/inlavigo/gg_merge/tag/%tag
