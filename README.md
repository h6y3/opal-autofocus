# opal-autofocus

Keeps the Opal C1 webcam's autofocus working on macOS without running Opal
Composer.

## Why

The Opal C1 is a good UVC webcam, but on a fresh plug-in its autofocus stays
parked at one distance until Opal Composer has talked to it. Composer is heavy
and no longer well maintained. The only thing Composer sends to wake autofocus
is the standard UVC "Focus, Auto" control, so this tool sends that one control
whenever the camera is attached and otherwise stays out of the way. The camera
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
for example `make install PREFIX=/usr/local`.

Requirements: macOS 14 or newer and a Swift 6 toolchain (Xcode 16, or the
Command Line Tools from `xcode-select --install`).

## Usage

    opal-autofocus status          # show attached cameras and focus state
    opal-autofocus enable          # turn continuous autofocus on
    opal-autofocus disable         # park the lens where it is
    opal-autofocus focus 180       # fixed focus position, 0 near to 255 far
    opal-autofocus run             # what the launchd agent runs
    opal-autofocus watch           # stay resident and handle each attach

Exit codes: 0 success, 1 no camera attached, 2 the camera rejected a request,
64 invalid arguments.

`focus` is the closest the hardware gets to background blur. The C1 has a
fixed aperture, so the only way to soften a background is to put the focus
plane where you want it. Composer's blur is done in software and is not part
of this tool.

## Troubleshooting

- `opal-autofocus status` prints the control values the camera reports. If
  `autofocus: off` persists after `enable`, include that output in a bug
  report together with `system_profiler SPUSBHostDataType | grep -A10 Opal`.
- Agent logs: `~/Library/Logs/opal-autofocus/agent.log` (make install) or
  `$(brew --prefix)/var/log/opal-autofocus.log` (brew services).
- `could not open device: kIOReturnExclusiveAccess` means another process
  holds the USB device exclusively, such as a browser tab with WebUSB access.
  Close it and run `opal-autofocus enable`.
- The camera takes a few seconds to start after it is plugged in, so focus
  may hunt briefly before it settles.
- Composer can stay installed; the two do not conflict.

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
