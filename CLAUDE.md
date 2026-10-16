# opal-autofocus

Swift CLI and launchd agent that enables the Opal C1's autofocus with the
standard UVC Focus-Auto control. Read `docs/ARCHITECTURE.md` before changing
code and `docs/PROTOCOL.md` before touching anything USB-related.

- Build: `swift build`. Test: `scripts/swift-test` (not bare `swift test`).
  Hardware check: `make smoke`.
- Changes to `Sources/OpalUVC` or `Sources/COpalUSB` need a manual hardware
  check; say in the commit or PR whether it was done.
- Hardware constants live only in `Models.swift` and `Controls.swift`.
- Update `CHANGELOG.md` under `Unreleased` for user-visible changes.
- Formula changes must also be copied to h6y3/homebrew-tap on release.
