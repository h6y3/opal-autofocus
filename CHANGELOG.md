# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.2] - 2026-10-16

### Changed
- A failed autofocus write no longer waits for a replug: `run` and `watch`
  retry it up to twice more, 0.5 s and 1 s apart, and log each failed attempt.
- `run` prefixes every log line with a UTC timestamp, so `agent.log` shows
  when each kick happened.
- `make smoke` starts with a cold-start check: it pauses the launchd agent,
  asks you to replug and confirm the lens is parked, then confirms `run`
  starts autofocus, and restores the agent afterwards.
- With several cameras attached, `run` reports every camera that failed, not
  only the first.

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

[Unreleased]: https://github.com/h6y3/opal-autofocus/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/h6y3/opal-autofocus/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/h6y3/opal-autofocus/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/h6y3/opal-autofocus/releases/tag/v0.1.0
