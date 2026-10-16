# What the Opal C1 exposes

Findings from 2026-10-16 on one Opal C1 (USB `03e7:f63d`, device release
0x0410) on macOS 27, Apple Silicon.

## Interfaces

| # | Class | Name | Notes |
|---|---|---|---|
| 0 | 0xff vendor | `S_BULKDATA` | XLink bulk endpoints 0x01 and 0x81. Does not answer XLink connects while the camera runs its UVC firmware. |
| 1 | 0x0e/0x01 | UVC VideoControl | Input (camera) terminal 1, processing unit 3, extension unit 4 (GUID all 0xff, its reads return junk), output terminal 2. |
| 2 | 0x0e/0x02 | UVC VideoStreaming | Bulk endpoint 0x82. |
| 3 | 0x01/0x01 | Audio control | |
| 4 | 0x01/0x02 | Audio streaming | Microphone. |

## Focus controls

Camera terminal unit 1, interface 1 (`wIndex = 0x0101`):

| Control | Selector | Size | Reported by the camera | Effect |
|---|---|---|---|---|
| Focus, Auto | 0x08 | 1 | INFO 0x01, MIN 0, MAX 1, DEF 1 | SET_CUR 0 parks the lens. SET_CUR 1 after 0 enables continuous autofocus. |
| Focus, Absolute | 0x06 | 2 | INFO 0x03, MIN 0, MAX 255, DEF 130 | Honoured when Focus-Auto is 0. 0 is nearest, 255 farthest. GET_CUR returns the last written value, not the live lens position. |

Focus-Auto's INFO byte advertises GET only, yet the camera accepts SET_CUR on
it. Both effects were confirmed by hand: with Focus-Auto at 0, a hand held
near the lens stays blurry; after SET_CUR Focus-Auto = 1 it comes into focus
and keeps tracking. A frame-sharpness measurement (variance of the Laplacian
on captured frames) agreed: it dropped sharply at both manual extremes and
returned to its original level after Focus-Auto = 1.

On a fresh plug-in the camera reports Focus-Auto = 1 while the lens is in fact
parked, and it ignores a SET_CUR of 1 in that state. Autofocus starts only when
the control goes from 0 to 1, so this tool always writes 0 and then 1. This was
confirmed on a cold camera with Opal Composer and all of its helpers removed:
writing 1 alone left the lens parked, writing 0 then 1 started autofocus.

## What Opal Composer does

Composer's `OpalCameraUVCService` helper is a standard UVC controller built on
libusb. Its autofocus path sends SET_CUR on `CT_FOCUS_AUTO_CONTROL` (selector
8, one byte, value 1) to unit 1, interface 1. This tool sends the same
request, preceded by a write of 0 (see above). No vendor request, extension-unit write, XLink message or firmware
upload is involved.

Composer's `OpalCameraDeviceService` links Luxonis depthai and libusb. It
also contains a one-shot request (`bRequest 0xF5`, `wValue 0x0DA1`) addressed
to a sibling product id, `03e7:f63b`. That looks like a mode switch for a
camera enumerating in another state, and it was not needed here.

## Things that did not work

- Connecting over XLink (depthai 2.15 or 2.33) to the running camera: the
  first bulk write never completes. The camera reports `FLASH_BOOTED`, and
  depthai's normal path would reboot it into Luxonis firmware, which is what
  open-opal does and which changes how the camera behaves.
- Reading the live lens position: not exposed.
- Power-cycling the hub port with `uhubctl` on a VIA Labs hub re-enumerated
  the device but did not reset its focus state; only a physical replug does.

## Composer's background helper

Composer installs a root LaunchDaemon,
`com.opalcamera.Opal.v2.cameraExtensionShim`, that stays running after
Composer quits. While it was installed, the camera sometimes came up with
autofocus already working after a replug. With the daemon removed, every cold
plug-in leaves the lens parked until this tool runs. Composer also installs a
camera system extension (`opalCameraExtension`); it provides Composer's virtual
camera and contains no USB code, so it does not affect focus.

## Method

- `system_profiler SPUSBHostDataType` and `ioreg -p IOUSB -l` for ids and
  interface layout; a short pyusb script to read and parse the configuration
  descriptor.
- A small C program using `IOUSBDeviceInterface::DeviceRequest` to read and
  write the controls while Photo Booth or ffmpeg streamed.
- ffmpeg frame grabs plus the Laplacian-variance measurement above.
- `strings` and static disassembly of Composer's helpers to confirm which
  request it sends. Nothing from Composer is redistributed.
