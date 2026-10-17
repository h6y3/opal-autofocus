# Architecture

## Targets

- `COpalUSB` (C) wraps IOKit's COM-style `IOUSBDeviceInterface` in three
  functions: `opal_usb_open`, `opal_usb_request`, `opal_usb_close`. Swift
  cannot call the function pointers in those interfaces directly, so the shim
  exists. It opens the device at device level and never claims an interface,
  which is why it coexists with the system UVC driver while other apps stream.
- `OpalUVC` (Swift library):
  - `Models.swift`: table of supported cameras (VID, PID, camera terminal id,
    control interface). Add a model here.
  - `Controls.swift`: the UVC camera terminal controls we use (selector,
    size). Add a control here.
  - `UVCRequest.swift`: packs a class request (`bmRequestType`, `bRequest`,
    `wValue = selector << 8`, `wIndex = unit << 8 | interface`) and
    little-endian payloads.
  - `OpalDevice.swift`: IOKit matching and discovery.
  - `Connection.swift`: an open handle; `perform(_:payload:)` runs one request.
  - `FocusControl.swift`: `enableAutofocus`, `disableAutofocus`, `setFocus`,
    `focusRange`, `focusStatus`.
  - `DeviceWatcher.swift`: IOKit first-match notifications on a dispatch queue.
  - `UVCError.swift`: errors carrying the IOReturn and the request name.
- `OpalAutofocusCLI` (executable `opal-autofocus`): swift-argument-parser
  subcommands. `KickLoop.swift` holds the polling loop for `run` behind a small
  protocol so it is tested with fakes. `FocusApply.swift` holds the range check
  and write pass for `focus` behind a small protocol so it is tested with
  fakes. `CameraSnapshot.swift` reads one camera's state into a value the CLI
  renders. `StatusJSON.swift` renders those values as the `status --json`
  output. `Doctor.swift` holds the `doctor` checks as pure logic over the small
  `DoctorEnvironment` protocol (`DoctorEnvironment.swift`);
  `LiveDoctorEnvironment.swift` implements that protocol against the real
  system (the launchd plists, `launchctl print` per label, the camera list
  and the log tail) and `DoctorCommand.swift` carries the subcommand. The
  doctor logic is tested with a fake environment. `WatchKick.swift` holds
  what `watch` does when the watcher reports an attach. `Retry.swift` holds the retry
  policy both share. `LaunchEventDrain.swift` consumes the launchd event (see
  below).

## Process model

Both modes send the same USB request.

1. Event-driven agent (`packaging/com.opal-autofocus.agent.plist`, installed
   by `make install`). launchd watches IOKit for VID 0x03e7 / PID 0xf63d and
   starts `opal-autofocus run --quiet-missing --launchd` when the camera
   appears. `run` polls for up to 5 s, enables autofocus, and exits. Nothing
   runs while the camera is unplugged. `RunAtLoad` covers logging in with the
   camera already attached.

   A job launched by `com.apple.iokit.matching` must take the event off the
   stream, or launchd keeps relaunching it every few seconds. `--launchd`
   registers `xpc_set_event_stream_handler` and waits up to one second for
   the pending event before doing its work.

2. Resident watcher (`opal-autofocus watch`, used by `brew services`).
   Homebrew's service DSL cannot express `LaunchEvents`, so brew users get a
   process that sleeps in the run loop and is woken by IOKit on attach.

## Error handling

`UVCError` names the failed request and the IOReturn. Both modes send the
autofocus writes through `Retry`: up to three attempts, 0.5 s and 1 s apart,
with each failed attempt but the last logged. This is a guard in case a freshly
attached camera rejects a request before the UVC driver settles; no such
failure has been seen yet. Only the last error is reported. The CLI maps
outcomes to exit codes 0, 1 and 2; `run --quiet-missing` turns "no device"
into 0 so launchd does not record a failure when the camera leaves before we
start. With several cameras, each is handled independently and the exit code
is the worst result.

## Testing

`scripts/swift-test` runs the suite. Tests use Swift Testing, which ships with
the Command Line Tools; the script adds the macro plugin path those installs
need. Unit tests cover request packing, the model table, the polling loop and
argument handling. `CLIBehaviourTests` runs the built binary. Hardware
behaviour is checked by hand with `make smoke`.

## Adding another Opal model

1. Read its descriptors (`ioreg -p IOUSB -l`, or the UVC descriptor parse
   described in `docs/PROTOCOL.md`) to get the camera terminal id and control
   interface.
2. Add a `CameraModel` to `KnownModels.all`.
3. Add an entry for its PID to the `LaunchEvents` block in the plist.
4. Run `make smoke` against the hardware and record the result in
   `docs/PROTOCOL.md`.
