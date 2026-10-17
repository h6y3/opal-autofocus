# opal-autofocus 0.2.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the four 0.2.0 changes: focus range read from the camera, `status --json`, a read-only `doctor` command, and unplug logging in `watch`, on a `0.2.0` branch with a draft PR, ready for the user's hardware check.

**Architecture:** OpalUVC gains two small device calls (`focusRange()`, `setFocus(Int)`) and an optional detach callback on `DeviceWatcher`. Everything else is CLI code in `Sources/OpalAutofocusCLI`, written as pure logic over small protocols (`FocusTarget`, `DoctorEnvironment`) so it is tested with fakes, the same pattern `KickLoop` and `WatchKick` already use.

**Tech Stack:** Swift 6 toolchain (language mode 5), swift-argument-parser, Swift Testing, IOKit, Foundation.

**Spec:** `docs/superpowers/specs/2026-10-16-opal-autofocus-0.2.0-design.md`. Read it before Task 1; this plan argues from it.

## Global Constraints

- Read `CLAUDE.md`, `docs/ARCHITECTURE.md` and `docs/PROTOCOL.md` before starting.
- Build: `swift build`. Test: `scripts/swift-test` (never bare `swift test`). One suite: `scripts/swift-test --filter <SuiteName>`.
- Existing exit codes: 0 ok, 1 no device, 2 request failed, 64 usage error. Do not change them except where Task 1 says so.
- Hardware constants (ids, selectors, sizes, ranges) live only in `Sources/OpalUVC/Models.swift` and `Sources/OpalUVC/Controls.swift`.
- `status` without `--json` must print exactly what it prints today.
- `doctor` is read-only: it never loads, unloads, writes or deletes anything, and it needs no root, Homebrew or network.
- Every user-visible change gets a line under `## [Unreleased]` in `CHANGELOG.md` (`### Added` or `### Changed`).
- New source files are listed in `docs/ARCHITECTURE.md`.
- Comments: none unless the reason is non-obvious; at most one line each. No multi-line doc comment blocks.
- Commit messages: plain sentences, explain why first. No `Co-Authored-By` or model attribution lines. End each commit message that touches `Sources/OpalUVC` with the line `Hardware check: pending, done once for the 0.2.0 release.`
- Git: work only on branch `0.2.0`. Push it after each task. Never push to `main`, never merge, never tag, never release.
- Never write prose with em dashes or en dashes (repo style).
- Do not run anything that writes to a camera (`enable`, `disable`, `focus`, `run`, `watch`, `make smoke`). Tests that would write already skip when a camera is attached; keep that pattern.

## Review Focus

1. A launchd plist path that contains a space (a home directory like `/Users/Jane Doe`): doctor's `launchctl bootstrap` fix line must quote the path. Test in Task 3.
2. A plist that exists but cannot be parsed, or has `Program` instead of `ProgramArguments`: doctor must report it, not crash. Test in Task 3.
3. `focus` at exactly the camera's minimum or maximum: accepted (range is inclusive). Test in Task 1.
4. Two cameras, one fine and one with autofocus off: doctor prints one ok line and one FAIL line and exits 1. Test in Task 3.
5. `status --json` with no camera attached: stdout holds only valid JSON (`{"cameras": [], "schema": 1}`) and the exit code is 1; nothing else on stdout. Test in Task 2.

---

### Task 1: Focus range from the camera

**Files:**
- Modify: `Sources/OpalUVC/Controls.swift` (add `maxEncodableValue`)
- Modify: `Sources/OpalUVC/FocusControl.swift:47-51` (`setFocus`, add `focusRange`)
- Create: `Sources/OpalAutofocusCLI/FocusApply.swift`
- Modify: `Sources/OpalAutofocusCLI/FocusCommands.swift:36-51` (`Focus`)
- Test: `Tests/OpalUVCTests/ModelsTests.swift` (or a new `ControlsTests.swift`), `Tests/OpalAutofocusCLITests/FocusApplyTests.swift` (new), `Tests/OpalAutofocusCLITests/FocusCommandTests.swift`, `Tests/OpalAutofocusCLITests/CLIBehaviourTests.swift`
- Docs: `CHANGELOG.md`, `README.md` (any place that says focus is 0 to 255), `docs/ARCHITECTURE.md`

**Interfaces:**
- Produces (OpalUVC):
  - `extension CameraTerminalControl { public var maxEncodableValue: Int }`, equal to `(1 << (8 * size)) - 1`.
  - `Connection.focusRange() throws -> ClosedRange<Int>`: `get(.focusAbsolute, .getMin)...get(.focusAbsolute, .getMax)`.
  - `Connection.setFocus(_ position: Int) throws` (was `UInt8`). Still writes Focus-Auto 0 then Focus-Absolute `position`.
- Produces (CLI):
  - `protocol FocusTarget { var label: String { get }; func focusRange() throws -> ClosedRange<Int>; func setFocus(_ position: Int) throws }`
  - `extension OpalDevice: FocusTarget` (each method does `try open().<call>`).
  - `func applyFocus(_ position: Int, to targets: [FocusTarget], log: (String) -> Void, fail: (String) -> Void) -> Int32` returning an `ExitStatus` value or `64`.

- [ ] **Step 0: Create the branch**

Run: `git switch -c 0.2.0` from an up-to-date `main` (`git pull --ff-only` first).
Expected: `Switched to a new branch '0.2.0'`.

- [ ] **Step 1: Write the failing tests**

In `FocusApplyTests.swift`, a fake `final class FakeFocusTarget: FocusTarget` with `label`, a `range: Result<ClosedRange<Int>, Boom>` and a recorded `written: [Int]`. Reuse `Boom` from `TestDoubles.swift`. Tests (each collects `log` and `fail` lines into arrays):

```swift
@Test func writesInRangePositionToEveryCamera()      // a: 0...255, b: 0...255, position 200
// returns 0; a.written == [200]; b.written == [200]
// logged == ["set focus position 200 on a", "set focus position 200 on b"]; failed == []

@Test func boundaryValuesAreAccepted()                // a: 10...20; apply 10 then 20 (two calls)
// both return 0; a.written == [10, 20]

@Test func outOfRangeOnAnyCameraWritesNothing()       // a: 0...255, b: 0...100, position 150
// returns 64; a.written == []; b.written == []
// failed == ["b: position 150 is outside this camera's range 0...100"]

@Test func outOfRangeWinsOverReadFailure()            // a: range throws Boom, b: 0...100, position 150
// returns 64; nothing written; failed contains "b: position 150 is outside this camera's range 0...100"

@Test func readFailureSkipsThatCameraOnly()           // a: range throws Boom, b: 0...255, position 50
// returns 2; a.written == []; b.written == [50]
// failed == ["a: \(Boom.message)"]; logged == ["set focus position 50 on b"]

@Test func writeFailureIsRequestFailure()             // a: 0...255 but setFocus throws Boom
// returns 2; failed == ["a: \(Boom.message)"]

@Test func noCamerasIsNoDevice()                      // targets []
// returns 1; failed == ["no Opal camera attached"]
```

In the OpalUVC tests: `focusAbsolute.maxEncodableValue == 65535`, `focusAuto.maxEncodableValue == 255`.

In `FocusCommandTests.swift`: `focusAcceptsRange` also accepts `"65535"` and `"300"`; `focusRejectsBadInput` arguments become `[["65536"], ["-1"], ["abc"], []]`; `validationErrorExitCodeIsUsage` parses `["70000"]`.

In `CLIBehaviourTests.swift`: keep the test named `focusOutOfRangeIsUsageError`, but change it to run `["focus", "70000"]`, expect status 64 and stderr containing `"between 0 and 65535"`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `scripts/swift-test --filter FocusApplyTests`
Expected: build failure, `cannot find 'applyFocus' in scope` (or `FocusTarget`).

- [ ] **Step 3: Implement**

- `maxEncodableValue` in `Controls.swift`.
- `focusRange()` and the `Int` `setFocus` in `FocusControl.swift`. Change the comment above `setFocus` to `/// Manual focus within focusRange(); lower is nearer.` so no `255` remains there.
- `FocusApply.swift`: the protocol, the `OpalDevice` conformance, and `applyFocus`. Order inside `applyFocus`, from the spec: empty targets → `fail("no Opal camera attached")`, return `ExitStatus.noDevice`. Then read every range first. If any read range does not contain `position`, `fail` one line per offending camera, write nothing, return 64. Otherwise write to each camera whose range was read (`log("set focus position \(position) on \(label)")` on success, `fail("\(label): \(error)")` on throw); report each range-read failure as `fail("\(label): \(error)")`; return 2 if anything failed, else 0.
- `Focus` in `FocusCommands.swift`:
  - abstract: `"Set a fixed focus position (lower is nearer; run status to see the camera's range)."`
  - argument help: `"Lens position within the camera's range (see status)."`
  - `validate()`: `0...CameraTerminalControl.focusAbsolute.maxEncodableValue`, else `ValidationError("position must be between 0 and \(max)")`.
  - `run()`: `let code = applyFocus(position, to: try OpalDevice.find(), log: Output.line, fail: Output.error)`; `if code != ExitStatus.ok { throw ExitCode(code) }`.

- [ ] **Step 4: Run all tests**

Run: `scripts/swift-test`
Expected: all suites pass, including `FocusApplyTests`, `FocusCommandTests`, `CLIBehaviourTests`.

- [ ] **Step 5: Docs**

- `CHANGELOG.md` under `## [Unreleased]` → `### Changed`: "`focus` checks the position against the range the camera reports instead of a fixed 0 to 255, and rejects an out-of-range value without moving the lens on any camera. With no camera attached, an out-of-range value now exits 1 (no camera) instead of 64."
- `README.md`: replace any "0 to 255" wording for `focus` with "within the range `status` shows (0 to 255 on the Opal C1)".
- `docs/ARCHITECTURE.md`: list `FocusApply.swift` next to `KickLoop.swift`.

- [ ] **Step 6: Commit, push, open the draft PR**

```bash
git add -A Sources Tests CHANGELOG.md README.md docs/ARCHITECTURE.md
git commit   # message: why the range now comes from the camera; last line "Hardware check: pending, done once for the 0.2.0 release."
git push -u origin 0.2.0
gh pr create --draft --base main --head 0.2.0 --title "0.2.0: focus range from the camera, status --json, doctor, unplug logs" --body "Implements docs/superpowers/plans/2026-10-16-opal-autofocus-0.2.0.md. Hardware check pending; do not merge before it."
```
Expected: PR URL printed. Then `gh pr checks --watch` ends with the CI job passing.

---

### Task 2: `status --json`

**Files:**
- Modify: `Sources/OpalUVC/OpalDevice.swift` (add `locationString`, use it in `label`)
- Create: `Sources/OpalAutofocusCLI/CameraSnapshot.swift`
- Create: `Sources/OpalAutofocusCLI/StatusJSON.swift`
- Modify: `Sources/OpalAutofocusCLI/StatusCommand.swift`
- Test: `Tests/OpalAutofocusCLITests/StatusJSONTests.swift` (new), `Tests/OpalAutofocusCLITests/CLIBehaviourTests.swift`
- Docs: `CHANGELOG.md`, `README.md`, `docs/ARCHITECTURE.md`

**Interfaces:**
- Consumes: `FocusStatus` (OpalUVC), `OpalDevice.find()`, `Connection.focusStatus()`.
- Produces:
  - `OpalDevice.locationString: String` = `String(format: "0x%08x", locationID)`; `label` uses it (label text unchanged).
  - `struct CameraSnapshot: Equatable { let model: String; let serial: String?; let location: String; let label: String; let reading: Reading }` with `enum Reading: Equatable { case status(FocusStatus); case failed(String) }` and `static func take(_ device: OpalDevice) -> CameraSnapshot` (opens the device and reads `focusStatus()`; any thrown error becomes `.failed("\(error)")`).
  - `enum StatusJSON { static let schema = 1; static func render(_ cameras: [CameraSnapshot]) -> String }`.
  Task 3 uses `CameraSnapshot` and `Reading`.

- [ ] **Step 1: Write the failing tests**

`StatusJSONTests.swift` parses the rendered string with `JSONSerialization` and checks values, plus one key-order check:

```swift
@Test func rendersOneCamera()
// snapshot: model "Opal C1", serial "1944301031042E1800", location "0x01220000",
//   reading .status(FocusStatus(autofocus: true, position: 130, minimum: 0, maximum: 255, defaultPosition: 130))
// parsed["schema"] == 1; cameras[0] has exactly the keys
//   autofocus(true) default(130) location maximum(255) minimum(0) model position(130) serial

@Test func nullSerialIsExplicitNull()
// serial nil → cameras[0]["serial"] is NSNull

@Test func failedCameraHasErrorAndNoFocusFields()
// reading .failed(Boom.message) → keys exactly model, serial, location, error

@Test func noCameras()
// render([]) parses to ["cameras": [], "schema": 1]

@Test func keysAreSortedAndPretty()
// render output contains "\"cameras\" : [" and "\"schema\" : 1", and "cameras" appears before "schema"
```

`CLIBehaviourTests.swift`, two tests gated on whether a camera is attached:

```swift
@Test(.disabled(if: opalAttached, "needs no camera attached"))
func statusJSONWithoutCameraIsOnlyJSON()
// run(["status", "--json"]): status == 1; stdout parses as JSON equal to ["cameras": [], "schema": 1]

@Test(.enabled(if: opalAttached, "needs a camera"))
func statusJSONWithCameraParses()
// run(["status", "--json"]): status == 0; stdout parses; cameras.count >= 1; cameras[0]["model"] == "Opal C1"
```
(`status` only reads; it never writes to the camera, so the attached test is safe.)

- [ ] **Step 2: Run to verify failure**

Run: `scripts/swift-test --filter StatusJSONTests`
Expected: build failure, `cannot find 'StatusJSON' in scope`.

- [ ] **Step 3: Implement**

- `locationString` in `OpalDevice.swift`.
- `CameraSnapshot.swift` as in Interfaces.
- `StatusJSON.render`: `JSONEncoder` with `[.prettyPrinted, .sortedKeys]` over a private `Encodable` type with a custom `encode(to:)`, so `serial` is encoded as `null` when nil (`encodeNil`) and the focus fields are omitted for `.failed`. Field names: `model, serial, location, autofocus, position, minimum, maximum, default, error`. Top level: `cameras`, `schema`.
- `Status`: add `@Flag(help: "Print JSON (see README for the format).") var json = false`. When `json`: take snapshots of `OpalDevice.find()`, print `StatusJSON.render(...)` with `Output.line`, write each `.failed` reading's message to stderr with `Output.error("\(label): \(message)")`, then exit 1 if there are no cameras, 2 if any failed. When not `json`: the current code path, unchanged.

- [ ] **Step 4: Run all tests**

Run: `scripts/swift-test`
Expected: all pass.

- [ ] **Step 5: Docs**

- `CHANGELOG.md` → `### Added`: "`status --json` prints the camera list as JSON for scripts and menu bar apps; the format is documented in the README."
- `README.md`: a short "Scripting" section with the example object from the spec and the rule: "`schema` changes only when a field is removed or its meaning changes. New fields can appear without a bump." Mention exit codes 0, 1, 2 and that errors go to stderr.
- `docs/ARCHITECTURE.md`: list `CameraSnapshot.swift` and `StatusJSON.swift`.

- [ ] **Step 6: Commit and push**

Commit (OpalUVC touched, so include the hardware-check line), `git push`, then `gh pr checks --watch` passes.

---

### Task 3: Doctor checks (pure logic and rendering)

**Files:**
- Create: `Sources/OpalAutofocusCLI/DoctorEnvironment.swift`
- Create: `Sources/OpalAutofocusCLI/Doctor.swift`
- Test: `Tests/OpalAutofocusCLITests/DoctorTests.swift` (new, with a `FakeDoctorEnvironment`)

**Interfaces:**
- Consumes: `CameraSnapshot`, `CameraSnapshot.Reading` (Task 2), `FocusStatus.summary`, `OpalUVC.version`.
- Produces:
  ```swift
  protocol DoctorEnvironment {
      var home: String { get }
      var userID: UInt32 { get }
      var executablePath: String { get }
      func fileExists(_ path: String) -> Bool
      func plist(at path: String) -> [String: Any]?      // nil when missing or unparseable
      func isLoaded(label: String) -> Bool
      func cameras() throws -> [CameraSnapshot]
      func lastLines(of path: String, count: Int) -> [String]?   // nil when the file is missing
  }

  enum CheckStatus: Equatable { case ok, note, fail }   // rendered "ok", "note", "FAIL"
  struct CheckLine: Equatable { let status: CheckStatus; let topic: String; let message: String; let fix: String? }
  struct LogExcerpt: Equatable { let path: String; let lines: [String] }
  struct DoctorReport: Equatable {
      let header: String
      let checks: [CheckLine]
      let logs: [LogExcerpt]
      var failed: Bool { get }          // any check with .fail
      func render() -> String
  }
  enum Doctor {
      static let eventAgentLabel = "com.opal-autofocus.agent"
      static let brewLabel = "homebrew.mxcl.opal-autofocus"
      static let composerDaemonPath = "/Library/LaunchDaemons/com.opalcamera.Opal.v2.cameraExtensionShim.plist"
      static func run(_ env: DoctorEnvironment) -> DoctorReport
  }
  ```
  Plist paths: `"\(home)/Library/LaunchAgents/\(label).plist"` for both labels.

Rules (copy from the spec, section "3. doctor"; summarised here so the tests are unambiguous):

- Header: `"opal-autofocus \(OpalUVC.version) at \(executablePath)"`.
- Setup (exactly one line, first matching rule wins), topic `setup`:
  1. both loaded → fail, `"two setups are loaded; use one"`, fix `"brew services stop opal-autofocus"`.
  2. one loaded → ok, `"event-driven launchd agent loaded (com.opal-autofocus.agent)"` or `"Homebrew watcher loaded (homebrew.mxcl.opal-autofocus)"`. If the other plist exists, an extra note, topic `setup`, `"leftover plist, not loaded: <path>"`, no fix.
  3. none loaded, a plist exists → fail, `"installed but not loaded"`, fix: event-driven plist present → `launchctl bootstrap gui/<uid> "<path>"` (path always in double quotes); only the Homebrew plist present → `brew services start opal-autofocus`.
  4. nothing installed → fail, `"nothing will re-enable autofocus after a replug"`, fix `"brew services start opal-autofocus, or make install from a source checkout"`.
- Agent program, topic `agent`, one line per existing plist: read `ProgramArguments[0]`, falling back to `Program`. Missing file → fail `"\(label) runs \(path), which does not exist"`, fix `"reinstall with the method that created \(plistPath)"`. Plist unparseable or no program key → fail `"cannot read \(plistPath)"`, same fix. Else ok `"\(label) runs \(path)"`.
- Composer, topic `composer`: if `fileExists(composerDaemonPath)`, note with the spec's sentence, no fix. Otherwise no line.
- Cameras, topics `camera` and `controls`: `cameras()` throwing → fail `camera`, `"cannot list cameras: \(error)"`. Empty → fail `camera`, `"no Opal camera found"`, fix `"plug the camera in; if it is behind a hub, plug it into the hub or Mac directly to rule the hub out"`. Per camera: ok `camera` with its `label`, then `controls`: `.failed(msg)` → fail `"\(label): \(msg)"`; autofocus off → fail `"\(label): autofocus is off"`, fix `"opal-autofocus enable; if it is off again after every replug, check the setup line above"`; else ok `"\(label): \(summary)"`.
- Logs: for each existing plist, `StandardOutPath` → `lastLines(of:count: 5)`; append a `LogExcerpt` when non-nil. Skip duplicates of the same path.
- Render: header, blank line, each check as `String(statusWord.padding(toLength: 6, withPad: " ", startingAt: 0)) + "\(topic): \(message)"`, its fix (if any) on the next line as `"      fix: \(fix)"`; then for each excerpt a blank line, `"recent log (\(path)):"`, and each line prefixed with two spaces. Ends with a newline.

- [ ] **Step 1: Write the failing tests**

`FakeDoctorEnvironment` is a struct with stored properties for every protocol member (`files: Set<String>`, `plists: [String: [String: Any]]`, `loaded: Set<String>`, `cameraList: Result<[CameraSnapshot], Boom>`, `logs: [String: [String]]`). Tests, each asserting on `Doctor.run(env).checks` (and `failed`) with exact strings from the rules above:

```swift
@Test func eventAgentOnlyIsOk()
@Test func brewOnlyIsOk()
@Test func bothLoadedFails()                      // fix == "brew services stop opal-autofocus"
@Test func loadedPlusLeftoverPlistAddsNote()
@Test func installedNotLoadedSuggestsBootstrap()  // fix == "launchctl bootstrap gui/501 \"/Users/a/Library/LaunchAgents/com.opal-autofocus.agent.plist\""
@Test func bootstrapFixQuotesPathWithSpace()      // home "/Users/Jane Doe"; fix contains "\"/Users/Jane Doe/Library/LaunchAgents/com.opal-autofocus.agent.plist\""
@Test func brewInstalledNotLoadedSuggestsBrewStart()
@Test func nothingInstalledFails()
@Test func staleProgramPathFails()
@Test func unreadablePlistFails()                 // plist file exists but plist(at:) returns nil
@Test func programKeyFallback()                   // plist has "Program" only; ok line names it
@Test func composerDaemonIsNoteNotFailure()       // everything else ok → failed == false, a .note line with topic "composer"
@Test func noComposerNoLine()
@Test func noCameraFailsWithHubHint()
@Test func cameraListErrorFails()
@Test func autofocusOffFails()
@Test func twoCamerasOneOff()                     // one ok controls line, one fail controls line, failed == true
@Test func allGoodIsNotFailed()                   // failed == false
@Test func logExcerptFromStandardOutPath()        // plist StandardOutPath "/tmp/x.log", logs["/tmp/x.log"] = ["a","b"] → logs == [LogExcerpt(path: "/tmp/x.log", lines: ["a","b"])]
@Test func missingLogFileIsSkipped()
@Test func renderMatchesSpecLayout()              // one ok, one fail with fix, one excerpt; compare the whole rendered string
```

- [ ] **Step 2: Run to verify failure**

Run: `scripts/swift-test --filter DoctorTests`
Expected: build failure, `cannot find 'Doctor' in scope`.

- [ ] **Step 3: Implement** `DoctorEnvironment.swift` (protocol only) and `Doctor.swift` (types, `run`, `render`) per Interfaces and Rules.

- [ ] **Step 4: Run all tests**

Run: `scripts/swift-test`
Expected: all pass.

- [ ] **Step 5: Commit and push**

No CHANGELOG line yet (the command is not wired up until Task 4). `git push`; CI passes.

---

### Task 4: `doctor` command and live environment

**Files:**
- Create: `Sources/OpalAutofocusCLI/LiveDoctorEnvironment.swift`
- Create: `Sources/OpalAutofocusCLI/DoctorCommand.swift`
- Modify: `Sources/OpalAutofocusCLI/OpalAutofocus.swift` (register `Doctor` command)
- Test: `Tests/OpalAutofocusCLITests/FocusCommandTests.swift` (`subcommandsRegistered`), `Tests/OpalAutofocusCLITests/CLIBehaviourTests.swift`, `Tests/OpalAutofocusCLITests/LiveDoctorEnvironmentTests.swift` (new)
- Docs: `CHANGELOG.md`, `README.md`, `docs/ARCHITECTURE.md`

**Interfaces:**
- Consumes: `DoctorEnvironment`, `Doctor.run`, `DoctorReport.render()`, `DoctorReport.failed` (Task 3); `CameraSnapshot.take` (Task 2).
- Produces: `struct LiveDoctorEnvironment: DoctorEnvironment` and `struct DoctorCommand: ParsableCommand` with `commandName: "doctor"`.

- [ ] **Step 1: Write the failing tests**

- `subcommandsRegistered` and `helpListsSubcommands` include `"doctor"`.
- `LiveDoctorEnvironmentTests`, using a temp directory from `FileManager.default.temporaryDirectory`:
  - `plistReadsDictionary`: write a plist with `ProgramArguments = ["/bin/echo"]`, `plist(at:)?["ProgramArguments"]` equals `["/bin/echo"]`.
  - `plistReturnsNilForGarbage`: a file containing `"not a plist"` → `nil`.
  - `lastLinesReturnsTail`: a file with lines `1`...`8` → `lastLines(of:count: 5) == ["4","5","6","7","8"]`; trailing newline does not produce an empty last element.
  - `lastLinesNilWhenMissing`.
  - `isLoadedFalseForUnknownLabel`: `isLoaded(label: "com.example.does-not-exist") == false`.
- `CLIBehaviourTests.doctorRuns`: `run(["doctor"])` exits 0 or 1 and stdout starts with `"opal-autofocus "` (the machine's setup decides which; both are valid).

- [ ] **Step 2: Run to verify failure**

Run: `scripts/swift-test --filter LiveDoctorEnvironmentTests`
Expected: build failure, `cannot find 'LiveDoctorEnvironment' in scope`.

- [ ] **Step 3: Implement**

- `LiveDoctorEnvironment`: `home` from `FileManager.default.homeDirectoryForCurrentUser.path`; `userID` from `getuid()`; `executablePath` from `Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]` (`arguments[0]` alone is just `opal-autofocus` when run from PATH); `plist(at:)` via `PropertyListSerialization` (nil on any failure); `isLoaded` runs `/bin/launchctl print gui/<uid>/<label>` with `Process`, stdout and stderr to `FileHandle.nullDevice`, true when exit status is 0; `cameras()` is `try OpalDevice.find().map(CameraSnapshot.take)`; `lastLines` reads the file as UTF-8 and returns the last `count` non-empty lines.
- `DoctorCommand`: abstract `"Check the install, the camera and known interference, and print fixes. Changes nothing."`, discussion `"Exits 0 when every check passes and 1 when any check failed."`. `run()`: print `Doctor.run(LiveDoctorEnvironment()).render()` (without an extra trailing newline), then `throw ExitCode(1)` if `failed`.
- Register in `OpalAutofocus.configuration.subcommands` after `Status`.

- [ ] **Step 4: Run all tests**

Run: `scripts/swift-test`
Expected: all pass. Also run `swift build && .build/debug/opal-autofocus doctor; echo "exit $?"` and read the output: it must list a setup line, camera lines and (on this machine) a recent log.

- [ ] **Step 5: Docs**

- `CHANGELOG.md` → `### Added`: "`doctor` checks the launchd or Homebrew setup, the agent's program path, the camera and its controls, notes Opal Composer's helper, shows recent log lines, and prints a fix for each problem. It changes nothing."
- `README.md` troubleshooting: lead with "Run `opal-autofocus doctor` first and include its output in bug reports." Keep the existing bullets.
- `docs/ARCHITECTURE.md`: list the four doctor files and say the logic is tested with a fake environment.

- [ ] **Step 6: Commit and push**

`git push`; CI passes.

---

### Task 5: Unplug logging in `watch`

**Files:**
- Modify: `Sources/OpalUVC/DeviceWatcher.swift`
- Modify: `Sources/OpalUVC/OpalDevice.swift` (`label` fallback)
- Modify: `Sources/OpalAutofocusCLI/WatchCommand.swift`
- Test: `Tests/OpalUVCTests/DeviceWatcherTests.swift`, `Tests/OpalUVCTests/DeviceDiscoveryTests.swift` (or wherever `label` is tested)
- Docs: `CHANGELOG.md`, `docs/ARCHITECTURE.md`

**Interfaces:**
- Produces:
  - `DeviceWatcher.init(models: [CameraModel] = KnownModels.all, queue: DispatchQueue = .main, onAttach: @escaping (OpalDevice) -> Void, onDetach: ((OpalDevice) -> Void)? = nil)`. Existing call sites (trailing closure for `onAttach`) keep compiling.
  - `OpalDevice.label` returns just `model.name` when `serial == nil && locationID == 0`; otherwise unchanged.

- [ ] **Step 1: Write the failing tests**

- `DeviceWatcherTests.startWithDetachHandlerReportsAttachOnly`: a watcher with both handlers on a private queue; after `start()` and `queue.sync {}`, attach count equals `OpalDevice.find().count` and detach count is 0; `stop()` then `start()` again works.
- A label test: an `OpalDevice` built with no serial and location 0 has `label == "Opal C1"`. `OpalDevice.init` is internal and takes an `io_service_t`; add an internal init `init(model: CameraModel, serial: String?, locationID: UInt32)` used only by tests and by `init(service:model:)` if that keeps things simple, with `service` set to `0` (IOObjectRelease on 0 is a no-op).

- [ ] **Step 2: Run to verify failure**

Run: `scripts/swift-test --filter DeviceWatcherTests`
Expected: build failure on the extra `onDetach` argument.

- [ ] **Step 3: Implement**

- For each model, register a second notification with `kIOTerminatedNotification` and the same matching dictionary, only when `onDetach` is non-nil. Drain it once at start to arm it (it reports nothing on start). The callback needs to know the model: keep an array of small registration objects `final class Registration { unowned let watcher: DeviceWatcher; let model: CameraModel }` owned by the watcher, pass `Unmanaged.passUnretained(registration).toOpaque()` as the refcon, and release them in `stop()`. For each terminated service, build `OpalDevice(service:model:)` with the registration's model (do not call `model(for:among:)`; a terminated service may have lost its properties) and call `onDetach`.
- `stop()` releases the terminated iterators too.
- `WatchCommand`: pass `onDetach: { Output.line("\(Output.timestamp()) detached: \($0.label)") }`.

- [ ] **Step 4: Run all tests**

Run: `scripts/swift-test`
Expected: all pass.

- [ ] **Step 5: Docs, commit, push**

- `CHANGELOG.md` → `### Added`: "`watch` logs a `detached:` line when a camera is unplugged."
- `docs/ARCHITECTURE.md`: `DeviceWatcher.swift` entry mentions attach and detach notifications.
- Commit with the hardware-check line; `git push`; CI passes.

---

### Task 6: Hand-off

**Files:** none new.

- [ ] **Step 1: Final verification**

Run: `swift build -c release && scripts/swift-test && ruby -c packaging/Formula/opal-autofocus.rb && plutil -lint packaging/com.opal-autofocus.agent.plist`
Expected: all succeed. `gh pr checks` shows the CI job passing on the latest push.

- [ ] **Step 2: Read the diff against the spec**

Run: `git diff main...0.2.0 --stat` and read `CHANGELOG.md` `Unreleased`. Each of the four spec items has its CHANGELOG line; README documents `status --json` and `doctor`; ARCHITECTURE lists every new file. No file outside `Models.swift`/`Controls.swift` contains `255`, `0x03e7`, `0xf63d` or a control selector, except tests and docs: `grep -rn "255\|0x03e7\|0xf63d" Sources | grep -v "Models.swift\|Controls.swift"` prints nothing.

- [ ] **Step 3: Update the PR and stop**

Edit the PR body (`gh pr edit 0.2.0 --body ...`) to add the spec's "Hardware check and release" checklist, steps 1 to 4, as unchecked boxes for the user. Leave the PR as a draft. Do not merge, tag, bump the version or touch the tap; the release happens after the user's hardware check.
