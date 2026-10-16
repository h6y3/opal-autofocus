# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-10-16

### Fixed
- Autofocus now starts on a freshly plugged-in camera. The camera ignores
  Focus-Auto = 1 until it has seen 0, so `enable`, `run` and `watch` write 0
  and then 1. 0.1.0 only worked while Opal Composer's background helper was
  installed.
- `run` waits 0.5 s (`--settle`) after finding the camera before writing.

## [0.1.0] - 2026-10-16

### Added
- `run`, `watch`, `status`, `enable`, `disable` and `focus` subcommands.
- launchd user agent started by IOKit matching, installed with `make install`.
- Homebrew formula with `brew services` support.

[Unreleased]: https://github.com/h6y3/opal-autofocus/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/h6y3/opal-autofocus/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/h6y3/opal-autofocus/releases/tag/v0.1.0
