# Contributing

## Build and test

    swift build
    scripts/swift-test   # or: make test
    make smoke           # needs the camera and a preview app such as Photo Booth

Use `scripts/swift-test` rather than plain `swift test`: Command Line Tools
installs need an extra plugin path for Swift Testing, and the script adds it.

CI builds, runs the tests, builds a release binary, and lints the formula and
plist on a macOS runner. CI has no camera, so any change to the USB path needs
a manual `make smoke`; say in the pull request that you ran it.

## Hardware verification

Before a release, with an Opal C1:

1. `make install`, unplug and replug the camera, and confirm a new
   `enabled autofocus` line in `~/Library/Logs/opal-autofocus/agent.log`.
   `launchctl print gui/$(id -u)/com.opal-autofocus.agent` should show the
   job `not running` with its run count up by one, not climbing.
2. `make smoke` and answer the prompts honestly. Its first phase is a cold
   start: it pauses the agent, asks you to replug, and checks that the lens is
   parked before `run` fixes it. If the lens is already focusing at that
   point, something else is enabling autofocus (for example Opal Composer's
   background helper), and the result says nothing about this tool; stop that
   first. Record notable results in `docs/PROTOCOL.md`.

## Code style

Swift defaults: 4-space indent, trailing commas in multi-line literals. Keep
files to one responsibility. Comments are for non-obvious constraints, not
for restating the code.

## Adding a camera or a control

See `docs/ARCHITECTURE.md`. Every table entry needs a unit test in
`Tests/OpalUVCTests` and a smoke-test result in `docs/PROTOCOL.md`.

## Changelog and releases

`CHANGELOG.md` follows Keep a Changelog. Add a line under `Unreleased` with
each user-visible change. To release:

1. Move `Unreleased` to a new version heading with the date.
2. Bump `OpalUVC.version` in `Sources/OpalUVC/OpalUVC.swift`.
3. Tag `vX.Y.Z`, push the tag, and create a GitHub release.
4. Update `url` and `sha256` in `packaging/Formula/opal-autofocus.rb`
   (`curl -sL <tarball url> | shasum -a 256`), then copy the formula to
   `Formula/opal-autofocus.rb` in
   [h6y3/homebrew-tap](https://github.com/h6y3/homebrew-tap).
