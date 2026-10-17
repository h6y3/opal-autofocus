# opal-autofocus 0.2.0: design

Date: 2026-10-16
Status: approved for planning

## Why

0.1.x makes autofocus work. 0.2.0 is about making the tool boring to support
for other Opal owners, not just the author. The problems that cost the most
time so far were not bugs in the tool: Opal Composer's helper quietly enabling
autofocus, a powered USB hub keeping the camera on across an "unplug", and
confusion between the `brew services` watcher and the event-driven launchd
agent. 0.2.0 adds a read-only `doctor` command that catches those, a stable
machine-readable `status --json`, takes the focus range from the camera
instead of hardcoding it, and logs unplugs in `watch`.

Theme: boring and reliable. Small, well-tested changes; no new runtime
dependencies.

## Goals

1. `focus` validates the requested position against the range the camera
   reports (Focus-Absolute GET_MIN / GET_MAX), not a hardcoded 0...255.
2. `status --json` prints a stable, documented JSON shape that scripts,
   Hammerspoon or a menu bar app can rely on.
3. `doctor` checks the install, the camera and known interference, and for
   each problem prints what is wrong and the exact command that fixes it.
4. `watch` logs a line when a camera is unplugged.
5. Ship all four together as 0.2.0 after one hardware check.

## Non-goals

- Log rotation, config files, plugin systems.
- More UVC controls (zoom, pan, exposure). Focus only.
- A `--version` flag: it already exists (`CommandConfiguration(version:)`
  reads `OpalUVC.version`, bumped each release).
- `doctor --json`. Text only for now (my call; people paste doctor output
  into issues, scripts use `status --json`).
- Any change to the retry behaviour shipped in 0.1.2.

## Anti-goals (would make this a failure even if it works)

- `doctor` changing anything. It is strictly read-only: it never loads,
  unloads, writes or deletes. It only prints fix commands.
- `doctor` needing root, Homebrew, or network access to run.
- Breaking existing behaviour: `status` without `--json` prints exactly what
  it prints today; exit codes of existing commands are unchanged, with one
  deliberate exception described under item 1 (`focus` with an
  out-of-range value and no camera attached).
- Hardware constants appearing outside `Models.swift` and `Controls.swift`.

## Constraints

- Swift package, macOS 14+, swift-argument-parser. Tests use Swift Testing
  and run with `scripts/swift-test` (not bare `swift test`).
- Existing exit codes: 0 ok, 1 no device, 2 request failed, 64 usage error
  (from ArgumentParser `ValidationError`).
- Changes under `Sources/OpalUVC` or `Sources/COpalUSB` need a manual
  hardware check, recorded in the commit message. Items 1 and 4 touch
  `Sources/OpalUVC`. Per the release decision, one hardware check covers the
  whole release, done at the end (see "Hardware check and release").
- Every user-visible change gets a line under `Unreleased` in `CHANGELOG.md`.
  README documents new commands and the JSON shape. `docs/ARCHITECTURE.md`
  lists new files.
- Code that touches the system (IOKit, launchctl, the filesystem) sits
  behind a small protocol so the logic is tested with fakes, the same way
  `KickLoop` and `WatchKick` are today.
- The executing agent is pi on a smaller model. Each step must be explicit;
  no step should require inventing an interface.

## Decided

### Order (decided, to avoid rework)

1. Focus range from the device.
2. `status --json`.
3. `doctor`.
4. Unplug logging in `watch`.

Items 2 and 3 build on the status-reading code, so its shape settles first.
Item 4 is independent and touches the IOKit watcher, so it goes last, right
before the hardware check.

### 1. Focus range from the device

- `Connection.setFocus` takes an `Int` instead of `UInt8`. The value is
  encoded with the control's declared size (Focus-Absolute is 2 bytes), as
  `set(_:value:)` already does.
- `Focus.validate()` keeps a check that does not need the camera: the
  position must fit the Focus-Absolute control's size, 0 through
  `(1 << (8 * size)) - 1` (0...65535 for 2 bytes), computed from
  `CameraTerminalControl.focusAbsolute.size`, not a literal. Outside that:
  usage error, exit 64. The range check against the camera moves to `run()`.
- `run()` works in two passes (my call on the mixed cases):
  1. With no camera attached: "no Opal camera attached", exit 1, as for
     every other command. So `focus 300` with no camera now exits 1 instead
     of 64. This is a deliberate behaviour change, noted in the CHANGELOG.
     `CLIBehaviourTests.focusOutOfRangeIsUsageError` changes to use a value
     above 65535 so CI still covers the usage-error path without a camera.
  2. Check pass: open every camera and read its range (GET_MIN, GET_MAX of
     Focus-Absolute). If the position is outside the range of any camera
     that was read, print one line per offending camera,
     `<label>: position <n> is outside this camera's range <min>...<max>`,
     write to no camera at all, and exit 64. A usage mistake wins over
     request failures.
  3. Write pass: otherwise, write to every camera whose range was read.
     Cameras whose range read failed are reported like any request failure
     and not written to; if there were any, exit 2.
  Rejecting, not clamping (my call: a silently clamped value is confusing;
  the message tells the user the valid range).
- Help text changes from "0 nearest, 255 farthest" to say the valid range
  comes from the camera and is shown by `opal-autofocus status`, with lower
  values nearer. No numeric range in help text (my call, so no hardware
  constant leaks out of `Models.swift` / `Controls.swift`).

### 2. `status --json`

- New `--json` flag on `status`. Without it, output is byte-for-byte what it
  is today.
- Output is one JSON object on stdout, pretty-printed with sorted keys:

  ```json
  {
    "cameras" : [
      {
        "autofocus" : true,
        "default" : 130,
        "location" : "0x01220000",
        "maximum" : 255,
        "minimum" : 0,
        "model" : "Opal C1",
        "position" : 130,
        "serial" : "1944301031042E1800"
      }
    ],
    "schema" : 1
  }
  ```

- `schema` is an integer that only changes when a field is removed or its
  meaning changes. Adding a field does not bump it. This rule is written in
  the README.
- `location` is the same hex string the text output shows. `serial` is the
  same string; `null` if the camera reports none.
- A camera whose controls cannot be read appears as
  `{"model", "serial", "location", "error": "<message>"}` with no focus
  fields. Exit code 2, as today.
- No camera: `{"cameras": [], "schema": 1}` and exit code 1, as today.
- In JSON mode nothing else is written to stdout. Errors still go to stderr
  as they do now, so stdout stays parseable.

### 3. `doctor`

New read-only subcommand. It runs every check, prints one line per check,
prints the recent log, and exits 0 if no check failed, 1 if any did (my
call; doctor's 1 means "something needs attention", documented in its help).

Output shape:

```
opal-autofocus 0.2.0 at /opt/homebrew/bin/opal-autofocus

ok    setup: event-driven launchd agent loaded (com.opal-autofocus.agent)
ok    setup: agent runs /Users/me/.local/bin/opal-autofocus
note  composer: Opal Composer's helper daemon is installed and can turn autofocus on by itself, so autofocus may work even when this tool is not running
ok    camera: Opal C1 (serial 1944301031042E1800, location 0x01220000)
ok    controls: autofocus: on, focus position: 130 (min 0, max 255, default 130)

recent log (/Users/me/Library/Logs/opal-autofocus/agent.log):
  2026-10-17T01:21:33Z enabled autofocus on Opal C1 (...)
```

Checks, in order:

1. **Setup detection.** Two possible setups, identified by launchd label and
   plist path in `~/Library/LaunchAgents`:
   - event-driven agent: `com.opal-autofocus.agent`
     (`com.opal-autofocus.agent.plist`), installed by `make install` or by
     hand from the Homebrew caveats;
   - Homebrew watcher: two possible labels, newest first:
     `sh.brew.opal-autofocus` (`sh.brew.opal-autofocus.plist`), used by
     Homebrew 7, and `homebrew.mxcl.opal-autofocus`
     (`homebrew.mxcl.opal-autofocus.plist`), used by older Homebrew.
     Doctor knows both: the hardware check found Homebrew 7.0.9 running the
     watcher under `sh.brew` while doctor only looked for `homebrew.mxcl`,
     which hid the two-setups conflict. The watcher counts as loaded when
     either label is loaded and as installed when either plist exists, and
     messages name the label actually seen.

   For each, "installed" means the plist exists and "loaded" means
   `launchctl print gui/<uid>/<label>` exits 0. Apply the first rule that
   matches, and print exactly one setup line (my call on precedence):
   1. Both loaded: FAIL, "two setups are loaded; use one". Fix:
      `brew services stop opal-autofocus` (keeping the event-driven agent).
   2. Exactly one loaded: ok, naming it. If the other one's plist is
      installed but not loaded, add a `note` line saying it is a harmless
      leftover, with its path.
   3. None loaded, at least one plist installed: FAIL, "installed but not
      loaded". Fix: for the event-driven agent,
      `launchctl bootstrap gui/<uid> <plist path>`; for the Homebrew watcher,
      `brew services start opal-autofocus`. If both plists are installed,
      the fix names the event-driven agent only, to avoid steering the user
      into loading both.
   4. Nothing installed: FAIL, "nothing will re-enable autofocus after a
      replug". Fix: `brew services start opal-autofocus` or `make install`.
2. **Agent program.** For each installed plist, read `ProgramArguments[0]`.
   If that file does not exist: FAIL (stale after an uninstall or a moved
   prefix). Fix: re-run the install that created it. Otherwise ok, naming
   the path.
3. **Opal Composer helper.** If
   `/Library/LaunchDaemons/com.opalcamera.Opal.v2.cameraExtensionShim.plist`
   exists, print a `note` line (not a failure; the README says Composer and
   this tool do not conflict): "Opal Composer's helper daemon is installed
   and can turn autofocus on by itself, so autofocus may work even when
   this tool is not running". No fix line. If absent, print nothing for this
   check. (My call: a third status, `note`, which never affects the exit
   code.)
4. **Camera.** No camera: FAIL. Fix: "plug the camera in; if it is behind a
   hub, plug it into the hub or Mac directly to rule the hub out". One ok
   line per camera found, with its label.
5. **Controls.** Per camera, read focus status. Read error: FAIL with the
   error. Autofocus off: FAIL, "autofocus is off". Fix:
   `opal-autofocus enable`, plus "if it is off again after every replug, the
   setup check above is the place to look". Otherwise ok with the summary.
   (Decided: autofocus off is reported as a failure even though the user may
   have turned it off on purpose; the fix line covers that case.)
6. **Recent log.** Not a pass/fail check. From each installed plist, read
   `StandardOutPath`; print the last 5 lines of that file under a
   `recent log (<path>):` heading. Skip silently if the file is missing.

Implementation shape (decided): checks are pure logic over a
`DoctorEnvironment` protocol that exposes only what doctor needs (home
directory, user id, file exists, read a plist as a dictionary, is a launchd
label loaded, list cameras with their status or error, last N lines of a
file, own executable path). One live implementation; tests use a fake. The
Composer daemon path and the two launchd labels are not hardware constants
and live in the doctor code.

### 4. Unplug logging in `watch`

- `DeviceWatcher` gains an optional `onDetach` callback, driven by an
  `IOServiceAddMatchingNotification` with `kIOTerminatedNotification` on the
  same matching dictionaries. Existing callers that pass only `onAttach`
  compile and behave as before.
- `watch` logs `<timestamp> detached: <label>` through the same `Output.line`
  path as `attached:`.
- Reading serial and location from a terminated service may fail. If it
  does, the label falls back to the model name. The builder confirms what
  the label looks like on the real camera during the hardware check.

### Branch, commits

- Work on a branch `0.2.0`, one commit per item at minimum, each with tests
  passing. Commit messages follow the repo style (plain sentences, why
  first, no model attribution beyond what the repo already uses).
- CI only runs on pushes to `main` and on pull requests, so the executing
  agent pushes `0.2.0` after the first commit and opens a draft PR against
  `main` (decided by the user). It pushes after each item. It never merges
  and never pushes to `main`.
- CI must be green on the PR before the hardware check.

### Hardware check and release

Not done by the executing agent. When the branch is ready:

1. The user runs `make install`, then `make smoke` (pulling the camera's own
   cable at the cold-start prompt).
2. With the camera attached: `opal-autofocus focus 300` exits 64 with the
   range message and does not change the lens; `opal-autofocus focus 200`
   moves it; `opal-autofocus status --json` parses with `python3 -m
   json.tool`; `opal-autofocus doctor` exits 0.
3. With `brew services` started as well, `doctor` reports both setups and
   exits 1.
4. Running `opal-autofocus watch` in a terminal, unplugging the camera logs
   `detached:` with a sensible label.
5. Then merge to main and release 0.2.0 with the CONTRIBUTING.md steps,
   including the tap update.

## Left to the builder

- File layout for new code, as long as `docs/ARCHITECTURE.md` lists it.
- Exact wording of ok/FAIL messages beyond what is given above, and the
  column alignment.
- Whether `status --json` builds its output from `FocusStatus` with a
  separate `Codable` DTO in the CLI (preferred so `OpalUVC` stays free of
  output concerns) or another way that keeps the shape above.
- How the live `DoctorEnvironment` runs `launchctl` (Foundation `Process`
  is fine).
