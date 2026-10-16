# opal-autofocus: design

Date: 2026-10-16
Status: approved for planning

## Problem

The Opal C1 webcam works as a plain UVC camera on macOS, but its autofocus
stays parked at a fixed lens position until Opal Composer has run. Composer is
unreliable and effectively unmaintained. We want a small, open-source macOS
tool that makes autofocus work whenever the camera is plugged in, without
Composer and without changing how the camera is used (still the stock UVC
device in any app).

## What we established (2026-10-16 investigation)

- The camera enumerates as USB `03e7:f63d`. Interface 0 is a vendor bulk
  interface (`S_BULKDATA`, XLink) that does not respond while the camera runs
  its UVC firmware. Interface 1 is the UVC control interface, interface 2 the
  video stream, 3 and 4 are audio.
- Autofocus is driven by the standard UVC Camera Terminal control
  `CT_FOCUS_AUTO_CONTROL` (selector 8, one byte, unit 1, interface 1).
  Writing 0 parks the lens. Writing 1 enables continuous autofocus. Both
  directions were confirmed by hand on the real camera. The camera also
  honours `CT_FOCUS_ABSOLUTE_CONTROL` (selector 6, two bytes, 0 to 255) when
  Focus-Auto is 0. Readback of Focus-Absolute returns the last written value,
  not the live lens position.
- Composer's own UVC helper sends exactly that standard `SET_CUR Focus-Auto = 1`
  request through libusb. No vendor request, XLink traffic, or firmware upload
  is part of the autofocus path.
- A device-level `IOUSBDeviceInterface` open from an unprivileged process can
  issue these class requests while the system UVC driver and another app
  (Photo Booth, ffmpeg) stream video at the same time. No root, no kernel or
  system extension, no exclusive access.
- Open question: on one replug during the investigation the camera came up
  focusing before we sent anything. Composer installs a LaunchDaemon
  (`com.opalcamera.Opal.v2.cameraExtensionShim`) and a login item
  (`OpalLauncher.app`); one of them may send the kick after Composer has run
  once in a boot. Sending Focus-Auto = 1 on every attach is harmless and
  idempotent, so the tool does not depend on resolving this. It is listed as a
  verification task below.

## Goals

1. Autofocus works on every plug-in and on login with the camera attached,
   without Composer installed.
2. Nothing of ours runs while the camera is unplugged.
3. Installable with `brew services` or a `make install`, as a per-user
   launchd agent. No root.
4. Small, readable code that another person (or an AI assistant) can extend
   to another Opal model or another UVC control in an afternoon.

## Non-goals

- Replacing any other Composer feature (virtual camera, face tracking,
  background blur, white balance UI).
- Talking to the XLink/depthai side of the camera.
- Linux or Windows support (the control path is standard UVC, so ports are
  possible, but not in scope).
- Background blur. The lens has a fixed aperture; the only hardware "blur" is
  choosing a focus distance, which the `focus` subcommand exposes.

## Architecture

Swift package `opal-autofocus`, one executable, two targets.

```
Package.swift
Sources/
  OpalUVC/                 library: device discovery and UVC control I/O
    Device.swift           match + open IOUSBHostDevice by VID/PID
    UVCControl.swift       GET_CUR / SET_CUR class requests, byte packing
    Controls.swift         table of known controls (unit, selector, size)
    Models.swift           table of known devices (VID, PID, terminal ids)
  opal-autofocus/          CLI
    main.swift             subcommand dispatch (swift-argument-parser)
    RunCommand.swift       launchd entry point
    WatchCommand.swift     foreground IOKit notification loop
    ...                    status / enable / disable / focus
Tests/
  OpalUVCTests/            packing, match dictionary, table sanity
packaging/
  com.opal-autofocus.agent.plist            LaunchAgent template
  Formula/opal-autofocus.rb                 Homebrew formula (tap)
scripts/
  smoke.sh                 manual hardware check
docs/
  ARCHITECTURE.md
  PROTOCOL.md
CONTRIBUTING.md
CHANGELOG.md
CLAUDE.md
LICENSE                    MIT
README.md
```

### OpalUVC library

- `OpalDevice.find() -> [OpalDevice]`: builds an `IOUSBHostDevice` matching
  dictionary from the model table (`idVendor` 0x03e7, `idProduct` 0xf63d),
  iterates matches, and wraps each `io_service_t`.
- `OpalDevice.open()`: `IOCreatePlugInInterfaceForService` +
  `QueryInterface(kIOUSBDeviceInterfaceID)`. Device-level open only; no
  interface claim.
- `UVCControl`: encodes a class request. `bmRequestType` 0xA1 for GET,
  0x21 for SET; `bRequest` 0x81 GET_CUR, 0x01 SET_CUR, plus GET_MIN/MAX/DEF/
  INFO for `status`; `wValue = selector << 8`; `wIndex = (unit << 8) |
  interface`. Little-endian payload of `size` bytes.
- Public API:
  - `enableAutofocus()`: SET_CUR Focus-Auto = 1.
  - `disableAutofocus()`: SET_CUR Focus-Auto = 0.
  - `setFocus(_ position: UInt8)`: SET_CUR Focus-Auto = 0, then SET_CUR
    Focus-Absolute = position.
  - `status() -> Status`: Focus-Auto CUR, Focus-Absolute CUR/MIN/MAX/DEF.
- Errors: a single `UVCError` enum carrying the `IOReturn` code and the
  request that failed. No retries inside the library.

### CLI

| Subcommand | Behaviour | Exit code |
|---|---|---|
| `run` | Poll for the device every 250 ms for up to 5 s (configurable with `--timeout`). For each device found, `enableAutofocus()`. Log one line per device. | 0 on success; 0 if no device appeared and `--quiet-missing` is set (used by the launchd plist); 1 if no device; 2 on request failure |
| `watch` | Register `IOServiceAddMatchingNotification` for the model table and run the run loop. On each first-match, wait 500 ms then `enableAutofocus()`. Log attach, kick, and errors. Never exits on its own. | 1 on registration failure |
| `status` | Print device presence, serial, and the focus control values. | 0 / 1 if no device |
| `enable` | `enableAutofocus()` once. | 0 / 1 / 2 as `run` |
| `disable` | `disableAutofocus()` once. | same |
| `focus <0-255>` | `setFocus(n)`. | same |

All logging is plain text on stdout (normal) and stderr (errors), one event
per line, so launchd's `StandardOutPath`/`StandardErrorPath` capture it.

### launchd agent

`packaging/*.plist` (user agent, `~/Library/LaunchAgents`):

- `ProgramArguments`: `[<bin>, run, --quiet-missing]`
- `LaunchEvents` → `com.apple.iokit.matching` → one entry with
  `IOProviderClass` `IOUSBHostDevice`, `idVendor` 999, `idProduct` 63037,
  `IOMatchLaunchStream` true.
- `RunAtLoad` true (covers login with the camera already present),
  `KeepAlive` false, `ProcessType` Background,
  `StandardOutPath`/`StandardErrorPath` under `~/Library/Logs/opal-autofocus/`.

Homebrew: formula with `depends_on xcode: ["15.0", :build]`, builds with
`swift build -c release`, and a `service do` block. Homebrew's service DSL
has no `launch_events` key as of 2026-10, so `brew services start` runs
`opal-autofocus watch` with `keep_alive true` (the resident IOKit-notification
mode: one sleeping process, zero CPU while unplugged). The formula also
installs the event-driven plist under `#{prefix}/` and the caveats explain
how to use it instead for the no-resident-process behaviour. If the DSL gains
event support, switch to it and note the change in ARCHITECTURE.md.
`make install` / `make uninstall`
for source builds: copy binary, render the plist template with the binary
path, `launchctl bootstrap gui/$UID` / `bootout`.

### Error handling

- Device absent at `run`: retry window, then exit as in the table. launchd
  fires again on the next attach, so no long waits.
- IOKit open fails (another process holds an exclusive open): report the
  IOReturn and exit 2. We do not retry; `watch` logs and keeps watching.
- SET_CUR stalls (`kIOUSBPipeStalled`): report and exit 2. This is the
  signal that the firmware did not accept the control; documented in
  PROTOCOL.md.
- Several Opals: each is handled independently; one failure does not stop
  the others; the exit code is the worst of the set.

### Testing

- Unit tests (no hardware): request packing for every table entry,
  little-endian payloads for 1- and 2-byte controls, matching dictionary
  contents, exit-code mapping.
- `scripts/smoke.sh`: hardware walkthrough. Runs `status`, `disable`, asks
  the operator to confirm the lens is parked, `enable`, asks for
  confirmation that focus tracks a hand, then prints `status` again.
- GitHub Actions on `macos-latest`: `swift build`, `swift test`, formula
  audit. Hardware steps are manual and listed in CONTRIBUTING.md.
- Verification task before 1.0: reboot with Composer's LaunchDaemon and login
  item disabled (or Composer uninstalled), plug in, confirm the parked state,
  then confirm `run` fixes it. Record the outcome in PROTOCOL.md.

### Documentation

- README: what it does, why it exists, install (brew, source), usage,
  troubleshooting (`status`, log paths), prior art (open-opal, depthai),
  license.
- docs/ARCHITECTURE.md: the two targets, the launchd trigger, where to add a
  model or a control.
- docs/PROTOCOL.md: the camera's interfaces, the UVC controls and their
  values, what Composer sends, what does not work (XLink inert, Focus-Absolute
  readback), the open question above, and the method used to find all this.
- CONTRIBUTING.md: build, test, smoke test, code style (Swift format
  defaults), changelog rule, how to add a device.
- CHANGELOG.md: Keep a Changelog, semantic versions.
- CLAUDE.md: thin pointers to the docs above and the hardware-test rule.

## Risks

- Some Opal firmware versions might expose a different unit id or ignore
  Focus-Auto. The model table carries unit ids per PID, and `status` shows
  what the camera reports, which is the first thing to ask for in a bug
  report.
- launchd IOKit matching events have sparse documentation. If `RunAtLoad`
  plus `LaunchEvents` misbehaves on some macOS version, the fallback is
  documented: run `watch` from the plist with `KeepAlive` true.
- Reverse engineering Composer was limited to reading its public strings and
  observing standard USB class traffic; nothing from Composer's binaries is
  redistributed.
