# opal-autofocus

Keeps the Opal C1 webcam's autofocus working on macOS without running Opal
Composer.

## Why

The Opal C1 is a good UVC webcam, but on a fresh plug-in its autofocus stays
parked at one distance until Opal Composer has talked to it. Composer is heavy
and no longer well maintained. Autofocus is controlled by the standard UVC
"Focus, Auto" control, which the camera only honours when it changes from off
to on. This tool flips that control off and on whenever the camera is attached
and otherwise stays out of the way. The camera
remains an ordinary UVC device for every app.

## Install

### Homebrew

    brew install h6y3/tap/opal-autofocus
    brew services start opal-autofocus

`brew services` runs `opal-autofocus watch`, a resident process that sleeps
until the camera is attached. If you would rather have nothing running while
the camera is unplugged, follow the caveats printed by `brew install` to load
the event-driven launchd agent instead. Use one or the other, not both.

### From source

    git clone https://github.com/h6y3/opal-autofocus.git
    cd opal-autofocus
    make install

`make install` builds a release binary into `~/.local/bin`, writes
`~/Library/LaunchAgents/com.opal-autofocus.agent.plist`, and loads it. launchd
starts the agent only when an Opal C1 appears; it enables autofocus and exits.
Remove everything with `make uninstall`. Set `PREFIX` to install elsewhere,
for example `make install PREFIX=/usr/local`. The agent uses the full path,
but to run the commands below yourself, `~/.local/bin` must be on your `PATH`.

Requirements: macOS 14 or newer and a Swift 6 toolchain (Xcode 16, or the
Command Line Tools from `xcode-select --install`).

## Usage

    opal-autofocus status          # show attached cameras and focus state
    opal-autofocus enable          # turn continuous autofocus on
    opal-autofocus disable         # park the lens where it is
    opal-autofocus focus 180       # fixed focus position within the range status shows (0 to 255 on the Opal C1)
    opal-autofocus run             # what the launchd agent runs
    opal-autofocus watch           # stay resident and handle each attach

Exit codes: 0 success, 1 no camera attached, 2 the camera rejected a request,
64 invalid arguments.

`focus` is the closest the hardware gets to background blur. The C1 has a
fixed aperture, so the only way to soften a background is to put the focus
plane where you want it. Composer's blur is done in software and is not part
of this tool.

## Scripting

`opal-autofocus status --json` prints one JSON object with every attached
camera, and errors are written to stderr so stdout stays parseable. Exit
codes: 0 success, 1 no camera attached, 2 the camera rejected a request.
A camera whose controls could not be read appears with an `error` field and
no focus fields.

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

`schema` changes only when a field is removed or its meaning changes. New
fields can appear without a bump.

## Troubleshooting

- Run `opal-autofocus doctor` first and include its output in bug reports.
- `opal-autofocus status` prints the control values the camera reports. If
  `autofocus: off` persists after `enable`, include that output in a bug
  report together with `system_profiler SPUSBHostDataType | grep -A10 Opal`.
- Agent logs: `~/Library/Logs/opal-autofocus/agent.log` (make install) or
  `$(brew --prefix)/var/log/opal-autofocus.log` (brew services).
- The camera takes a few seconds to start after it is plugged in, so focus
  may hunt briefly before it settles.
- Composer can stay installed; the two do not conflict. You can also remove
  it entirely: this tool does not need any of its parts.

## How it works

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the code layout and
[docs/PROTOCOL.md](docs/PROTOCOL.md) for what the camera exposes and how that
was found.

## Prior art

- [cansik/open-opal](https://github.com/cansik/open-opal) drives the C1
  through Luxonis depthai, which reboots the camera into a different mode.
  Useful for computer vision; not a drop-in webcam fix.
- [luxonis/depthai-core](https://github.com/luxonis/depthai-core) is the
  framework the camera's chip is built around.

This project is not affiliated with Opal Camera.

## License

MIT. See [LICENSE](LICENSE).
