# opal-autofocus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Swift command-line tool plus launchd user agent that enables the Opal C1's autofocus (standard UVC Focus-Auto control) every time the camera is attached, with no Opal Composer and nothing resident while the camera is unplugged.

**Architecture:** One Swift package with three targets: `COpalUSB` (a 60-line C shim around IOKit's COM-style `IOUSBDeviceInterface`, because Swift cannot call the plugin vtables directly), `OpalUVC` (Swift library: device discovery, UVC class requests, focus operations, attach notifications), and `OpalAutofocusCLI` (the `opal-autofocus` executable built on swift-argument-parser). launchd starts `opal-autofocus run` on an IOKit matching event; `watch` is the resident fallback used by `brew services`.

**Tech Stack:** Swift 5.9+, SwiftPM, swift-argument-parser 1.3, IOKit (IOKitLib, IOUSBLib), XCTest, launchd, Homebrew formula, GitHub Actions (macOS runner).

**Spec:** `docs/superpowers/specs/2026-10-16-opal-autofocus-design.md`

## Global Constraints

- Platform: macOS 13 or newer (`platforms: [.macOS(.v13)]`), Apple Silicon and Intel.
- Toolchain: Swift 5.9 or newer; `swift build -c release` must work with no Xcode project.
- Only dependency: `swift-argument-parser` `from: "1.3.0"`. No libusb, no depthai.
- Camera constants: VID `0x03e7`, PID `0xf63d`, camera terminal unit `1`, UVC control interface `1`, Focus-Auto selector `0x08` (1 byte), Focus-Absolute selector `0x06` (2 bytes, 0 to 255).
- Exit codes: `0` success, `1` no device, `2` request failed, argument-parser validation errors use its default (`64`).
- Agent label: `com.opal-autofocus.agent`. Logs: `~/Library/Logs/opal-autofocus/`.
- License: MIT. Changelog: Keep a Changelog format, semantic versions, first release `0.1.0`.
- Commit messages: imperative subject, body explains why. No co-author or model attribution lines (user rule).
- Writing style in all docs: plain sentences, no em dashes, no marketing words.
- GitHub owner is not decided yet. Owner is `h6y3`. Repository `h6y3/opal-autofocus`, tap `h6y3/homebrew-tap`. Use `h6y3` directly in URLs.

## Review Focus

1. Another process holds the device exclusively (e.g. a WebUSB page in Chrome, seen during research): `opal_usb_open` fails with an IOReturn. Expected: `run`/`enable` print the IOReturn name and exit 2, never crash. Pinned in Task 5 (`KickLoop` failure mapping) and Task 3 (`UVCError` description).
2. `focus` with an out-of-range or non-numeric argument (`focus 300`, `focus -1`, `focus abc`). Expected: usage error, exit 64, no USB traffic. Pinned in Task 4 (`Focus` command validation test).
3. The camera detaches between discovery and the control write. Expected: the IOReturn surfaces as exit 2 with the request name, and `watch` keeps running. Pinned in Task 5 (`KickLoop` partial failure test) and Task 6 (`watch` logs and continues).
4. Two Opals attached. Expected: every device is kicked; exit code is the worst result. Pinned in Task 5 (`KickLoop` multi-target tests).
5. `run --timeout 0` and launchd firing for a device that already left. Expected: exactly one discovery attempt, then exit 0 with `--quiet-missing` or 1 without. Pinned in Task 5 (`KickLoop` timeout-zero test and exit mapping test).

---

### Task 1: Package scaffold, license, CI

**Files:**
- Create: `Package.swift`
- Create: `Sources/COpalUSB/include/copalusb.h`, `Sources/COpalUSB/copalusb.c` (empty stubs; real code in Task 3)
- Create: `Sources/OpalUVC/OpalUVC.swift`
- Create: `Sources/OpalAutofocusCLI/OpalAutofocus.swift`
- Create: `Tests/OpalUVCTests/SmokeTests.swift`
- Create: `LICENSE`, `README.md` (short placeholder replaced in Task 10), `.github/workflows/ci.yml`
- Modify: `.gitignore`

**Interfaces:**
- Produces: package layout and target names `COpalUSB`, `OpalUVC`, `OpalAutofocusCLI`, `OpalUVCTests`, `OpalAutofocusCLITests`; product `opal-autofocus`.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "opal-autofocus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "opal-autofocus", targets: ["OpalAutofocusCLI"]),
        .library(name: "OpalUVC", targets: ["OpalUVC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "COpalUSB",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .target(name: "OpalUVC", dependencies: ["COpalUSB"]),
        .executableTarget(
            name: "OpalAutofocusCLI",
            dependencies: [
                "OpalUVC",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "OpalUVCTests", dependencies: ["OpalUVC"]),
        .testTarget(name: "OpalAutofocusCLITests", dependencies: ["OpalAutofocusCLI"]),
    ]
)
```

- [ ] **Step 2: Write the C stub so the target compiles**

`Sources/COpalUSB/include/copalusb.h`:

```c
#ifndef COPALUSB_H
#define COPALUSB_H

#include <stdint.h>
#include <IOKit/IOKitLib.h>

typedef struct opal_usb_device opal_usb_device_t;

kern_return_t opal_usb_open(io_service_t service, opal_usb_device_t **out);
kern_return_t opal_usb_request(opal_usb_device_t *dev, uint8_t bmRequestType, uint8_t bRequest,
                               uint16_t wValue, uint16_t wIndex, void *data, uint16_t length,
                               uint32_t *done);
void opal_usb_close(opal_usb_device_t *dev);

#endif
```

`Sources/COpalUSB/copalusb.c`:

```c
#include "copalusb.h"

struct opal_usb_device { int unused; };

kern_return_t opal_usb_open(io_service_t service, opal_usb_device_t **out) {
    (void)service; (void)out;
    return kIOReturnUnsupported;
}

kern_return_t opal_usb_request(opal_usb_device_t *dev, uint8_t bmRequestType, uint8_t bRequest,
                               uint16_t wValue, uint16_t wIndex, void *data, uint16_t length,
                               uint32_t *done) {
    (void)dev; (void)bmRequestType; (void)bRequest; (void)wValue; (void)wIndex;
    (void)data; (void)length; (void)done;
    return kIOReturnUnsupported;
}

void opal_usb_close(opal_usb_device_t *dev) { (void)dev; }
```

- [ ] **Step 3: Write the Swift stubs**

`Sources/OpalUVC/OpalUVC.swift`:

```swift
/// Version of the OpalUVC library. Bumped with each release.
public enum OpalUVC {
    public static let version = "0.1.0"
}
```

`Sources/OpalAutofocusCLI/OpalAutofocus.swift`:

```swift
import ArgumentParser
import OpalUVC

@main
struct OpalAutofocus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "opal-autofocus",
        abstract: "Keep the Opal C1 webcam's autofocus enabled without Opal Composer.",
        version: OpalUVC.version
    )
}
```

`Tests/OpalUVCTests/SmokeTests.swift`:

```swift
import XCTest
@testable import OpalUVC

final class SmokeTests: XCTestCase {
    func testVersionIsSemver() {
        let parts = OpalUVC.version.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        XCTAssertTrue(parts.allSatisfy { Int($0) != nil })
    }
}
```

`Tests/OpalAutofocusCLITests/` gets a file in Task 5; SwiftPM warns about an empty test target, so create `Tests/OpalAutofocusCLITests/PlaceholderTests.swift` now:

```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func testTargetBuilds() { XCTAssertTrue(true) }
}
```

- [ ] **Step 4: Build and test**

Run: `swift build && swift test`
Expected: build succeeds; 2 tests pass. `swift run opal-autofocus --help` prints the abstract.

- [ ] **Step 5: Add LICENSE, placeholder README, CI, gitignore entries**

`LICENSE`: the MIT license text with `Copyright (c) 2026 h6y3`.

`README.md` (replaced in Task 10):

```markdown
# opal-autofocus

Keeps the Opal C1 webcam's autofocus enabled on macOS without Opal Composer.
Work in progress; see `docs/superpowers/specs/` for the design.
```

`.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
jobs:
  build-and-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: swift --version
      - run: swift build
      - run: swift test
```

`.gitignore` already lists `.build/`, `*.xcodeproj` and `.swiftpm/`; leave it as is. `Package.resolved` is committed on purpose so builds are reproducible.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests LICENSE README.md .github .gitignore
git commit -m "Scaffold Swift package with C shim, library, CLI and CI"
```

---

### Task 2: Models, controls, request encoding

**Files:**
- Create: `Sources/OpalUVC/Models.swift`, `Sources/OpalUVC/Controls.swift`, `Sources/OpalUVC/UVCRequest.swift`
- Test: `Tests/OpalUVCTests/UVCRequestTests.swift`, `Tests/OpalUVCTests/ModelsTests.swift`

**Interfaces:**
- Produces:
  - `public struct CameraModel: Equatable { name: String; vendorID: UInt16; productID: UInt16; cameraTerminalID: UInt8; controlInterface: UInt8 }`
  - `public enum KnownModels { static let opalC1: CameraModel; static let all: [CameraModel]; static func match(vendorID: UInt16, productID: UInt16) -> CameraModel? }`
  - `public struct CameraTerminalControl: Equatable { name: String; selector: UInt8; size: Int; static let focusAbsolute; static let focusAuto }`
  - `public struct UVCRequest: Equatable { enum Code: UInt8; bmRequestType: UInt8; bRequest: UInt8; wValue: UInt16; wIndex: UInt16; length: UInt16; debugName: String; isInput: Bool; static func setCurrent(_:model:) -> UVCRequest; static func get(_:_:model:) -> UVCRequest }`
  - `public enum LittleEndian { static func encode(_ value: Int, size: Int) -> [UInt8]; static func decode(_ bytes: [UInt8]) -> Int }`

- [ ] **Step 1: Write the failing tests**

`Tests/OpalUVCTests/UVCRequestTests.swift`:

```swift
import XCTest
@testable import OpalUVC

final class UVCRequestTests: XCTestCase {
    let model = KnownModels.opalC1

    func testSetCurrentFocusAutoPacksSelectorUnitAndInterface() {
        let r = UVCRequest.setCurrent(.focusAuto, model: model)
        XCTAssertEqual(r.bmRequestType, 0x21)
        XCTAssertEqual(r.bRequest, 0x01)
        XCTAssertEqual(r.wValue, 0x0800)
        XCTAssertEqual(r.wIndex, 0x0101)
        XCTAssertEqual(r.length, 1)
        XCTAssertFalse(r.isInput)
    }

    func testGetCurrentFocusAbsoluteIsTwoByteInput() {
        let r = UVCRequest.get(.getCur, .focusAbsolute, model: model)
        XCTAssertEqual(r.bmRequestType, 0xA1)
        XCTAssertEqual(r.bRequest, 0x81)
        XCTAssertEqual(r.wValue, 0x0600)
        XCTAssertEqual(r.wIndex, 0x0101)
        XCTAssertEqual(r.length, 2)
        XCTAssertTrue(r.isInput)
    }

    func testGetInfoIsAlwaysOneByte() {
        let r = UVCRequest.get(.getInfo, .focusAbsolute, model: model)
        XCTAssertEqual(r.bRequest, 0x86)
        XCTAssertEqual(r.length, 1)
    }

    func testRequestCodes() {
        XCTAssertEqual(UVCRequest.Code.getMin.rawValue, 0x82)
        XCTAssertEqual(UVCRequest.Code.getMax.rawValue, 0x83)
        XCTAssertEqual(UVCRequest.Code.getDef.rawValue, 0x87)
    }

    func testDebugNameNamesControlAndCode() {
        XCTAssertEqual(UVCRequest.setCurrent(.focusAuto, model: model).debugName, "SET_CUR Focus-Auto")
        XCTAssertEqual(UVCRequest.get(.getDef, .focusAbsolute, model: model).debugName, "GET_DEF Focus-Absolute")
    }

    func testLittleEndianEncodeTwoBytes() {
        XCTAssertEqual(LittleEndian.encode(0x82, size: 2), [0x82, 0x00])
        XCTAssertEqual(LittleEndian.encode(255, size: 2), [0xff, 0x00])
        XCTAssertEqual(LittleEndian.encode(1, size: 1), [0x01])
    }

    func testLittleEndianDecode() {
        XCTAssertEqual(LittleEndian.decode([0x82, 0x00]), 0x82)
        XCTAssertEqual(LittleEndian.decode([0x00, 0xff]), 0xff00)
        XCTAssertEqual(LittleEndian.decode([]), 0)
    }

    func testEveryKnownControlRoundTrips() {
        for control in CameraTerminalControl.all {
            let value = (1 << (8 * control.size)) - 1
            XCTAssertEqual(LittleEndian.decode(LittleEndian.encode(value, size: control.size)), value, control.name)
        }
    }
}
```

`Tests/OpalUVCTests/ModelsTests.swift`:

```swift
import XCTest
@testable import OpalUVC

final class ModelsTests: XCTestCase {
    func testOpalC1Constants() {
        let m = KnownModels.opalC1
        XCTAssertEqual(m.vendorID, 0x03e7)
        XCTAssertEqual(m.productID, 0xf63d)
        XCTAssertEqual(m.cameraTerminalID, 1)
        XCTAssertEqual(m.controlInterface, 1)
    }

    func testMatchFindsKnownAndRejectsUnknown() {
        XCTAssertEqual(KnownModels.match(vendorID: 0x03e7, productID: 0xf63d), KnownModels.opalC1)
        XCTAssertNil(KnownModels.match(vendorID: 0x03e7, productID: 0xf63b))
    }

    func testAllModelsHaveUniqueIDs() {
        let ids = KnownModels.all.map { "\($0.vendorID):\($0.productID)" }
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (`CameraModel`, `UVCRequest` etc. not defined).

- [ ] **Step 3: Implement**

`Sources/OpalUVC/Models.swift`:

```swift
/// A camera we know how to talk to. Add a new entry for another Opal model;
/// the unit and interface ids come from the camera's UVC descriptors.
public struct CameraModel: Equatable {
    public let name: String
    public let vendorID: UInt16
    public let productID: UInt16
    public let cameraTerminalID: UInt8
    public let controlInterface: UInt8

    public init(name: String, vendorID: UInt16, productID: UInt16, cameraTerminalID: UInt8, controlInterface: UInt8) {
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.cameraTerminalID = cameraTerminalID
        self.controlInterface = controlInterface
    }
}

public enum KnownModels {
    public static let opalC1 = CameraModel(
        name: "Opal C1", vendorID: 0x03e7, productID: 0xf63d, cameraTerminalID: 1, controlInterface: 1)

    public static let all: [CameraModel] = [opalC1]

    public static func match(vendorID: UInt16, productID: UInt16) -> CameraModel? {
        all.first { $0.vendorID == vendorID && $0.productID == productID }
    }
}
```

`Sources/OpalUVC/Controls.swift`:

```swift
/// UVC Camera Terminal controls (USB Video Class 1.1, table 4-9).
public struct CameraTerminalControl: Equatable {
    public let name: String
    public let selector: UInt8
    public let size: Int

    public static let focusAbsolute = CameraTerminalControl(name: "Focus-Absolute", selector: 0x06, size: 2)
    public static let focusAuto = CameraTerminalControl(name: "Focus-Auto", selector: 0x08, size: 1)

    public static let all: [CameraTerminalControl] = [focusAbsolute, focusAuto]
}
```

`Sources/OpalUVC/UVCRequest.swift`:

```swift
/// One UVC class request on the default control pipe.
public struct UVCRequest: Equatable {
    public enum Code: UInt8 {
        case setCur = 0x01
        case getCur = 0x81
        case getMin = 0x82
        case getMax = 0x83
        case getInfo = 0x86
        case getDef = 0x87

        var name: String {
            switch self {
            case .setCur: return "SET_CUR"
            case .getCur: return "GET_CUR"
            case .getMin: return "GET_MIN"
            case .getMax: return "GET_MAX"
            case .getInfo: return "GET_INFO"
            case .getDef: return "GET_DEF"
            }
        }
    }

    public let bmRequestType: UInt8
    public let bRequest: UInt8
    public let wValue: UInt16
    public let wIndex: UInt16
    public let length: UInt16
    public let debugName: String

    public var isInput: Bool { bmRequestType & 0x80 != 0 }

    public static func setCurrent(_ control: CameraTerminalControl, model: CameraModel) -> UVCRequest {
        UVCRequest(
            bmRequestType: 0x21, bRequest: Code.setCur.rawValue,
            wValue: UInt16(control.selector) << 8,
            wIndex: UInt16(model.cameraTerminalID) << 8 | UInt16(model.controlInterface),
            length: UInt16(control.size),
            debugName: "\(Code.setCur.name) \(control.name)")
    }

    public static func get(_ code: Code, _ control: CameraTerminalControl, model: CameraModel) -> UVCRequest {
        UVCRequest(
            bmRequestType: 0xA1, bRequest: code.rawValue,
            wValue: UInt16(control.selector) << 8,
            wIndex: UInt16(model.cameraTerminalID) << 8 | UInt16(model.controlInterface),
            length: code == .getInfo ? 1 : UInt16(control.size),
            debugName: "\(code.name) \(control.name)")
    }
}

public enum LittleEndian {
    public static func encode(_ value: Int, size: Int) -> [UInt8] {
        (0..<size).map { UInt8((value >> (8 * $0)) & 0xff) }
    }

    public static func decode(_ bytes: [UInt8]) -> Int {
        bytes.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: all tests pass (SmokeTests, UVCRequestTests, ModelsTests, PlaceholderTests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OpalUVC Tests/OpalUVCTests
git commit -m "Add camera model table and UVC request encoding"
```

---

### Task 3: IOKit shim, device discovery, connection

**Files:**
- Modify: `Sources/COpalUSB/copalusb.c` (replace stub)
- Create: `Sources/OpalUVC/UVCError.swift`, `Sources/OpalUVC/OpalDevice.swift`, `Sources/OpalUVC/Connection.swift`
- Test: `Tests/OpalUVCTests/UVCErrorTests.swift`, `Tests/OpalUVCTests/DeviceDiscoveryTests.swift`

**Interfaces:**
- Consumes: `CameraModel`, `KnownModels`, `UVCRequest` from Task 2; C functions from Task 1 header.
- Produces:
  - `public enum UVCError: Error, CustomStringConvertible { case ioKit(IOReturn, String); case openFailed(IOReturn) }` with `description` like `"SET_CUR Focus-Auto failed: kIOReturnNotResponding (0xe00002ed)"`.
  - `public final class OpalDevice { let model: CameraModel; let serial: String?; let locationID: UInt32; var label: String; static func find(models: [CameraModel] = KnownModels.all) throws -> [OpalDevice]; static func matchingDictionary(for: CameraModel) -> CFMutableDictionary; static func model(for service: io_service_t, among: [CameraModel]) -> CameraModel?; func open() throws -> Connection }`
  - `public final class Connection { let device: OpalDevice; func perform(_ request: UVCRequest, payload: [UInt8] = []) throws -> [UInt8] }`

- [ ] **Step 1: Write the failing tests**

`Tests/OpalUVCTests/UVCErrorTests.swift`:

```swift
import XCTest
import IOKit
@testable import OpalUVC

final class UVCErrorTests: XCTestCase {
    func testDescriptionNamesRequestAndCode() {
        let e = UVCError.ioKit(IOReturn(bitPattern: 0xe00002ed), "SET_CUR Focus-Auto")
        XCTAssertEqual(e.description, "SET_CUR Focus-Auto failed: kIOReturnNotResponding (0xe00002ed)")
    }

    func testDescriptionForExclusiveAccess() {
        let e = UVCError.openFailed(IOReturn(bitPattern: 0xe00002c5))
        XCTAssertEqual(e.description, "could not open device: kIOReturnExclusiveAccess (0xe00002c5)")
    }

    func testPipeStallIsNamed() {
        XCTAssertEqual(UVCError.name(of: IOReturn(bitPattern: 0xe000404f)), "kIOUSBPipeStalled (0xe000404f)")
    }

    func testUnknownCodeFallsBackToHex() {
        let e = UVCError.ioKit(IOReturn(bitPattern: 0xe0001234), "GET_CUR Focus-Absolute")
        XCTAssertEqual(e.description, "GET_CUR Focus-Absolute failed: IOReturn (0xe0001234)")
    }
}
```

`Tests/OpalUVCTests/DeviceDiscoveryTests.swift` (runs without hardware; with hardware it exercises the real path):

```swift
import XCTest
@testable import OpalUVC

final class DeviceDiscoveryTests: XCTestCase {
    func testMatchingDictionaryCarriesVendorAndProduct() {
        let dict = OpalDevice.matchingDictionary(for: KnownModels.opalC1) as NSDictionary
        XCTAssertEqual(dict["IOProviderClass"] as? String, "IOUSBHostDevice")
        XCTAssertEqual(dict["idVendor"] as? Int, 0x03e7)
        XCTAssertEqual(dict["idProduct"] as? Int, 0xf63d)
    }

    func testFindDoesNotThrowAndReturnsOnlyKnownModels() throws {
        let devices = try OpalDevice.find()
        for d in devices {
            XCTAssertTrue(KnownModels.all.contains(d.model))
            XCTAssertFalse(d.label.isEmpty)
        }
    }

    func testFindWithUnknownModelReturnsNothing() throws {
        let bogus = CameraModel(name: "none", vendorID: 0xffff, productID: 0xffff, cameraTerminalID: 1, controlInterface: 1)
        XCTAssertEqual(try OpalDevice.find(models: [bogus]).count, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'UVCErrorTests|DeviceDiscoveryTests'`
Expected: compile errors (`UVCError`, `OpalDevice` not defined).

- [ ] **Step 3: Implement the C shim**

Replace `Sources/COpalUSB/copalusb.c`:

```c
#include "copalusb.h"

#include <stdlib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

struct opal_usb_device {
    IOUSBDeviceInterface **iface;
};

kern_return_t opal_usb_open(io_service_t service, opal_usb_device_t **out) {
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    if (kr != KERN_SUCCESS) return kr;
    if (plugin == NULL) return kIOReturnNoDevice;

    IOUSBDeviceInterface **iface = NULL;
    HRESULT hr = (*plugin)->QueryInterface(
        plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&iface);
    (*plugin)->Release(plugin);
    if (hr != S_OK || iface == NULL) return kIOReturnNotFound;

    opal_usb_device_t *dev = calloc(1, sizeof *dev);
    if (dev == NULL) {
        (*iface)->Release(iface);
        return kIOReturnNoMemory;
    }
    dev->iface = iface;
    *out = dev;
    return KERN_SUCCESS;
}

kern_return_t opal_usb_request(opal_usb_device_t *dev, uint8_t bmRequestType, uint8_t bRequest,
                               uint16_t wValue, uint16_t wIndex, void *data, uint16_t length,
                               uint32_t *done) {
    IOUSBDevRequest req = {
        .bmRequestType = bmRequestType,
        .bRequest = bRequest,
        .wValue = wValue,
        .wIndex = wIndex,
        .wLength = length,
        .pData = data,
        .wLenDone = 0,
    };
    kern_return_t kr = (*dev->iface)->DeviceRequest(dev->iface, &req);
    if (done) *done = req.wLenDone;
    return kr;
}

void opal_usb_close(opal_usb_device_t *dev) {
    if (dev == NULL) return;
    if (dev->iface) (*dev->iface)->Release(dev->iface);
    free(dev);
}
```

Note: the device is deliberately not opened with `USBDeviceOpen`. Control requests on the default pipe work through the device-level interface while the system UVC driver owns interfaces 1 and 2; this was verified on the real camera during research.

- [ ] **Step 4: Implement the Swift side**

`Sources/OpalUVC/UVCError.swift`:

```swift
import IOKit

public enum UVCError: Error, CustomStringConvertible {
    case ioKit(IOReturn, String)
    case openFailed(IOReturn)

    public var description: String {
        switch self {
        case .ioKit(let code, let request):
            return "\(request) failed: \(UVCError.name(of: code))"
        case .openFailed(let code):
            return "could not open device: \(UVCError.name(of: code))"
        }
    }

    /// IOReturn values are built from function-like C macros that Swift does not import,
    /// so the ones we name are listed by value (IOKit/IOReturn.h and IOUSBLib.h).
    static let knownCodes: [UInt32: String] = [
        0xe00002bc: "kIOReturnError",
        0xe00002bd: "kIOReturnNoMemory",
        0xe00002c0: "kIOReturnNoDevice",
        0xe00002c2: "kIOReturnBadArgument",
        0xe00002c5: "kIOReturnExclusiveAccess",
        0xe00002c7: "kIOReturnUnsupported",
        0xe00002cd: "kIOReturnNotOpen",
        0xe00002d5: "kIOReturnBusy",
        0xe00002d6: "kIOReturnTimeout",
        0xe00002d9: "kIOReturnNotAttached",
        0xe00002e2: "kIOReturnNotPermitted",
        0xe00002eb: "kIOReturnAborted",
        0xe00002ed: "kIOReturnNotResponding",
        0xe00002f0: "kIOReturnNotFound",
        0xe000404f: "kIOUSBPipeStalled",
    ]

    static func name(of code: IOReturn) -> String {
        let raw = UInt32(bitPattern: code)
        let hex = String(format: "0x%08x", raw)
        if let n = knownCodes[raw] { return "\(n) (\(hex))" }
        return "IOReturn (\(hex))"
    }
}
```

`IOReturn` is `Int32` (`kern_return_t`); `UInt32(bitPattern:)` gives the value as printed by IOKit tools.

`Sources/OpalUVC/OpalDevice.swift`:

```swift
import Foundation
import IOKit
import IOKit.usb

/// One attached camera, backed by an IOKit service handle.
public final class OpalDevice {
    public let model: CameraModel
    public let serial: String?
    public let locationID: UInt32
    let service: io_service_t

    init(service: io_service_t, model: CameraModel) {
        self.service = service
        self.model = model
        self.serial = OpalDevice.property(service, "USB Serial Number") as? String
        self.locationID = (OpalDevice.property(service, "locationID") as? NSNumber)?.uint32Value ?? 0
    }

    deinit { IOObjectRelease(service) }

    /// "Opal C1 (serial 1944..., location 0x01220000)"
    public var label: String {
        "\(model.name) (serial \(serial ?? "unknown"), location \(String(format: "0x%08x", locationID)))"
    }

    public static func matchingDictionary(for model: CameraModel) -> CFMutableDictionary {
        let dict = IOServiceMatching("IOUSBHostDevice")!
        let mutable = dict as NSMutableDictionary
        mutable["idVendor"] = Int(model.vendorID)
        mutable["idProduct"] = Int(model.productID)
        return dict
    }

    public static func model(for service: io_service_t, among models: [CameraModel]) -> CameraModel? {
        guard let vendor = (property(service, "idVendor") as? NSNumber)?.uint16Value,
              let product = (property(service, "idProduct") as? NSNumber)?.uint16Value else { return nil }
        return models.first { $0.vendorID == vendor && $0.productID == product }
    }

    public static func find(models: [CameraModel] = KnownModels.all) throws -> [OpalDevice] {
        var found: [OpalDevice] = []
        for model in models {
            var iterator: io_iterator_t = 0
            // IOServiceGetMatchingServices consumes one reference to the dictionary.
            let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary(for: model), &iterator)
            guard kr == KERN_SUCCESS else { throw UVCError.ioKit(kr, "IOServiceGetMatchingServices") }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                found.append(OpalDevice(service: service, model: model))
            }
        }
        return found
    }

    public func open() throws -> Connection {
        try Connection(device: self)
    }

    static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
```

`Sources/OpalUVC/Connection.swift`:

```swift
import Foundation
import IOKit
import COpalUSB

/// An open device-level handle. Released when the object goes away.
public final class Connection {
    public let device: OpalDevice
    private let handle: OpaquePointer

    init(device: OpalDevice) throws {
        var out: OpaquePointer? = nil
        let kr = opal_usb_open(device.service, &out)
        guard kr == KERN_SUCCESS, let out else { throw UVCError.openFailed(kr) }
        self.device = device
        self.handle = out
    }

    deinit { opal_usb_close(handle) }

    /// Runs one control request. Returns the bytes read for IN requests, [] for OUT.
    public func perform(_ request: UVCRequest, payload: [UInt8] = []) throws -> [UInt8] {
        var buffer = request.isInput ? [UInt8](repeating: 0, count: Int(request.length)) : payload
        precondition(buffer.count == Int(request.length), "payload must be \(request.length) bytes")
        var done: UInt32 = 0
        let kr = buffer.withUnsafeMutableBytes { raw in
            opal_usb_request(handle, request.bmRequestType, request.bRequest, request.wValue,
                             request.wIndex, raw.baseAddress, request.length, &done)
        }
        guard kr == KERN_SUCCESS else { throw UVCError.ioKit(kr, request.debugName) }
        return request.isInput ? Array(buffer.prefix(Int(done))) : []
    }
}
```

- [ ] **Step 5: Build and run tests**

Run: `swift test`
Expected: all pass. With the camera attached, `testFindDoesNotThrowAndReturnsOnlyKnownModels` sees one device; without it, zero. Both are passes.

- [ ] **Step 6: Hardware check**

With the camera attached, `swift test --filter DeviceDiscoveryTests` must report one device in `testFindDoesNotThrowAndReturnsOnlyKnownModels` (add a temporary `print(devices.map(\.label))` while checking, then remove it). The first real control request happens in Task 4's `status` command; no separate check here.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "Add IOKit USB shim, device discovery and control-request connection"
```

---

### Task 4: Focus operations and the status / enable / disable / focus commands

**Files:**
- Create: `Sources/OpalUVC/FocusControl.swift`
- Create: `Sources/OpalAutofocusCLI/StatusCommand.swift`, `Sources/OpalAutofocusCLI/FocusCommands.swift`, `Sources/OpalAutofocusCLI/Output.swift`
- Modify: `Sources/OpalAutofocusCLI/OpalAutofocus.swift` (register subcommands)
- Test: `Tests/OpalUVCTests/FocusStatusTests.swift`, `Tests/OpalAutofocusCLITests/FocusCommandTests.swift`

**Interfaces:**
- Consumes: `Connection.perform`, `UVCRequest`, `LittleEndian`, `CameraTerminalControl` from Tasks 2 and 3.
- Produces:
  - `public struct FocusStatus: Equatable { autofocus: Bool; position: Int; minimum: Int; maximum: Int; defaultPosition: Int; var summary: String }`
  - `extension Connection { func enableAutofocus() throws; func disableAutofocus() throws; func setFocus(_ position: UInt8) throws; func focusStatus() throws -> FocusStatus }`
  - CLI: `Status`, `Enable`, `Disable`, `Focus` `ParsableCommand`s; `enum ExitStatus { static let ok: Int32 = 0; noDevice = 1; requestFailed = 2 }`; `func fail(_ message: String, code: Int32) -> Never`-style helper `Output.error(_:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/OpalUVCTests/FocusStatusTests.swift`:

```swift
import XCTest
@testable import OpalUVC

final class FocusStatusTests: XCTestCase {
    func testSummaryLine() {
        let s = FocusStatus(autofocus: true, position: 130, minimum: 0, maximum: 255, defaultPosition: 130)
        XCTAssertEqual(s.summary, "autofocus: on, focus position: 130 (min 0, max 255, default 130)")
    }

    func testSummaryWhenOff() {
        let s = FocusStatus(autofocus: false, position: 255, minimum: 0, maximum: 255, defaultPosition: 130)
        XCTAssertEqual(s.summary, "autofocus: off, focus position: 255 (min 0, max 255, default 130)")
    }
}
```

`Tests/OpalAutofocusCLITests/FocusCommandTests.swift` (replace `PlaceholderTests.swift`; delete that file):

```swift
import XCTest
import ArgumentParser
@testable import OpalAutofocusCLI

final class FocusCommandTests: XCTestCase {
    func testFocusAcceptsRange() throws {
        XCTAssertEqual(try Focus.parse(["0"]).position, 0)
        XCTAssertEqual(try Focus.parse(["255"]).position, 255)
    }

    func testFocusRejectsOutOfRangeAndNonNumeric() {
        XCTAssertThrowsError(try Focus.parse(["256"]))
        XCTAssertThrowsError(try Focus.parse(["-1"]))
        XCTAssertThrowsError(try Focus.parse(["abc"]))
        XCTAssertThrowsError(try Focus.parse([]))
    }

    func testValidationErrorExitCodeIsUsage() {
        do {
            _ = try Focus.parse(["300"])
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(Focus.exitCode(for: error), ExitCode(64))
        }
    }

    func testSubcommandsRegistered() {
        let names = OpalAutofocus.configuration.subcommands.map { $0.configuration.commandName ?? "" }
        XCTAssertEqual(Set(names), ["status", "enable", "disable", "focus"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'FocusStatusTests|FocusCommandTests'`
Expected: compile errors.

- [ ] **Step 3: Implement the library part**

`Sources/OpalUVC/FocusControl.swift`:

```swift
public struct FocusStatus: Equatable {
    public let autofocus: Bool
    public let position: Int
    public let minimum: Int
    public let maximum: Int
    public let defaultPosition: Int

    public init(autofocus: Bool, position: Int, minimum: Int, maximum: Int, defaultPosition: Int) {
        self.autofocus = autofocus
        self.position = position
        self.minimum = minimum
        self.maximum = maximum
        self.defaultPosition = defaultPosition
    }

    public var summary: String {
        "autofocus: \(autofocus ? "on" : "off"), focus position: \(position) "
            + "(min \(minimum), max \(maximum), default \(defaultPosition))"
    }
}

extension Connection {
    /// Turns continuous autofocus on. This is the write Opal Composer sends.
    public func enableAutofocus() throws {
        try set(.focusAuto, value: 1)
    }

    /// Parks the lens at its current position.
    public func disableAutofocus() throws {
        try set(.focusAuto, value: 0)
    }

    /// Manual focus. 0 is nearest, 255 is farthest on the Opal C1.
    public func setFocus(_ position: UInt8) throws {
        try set(.focusAuto, value: 0)
        try set(.focusAbsolute, value: Int(position))
    }

    public func focusStatus() throws -> FocusStatus {
        FocusStatus(
            autofocus: try get(.focusAuto, .getCur) != 0,
            position: try get(.focusAbsolute, .getCur),
            minimum: try get(.focusAbsolute, .getMin),
            maximum: try get(.focusAbsolute, .getMax),
            defaultPosition: try get(.focusAbsolute, .getDef))
    }

    func set(_ control: CameraTerminalControl, value: Int) throws {
        let request = UVCRequest.setCurrent(control, model: device.model)
        _ = try perform(request, payload: LittleEndian.encode(value, size: control.size))
    }

    func get(_ control: CameraTerminalControl, _ code: UVCRequest.Code) throws -> Int {
        LittleEndian.decode(try perform(UVCRequest.get(code, control, model: device.model)))
    }
}
```

- [ ] **Step 4: Implement the CLI part**

`Sources/OpalAutofocusCLI/Output.swift`:

```swift
import Foundation
import ArgumentParser

enum ExitStatus {
    static let ok: Int32 = 0
    static let noDevice: Int32 = 1
    static let requestFailed: Int32 = 2
}

enum Output {
    static func line(_ message: String) {
        print(message)
        fflush(stdout)
    }

    static func error(_ message: String) {
        FileHandle.standardError.write(("opal-autofocus: " + message + "\n").data(using: .utf8)!)
    }

    static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}
```

`Sources/OpalAutofocusCLI/StatusCommand.swift`:

```swift
import ArgumentParser
import OpalUVC

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show attached cameras and their focus controls.")

    func run() throws {
        let devices = try OpalDevice.find()
        guard !devices.isEmpty else {
            Output.line("no Opal camera attached")
            throw ExitCode(ExitStatus.noDevice)
        }
        var failed = false
        for device in devices {
            Output.line(device.label)
            do {
                Output.line("  " + (try device.open().focusStatus().summary))
            } catch {
                Output.error("\(device.label): \(error)")
                failed = true
            }
        }
        if failed { throw ExitCode(ExitStatus.requestFailed) }
    }
}
```

`Sources/OpalAutofocusCLI/FocusCommands.swift`:

```swift
import ArgumentParser
import OpalUVC

/// Applies one action to every attached camera and maps the result to an exit code.
func applyToAllDevices(_ what: String, _ action: (Connection) throws -> Void) throws {
    let devices = try OpalDevice.find()
    guard !devices.isEmpty else {
        Output.error("no Opal camera attached")
        throw ExitCode(ExitStatus.noDevice)
    }
    var failed = false
    for device in devices {
        do {
            try action(try device.open())
            Output.line("\(what) on \(device.label)")
        } catch {
            Output.error("\(device.label): \(error)")
            failed = true
        }
    }
    if failed { throw ExitCode(ExitStatus.requestFailed) }
}

struct Enable: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Turn continuous autofocus on.")
    func run() throws { try applyToAllDevices("enabled autofocus") { try $0.enableAutofocus() } }
}

struct Disable: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Turn autofocus off (lens stays where it is).")
    func run() throws { try applyToAllDevices("disabled autofocus") { try $0.disableAutofocus() } }
}

struct Focus: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Set a fixed focus position (0 nearest, 255 farthest).")

    @Argument(help: "Lens position, 0 to 255.")
    var position: Int

    func validate() throws {
        guard (0...255).contains(position) else {
            throw ValidationError("position must be between 0 and 255")
        }
    }

    func run() throws {
        try applyToAllDevices("set focus position \(position)") { try $0.setFocus(UInt8(position)) }
    }
}
```

Modify `Sources/OpalAutofocusCLI/OpalAutofocus.swift`:

```swift
import ArgumentParser
import OpalUVC

@main
struct OpalAutofocus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "opal-autofocus",
        abstract: "Keep the Opal C1 webcam's autofocus enabled without Opal Composer.",
        version: OpalUVC.version,
        subcommands: [Status.self, Enable.self, Disable.self, Focus.self]
    )
}
```

Delete `Tests/OpalAutofocusCLITests/PlaceholderTests.swift`.

- [ ] **Step 5: Run tests**

Run: `swift test`
Expected: all pass.

- [ ] **Step 6: Hardware check (camera attached)**

```bash
swift build
.build/debug/opal-autofocus status
.build/debug/opal-autofocus disable
.build/debug/opal-autofocus status
.build/debug/opal-autofocus enable
.build/debug/opal-autofocus status; echo "exit $?"
.build/debug/opal-autofocus focus 300; echo "exit $?"
```

Expected: status prints the label and `autofocus: on, ...`; after `disable` it prints `autofocus: off`; after `enable` it is `on` again with exit 0; `focus 300` prints a usage error and exits 64. With Photo Booth open on the Opal, the picture goes parked after `disable` and refocuses after `enable`.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "Add focus operations and status, enable, disable, focus commands"
```

---

### Task 5: `run` command with retry loop and exit mapping

**Files:**
- Create: `Sources/OpalAutofocusCLI/KickLoop.swift`, `Sources/OpalAutofocusCLI/RunCommand.swift`
- Modify: `Sources/OpalAutofocusCLI/OpalAutofocus.swift` (add `Run.self`)
- Test: `Tests/OpalAutofocusCLITests/KickLoopTests.swift`

**Interfaces:**
- Consumes: `OpalDevice.find`, `Connection.enableAutofocus` (Tasks 3, 4), `ExitStatus`, `Output` (Task 4).
- Produces:
  - `protocol AutofocusTarget { var label: String { get }; func kick() throws }`; `extension OpalDevice: AutofocusTarget`.
  - `enum KickOutcome: Equatable { case kicked(Int); case noDevice; case failed(message: String, kicked: Int) }`
  - `struct KickLoop { timeout: TimeInterval; interval: TimeInterval; sleep: (TimeInterval) -> Void; now: () -> Date; find: () throws -> [AutofocusTarget]; log: (String) -> Void; func run() -> KickOutcome; static func exitCode(for: KickOutcome, quietMissing: Bool) -> Int32 }`

- [ ] **Step 1: Write the failing tests**

`Tests/OpalAutofocusCLITests/KickLoopTests.swift`:

```swift
import XCTest
@testable import OpalAutofocusCLI

private struct FakeTarget: AutofocusTarget {
    let label: String
    let error: Error?
    func kick() throws { if let error { throw error } }
}

private struct Boom: Error, CustomStringConvertible { var description: String { "SET_CUR Focus-Auto failed: kIOReturnNotResponding (0xe00002ed)" } }

final class KickLoopTests: XCTestCase {
    private var clock: TimeInterval = 0
    private var slept: [TimeInterval] = []
    private var logged: [String] = []

    private func loop(timeout: TimeInterval, interval: TimeInterval = 0.25,
                      find: @escaping () throws -> [AutofocusTarget]) -> KickLoop {
        KickLoop(timeout: timeout, interval: interval,
                 sleep: { self.slept.append($0); self.clock += $0 },
                 now: { Date(timeIntervalSince1970: self.clock) },
                 find: find,
                 log: { self.logged.append($0) })
    }

    func testKicksEveryDevicePresentOnFirstTry() {
        let l = loop(timeout: 5) { [FakeTarget(label: "a", error: nil), FakeTarget(label: "b", error: nil)] }
        XCTAssertEqual(l.run(), .kicked(2))
        XCTAssertEqual(slept, [])
        XCTAssertEqual(logged, ["enabled autofocus on a", "enabled autofocus on b"])
    }

    func testRetriesUntilDeviceAppears() {
        var calls = 0
        let l = loop(timeout: 5) { calls += 1; return calls < 4 ? [] : [FakeTarget(label: "a", error: nil)] }
        XCTAssertEqual(l.run(), .kicked(1))
        XCTAssertEqual(calls, 4)
        XCTAssertEqual(slept, [0.25, 0.25, 0.25])
    }

    func testGivesUpAtTimeout() {
        var calls = 0
        let l = loop(timeout: 1.0) { calls += 1; return [] }
        XCTAssertEqual(l.run(), .noDevice)
        XCTAssertEqual(calls, 5)          // t = 0, 0.25, 0.5, 0.75, 1.0
        XCTAssertEqual(slept.count, 4)
    }

    func testTimeoutZeroTriesExactlyOnce() {
        var calls = 0
        let l = loop(timeout: 0) { calls += 1; return [] }
        XCTAssertEqual(l.run(), .noDevice)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(slept, [])
    }

    func testPartialFailureReportsMessageAndCount() {
        let l = loop(timeout: 5) { [FakeTarget(label: "a", error: nil), FakeTarget(label: "b", error: Boom())] }
        XCTAssertEqual(l.run(), .failed(message: "b: SET_CUR Focus-Auto failed: kIOReturnNotResponding (0xe00002ed)", kicked: 1))
    }

    func testFindErrorIsTreatedAsNoDeviceThisRound() {
        var calls = 0
        let l = loop(timeout: 0.5) { calls += 1; if calls == 1 { throw Boom() }; return [FakeTarget(label: "a", error: nil)] }
        XCTAssertEqual(l.run(), .kicked(1))
    }

    func testExitCodeMapping() {
        XCTAssertEqual(KickLoop.exitCode(for: .kicked(1), quietMissing: false), 0)
        XCTAssertEqual(KickLoop.exitCode(for: .noDevice, quietMissing: false), 1)
        XCTAssertEqual(KickLoop.exitCode(for: .noDevice, quietMissing: true), 0)
        XCTAssertEqual(KickLoop.exitCode(for: .failed(message: "x", kicked: 0), quietMissing: true), 2)
        XCTAssertEqual(KickLoop.exitCode(for: .failed(message: "x", kicked: 3), quietMissing: false), 2)
    }

    func testRunCommandDefaults() throws {
        let cmd = try Run.parse([])
        XCTAssertEqual(cmd.timeout, 5)
        XCTAssertFalse(cmd.quietMissing)
        let quiet = try Run.parse(["--quiet-missing", "--timeout", "0"])
        XCTAssertTrue(quiet.quietMissing)
        XCTAssertEqual(quiet.timeout, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter KickLoopTests`
Expected: compile errors.

- [ ] **Step 3: Implement**

`Sources/OpalAutofocusCLI/KickLoop.swift`:

```swift
import Foundation
import OpalUVC

protocol AutofocusTarget {
    var label: String { get }
    func kick() throws
}

extension OpalDevice: AutofocusTarget {
    func kick() throws { try open().enableAutofocus() }
}

enum KickOutcome: Equatable {
    case kicked(Int)
    case noDevice
    case failed(message: String, kicked: Int)
}

/// Polls for cameras until one appears or the timeout passes, then enables autofocus on each.
struct KickLoop {
    var timeout: TimeInterval
    var interval: TimeInterval = 0.25
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var now: () -> Date = Date.init
    var find: () throws -> [AutofocusTarget]
    var log: (String) -> Void = { Output.line($0) }

    func run() -> KickOutcome {
        let deadline = now().addingTimeInterval(timeout)
        while true {
            let targets = (try? find()) ?? []
            if !targets.isEmpty { return kick(targets) }
            if now() >= deadline { return .noDevice }
            sleep(interval)
        }
    }

    private func kick(_ targets: [AutofocusTarget]) -> KickOutcome {
        var kicked = 0
        var firstFailure: String?
        for target in targets {
            do {
                try target.kick()
                kicked += 1
                log("enabled autofocus on \(target.label)")
            } catch {
                if firstFailure == nil { firstFailure = "\(target.label): \(error)" }
            }
        }
        if let firstFailure { return .failed(message: firstFailure, kicked: kicked) }
        return .kicked(kicked)
    }

    static func exitCode(for outcome: KickOutcome, quietMissing: Bool) -> Int32 {
        switch outcome {
        case .kicked: return ExitStatus.ok
        case .noDevice: return quietMissing ? ExitStatus.ok : ExitStatus.noDevice
        case .failed: return ExitStatus.requestFailed
        }
    }
}
```

`Sources/OpalAutofocusCLI/RunCommand.swift`:

```swift
import ArgumentParser
import OpalUVC

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Enable autofocus on any attached Opal, waiting briefly for it to appear, then exit.",
        discussion: "This is what the launchd agent runs when the camera is attached.")

    @Option(help: "Seconds to keep looking for the camera before giving up.")
    var timeout: Double = 5

    @Flag(help: "Exit 0 instead of 1 when no camera appears (for launchd).")
    var quietMissing = false

    func run() throws {
        let loop = KickLoop(timeout: timeout, find: { try OpalDevice.find() })
        let outcome = loop.run()
        switch outcome {
        case .kicked:
            break
        case .noDevice:
            if !quietMissing { Output.error("no Opal camera appeared within \(timeout) s") }
        case .failed(let message, let kicked):
            Output.error("\(message) (\(kicked) other device(s) succeeded)")
        }
        let code = KickLoop.exitCode(for: outcome, quietMissing: quietMissing)
        if code != ExitStatus.ok { throw ExitCode(code) }
    }
}
```

Add `Run.self` as the first entry of `subcommands` in `OpalAutofocus.swift` and update the registration test in Task 4 to expect `["run", "status", "enable", "disable", "focus"]`.

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: all pass.

- [ ] **Step 5: Hardware check**

```bash
swift build
.build/debug/opal-autofocus run; echo "exit $?"
.build/debug/opal-autofocus run --timeout 0 --quiet-missing; echo "exit $?"
```

Expected (camera attached): `enabled autofocus on Opal C1 (...)`, exit 0 both times. Unplug the camera and run again: first prints `no Opal camera appeared within 5.0 s` with exit 1 after about 5 s; second is silent, exit 0, immediate.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "Add run command: poll briefly for the camera, enable autofocus, exit"
```

---

### Task 6: `watch` command with IOKit attach notifications

**Files:**
- Create: `Sources/OpalUVC/DeviceWatcher.swift`, `Sources/OpalAutofocusCLI/WatchCommand.swift`
- Modify: `Sources/OpalAutofocusCLI/OpalAutofocus.swift` (add `Watch.self`)
- Test: `Tests/OpalUVCTests/DeviceWatcherTests.swift`

**Interfaces:**
- Consumes: `OpalDevice.matchingDictionary(for:)`, `OpalDevice.model(for:among:)`, `OpalDevice.init(service:model:)` (Task 3), `Connection.enableAutofocus` (Task 4).
- Produces: `public final class DeviceWatcher { init(models: [CameraModel] = KnownModels.all, queue: DispatchQueue = .main, onAttach: @escaping (OpalDevice) -> Void); func start() throws; func stop() }`.

- [ ] **Step 1: Write the failing test**

`Tests/OpalUVCTests/DeviceWatcherTests.swift`:

```swift
import XCTest
@testable import OpalUVC

final class DeviceWatcherTests: XCTestCase {
    func testStartReportsAlreadyAttachedDevicesAndStops() throws {
        let expectation = expectation(description: "initial scan delivered")
        expectation.assertForOverFulfill = false
        var seen: [OpalDevice] = []
        let queue = DispatchQueue(label: "watcher-test")
        let watcher = DeviceWatcher(queue: queue) { device in
            seen.append(device)
            expectation.fulfill()
        }
        try watcher.start()
        // Without a camera the callback never fires; give it a moment then stop.
        let present = try OpalDevice.find().count
        if present == 0 { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
        watcher.stop()
        XCTAssertEqual(seen.count, present)
        for d in seen { XCTAssertTrue(KnownModels.all.contains(d.model)) }
    }

    func testStartTwiceThrows() throws {
        let watcher = DeviceWatcher(queue: DispatchQueue(label: "w")) { _ in }
        try watcher.start()
        XCTAssertThrowsError(try watcher.start())
        watcher.stop()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DeviceWatcherTests`
Expected: compile error, `DeviceWatcher` not defined.

- [ ] **Step 3: Implement**

`Sources/OpalUVC/DeviceWatcher.swift`:

```swift
import Foundation
import IOKit

/// Calls `onAttach` for every matching camera already present and for each one attached later.
public final class DeviceWatcher {
    public enum WatcherError: Error, CustomStringConvertible {
        case alreadyStarted
        case ioKit(IOReturn, String)
        public var description: String {
            switch self {
            case .alreadyStarted: return "watcher already started"
            case .ioKit(let code, let what): return "\(what) failed: \(UVCError.name(of: code))"
            }
        }
    }

    private let models: [CameraModel]
    private let queue: DispatchQueue
    private let onAttach: (OpalDevice) -> Void
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    public init(models: [CameraModel] = KnownModels.all, queue: DispatchQueue = .main,
                onAttach: @escaping (OpalDevice) -> Void) {
        self.models = models
        self.queue = queue
        self.onAttach = onAttach
    }

    deinit { stop() }

    public func start() throws {
        guard port == nil else { throw WatcherError.alreadyStarted }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            throw WatcherError.ioKit(IOReturn(bitPattern: 0xe00002bc), "IONotificationPortCreate")  // kIOReturnError
        }
        IONotificationPortSetDispatchQueue(port, queue)
        self.port = port

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for model in models {
            var iterator: io_iterator_t = 0
            let kr = IOServiceAddMatchingNotification(
                port, kIOFirstMatchNotification, OpalDevice.matchingDictionary(for: model),
                { refcon, iterator in
                    guard let refcon else { return }
                    Unmanaged<DeviceWatcher>.fromOpaque(refcon).takeUnretainedValue().drain(iterator)
                },
                refcon, &iterator)
            guard kr == KERN_SUCCESS else {
                stop()
                throw WatcherError.ioKit(kr, "IOServiceAddMatchingNotification")
            }
            iterators.append(iterator)
            // Draining arms the notification and reports devices that are already attached.
            drain(iterator)
        }
    }

    public func stop() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    private func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            guard let model = OpalDevice.model(for: service, among: models) else {
                IOObjectRelease(service)
                continue
            }
            onAttach(OpalDevice(service: service, model: model))
        }
    }
}
```

`Sources/OpalAutofocusCLI/WatchCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpalUVC

struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stay running and enable autofocus each time an Opal is attached.",
        discussion: "Use this when launchd IOKit events are not available (for example under brew services).")

    @Option(help: "Seconds to wait after attach before sending the control, so enumeration can settle.")
    var settle: Double = 0.5

    func run() throws {
        let watcher = DeviceWatcher { device in
            Output.line("\(Output.timestamp()) attached: \(device.label)")
            Thread.sleep(forTimeInterval: settle)
            do {
                try device.open().enableAutofocus()
                Output.line("\(Output.timestamp()) enabled autofocus on \(device.label)")
            } catch {
                Output.error("\(Output.timestamp()) \(device.label): \(error)")
            }
        }
        try watcher.start()
        Output.line("\(Output.timestamp()) watching for \(KnownModels.all.map(\.name).joined(separator: ", "))")
        dispatchMain()
    }
}
```

Add `Watch.self` after `Run.self` in `subcommands`; update the registration test to `["run", "watch", "status", "enable", "disable", "focus"]`.

Note on `settle`: during research the control write worked immediately after the IOKit first-match, but `IOUSBHostDevice` registration can precede UVC driver attachment by a few hundred milliseconds on some hubs. Half a second is a safe default; it is an option so users can tune it.

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: all pass with and without the camera.

- [ ] **Step 5: Hardware check**

```bash
swift build
.build/debug/opal-autofocus watch
```

Expected: prints `... watching for Opal C1`, then (camera attached) `attached: Opal C1 (...)` and `enabled autofocus on ...`. Unplug and replug the camera: a new `attached` and `enabled` pair appears. Ctrl-C to stop.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "Add watch command using IOKit first-match notifications"
```

---

### Task 7: launchd agent, Makefile, smoke script

**Files:**
- Create: `packaging/com.opal-autofocus.agent.plist`, `Makefile`, `scripts/smoke.sh`

**Interfaces:**
- Consumes: the `run --quiet-missing` command (Task 5) and `status`/`enable`/`disable` (Task 4).
- Produces: `make build|test|install|uninstall|smoke`, plist template with `@BIN@` and `@HOME@` tokens.

- [ ] **Step 1: Write the plist template**

`packaging/com.opal-autofocus.agent.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.opal-autofocus.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>@BIN@</string>
        <string>run</string>
        <string>--quiet-missing</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>LaunchEvents</key>
    <dict>
        <key>com.apple.iokit.matching</key>
        <dict>
            <key>com.opal-autofocus.opal-c1-attached</key>
            <dict>
                <key>IOProviderClass</key>
                <string>IOUSBHostDevice</string>
                <key>idVendor</key>
                <integer>999</integer>
                <key>idProduct</key>
                <integer>63037</integer>
                <key>IOMatchLaunchStream</key>
                <true/>
            </dict>
        </dict>
    </dict>
    <key>StandardOutPath</key>
    <string>@HOME@/Library/Logs/opal-autofocus/agent.log</string>
    <key>StandardErrorPath</key>
    <string>@HOME@/Library/Logs/opal-autofocus/agent.log</string>
</dict>
</plist>
```

- [ ] **Step 2: Write the Makefile**

```make
PREFIX ?= $(HOME)/.local
BIN := $(PREFIX)/bin/opal-autofocus
LABEL := com.opal-autofocus.agent
PLIST := $(HOME)/Library/LaunchAgents/$(LABEL).plist
LOGDIR := $(HOME)/Library/Logs/opal-autofocus
USERID := $(shell id -u)

.PHONY: build test install uninstall smoke clean

build:
	swift build -c release

test:
	swift test

install: build
	install -d "$(PREFIX)/bin" "$(HOME)/Library/LaunchAgents" "$(LOGDIR)"
	install -m 755 .build/release/opal-autofocus "$(BIN)"
	sed -e 's|@BIN@|$(BIN)|g' -e 's|@HOME@|$(HOME)|g' packaging/$(LABEL).plist > "$(PLIST)"
	-launchctl bootout gui/$(USERID)/$(LABEL) 2>/dev/null
	launchctl bootstrap gui/$(USERID) "$(PLIST)"
	@echo "installed $(BIN) and loaded $(LABEL); logs in $(LOGDIR)/agent.log"

uninstall:
	-launchctl bootout gui/$(USERID)/$(LABEL) 2>/dev/null
	rm -f "$(PLIST)" "$(BIN)"
	@echo "removed $(LABEL) and $(BIN)"

smoke: build
	BIN=.build/release/opal-autofocus scripts/smoke.sh

clean:
	rm -rf .build
```

Makefile recipes must be indented with a tab character.

- [ ] **Step 3: Write the smoke script**

`scripts/smoke.sh`:

```zsh
#!/bin/zsh
# Manual hardware check. Needs an Opal attached and a preview app (Photo Booth) open on it.
set -e
BIN=${BIN:-.build/release/opal-autofocus}

echo "== status"
"$BIN" status

echo
echo "== disable: hold a hand about 10 cm from the lens and watch the preview"
"$BIN" disable
read "answer?Is the hand blurry, i.e. autofocus parked? [y/N] "
[[ "$answer" == y* ]] || { echo "unexpected: camera still focusing after disable"; exit 1 }

echo
echo "== enable"
"$BIN" enable
read "answer?Does the hand come into focus, and refocus when you move it? [y/N] "
[[ "$answer" == y* ]] || { echo "unexpected: autofocus did not resume after enable"; exit 1 }

echo
"$BIN" status
echo "smoke test passed"
```

Run `chmod +x scripts/smoke.sh`.

- [ ] **Step 4: Verify install end to end**

```bash
make install
launchctl print gui/$(id -u)/com.opal-autofocus.agent | grep -E 'state|program|LaunchEvents' | head
cat ~/Library/Logs/opal-autofocus/agent.log
```

Expected: `launchctl print` shows the job; the log shows `enabled autofocus on Opal C1 (...)` from the `RunAtLoad` run. Then unplug the camera, wait 5 s, plug it back in, wait 5 s, and `tail -2 ~/Library/Logs/opal-autofocus/agent.log` shows a new `enabled autofocus` line. Then in Photo Booth confirm focus tracks a hand. Finally `make smoke` and answer the prompts.

If the replug produces no new log line, check `launchctl print gui/$(id -u)/com.opal-autofocus.agent` for an `events` section; if launchd on this macOS does not deliver the IOKit event to a user agent, switch the plist to `ProgramArguments [@BIN@, watch]` with `KeepAlive true` and record that in `docs/ARCHITECTURE.md` (Task 10) as the chosen default.

- [ ] **Step 5: Commit**

```bash
git add packaging Makefile scripts
git commit -m "Add launchd agent plist, Makefile install targets and smoke script"
```

---

### Task 8: Homebrew formula

**Files:**
- Create: `packaging/Formula/opal-autofocus.rb`

**Interfaces:**
- Consumes: `watch` command (Task 6), plist (Task 7).

- [ ] **Step 1: Write the formula**

```ruby
class OpalAutofocus < Formula
  desc "Keep the Opal C1 webcam's autofocus enabled without Opal Composer"
  homepage "https://github.com/h6y3/opal-autofocus"
  head "https://github.com/h6y3/opal-autofocus.git", branch: "main"
  license "MIT"

  depends_on :macos
  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/opal-autofocus"
    (prefix/"launchd").install "packaging/com.opal-autofocus.agent.plist"
  end

  service do
    run [opt_bin/"opal-autofocus", "watch"]
    keep_alive true
    log_path var/"log/opal-autofocus.log"
    error_log_path var/"log/opal-autofocus.log"
  end

  def caveats
    <<~EOS
      Start the resident watcher with:
        brew services start opal-autofocus

      To run nothing while the camera is unplugged, install the event-driven
      agent instead (one process per attach, exits immediately):
        sed -e "s|@BIN@|#{opt_bin}/opal-autofocus|g" -e "s|@HOME@|$HOME|g" \\
          #{prefix}/launchd/com.opal-autofocus.agent.plist \\
          > ~/Library/LaunchAgents/com.opal-autofocus.agent.plist
        mkdir -p ~/Library/Logs/opal-autofocus
        launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.opal-autofocus.agent.plist
    EOS
  end

  test do
    assert_match "opal-autofocus", shell_output("#{bin}/opal-autofocus --help")
    assert_match "0.1.0", shell_output("#{bin}/opal-autofocus --version")
  end
end
```

Stable `url`/`sha256` lines are added at release time (CONTRIBUTING, Task 10) once a tag exists.

- [ ] **Step 2: Verify the formula builds from the local checkout**

```bash
brew install --HEAD --build-from-source ./packaging/Formula/opal-autofocus.rb 2>&1 | tail -5
brew test opal-autofocus
brew services start opal-autofocus
sleep 2; tail -3 "$(brew --prefix)/var/log/opal-autofocus.log"
brew services stop opal-autofocus
brew uninstall opal-autofocus
```

`brew install` from a local path requires the formula to be fetchable; if brew refuses the `head` URL before the repository is published, run `brew audit --strict ./packaging/Formula/opal-autofocus.rb` and `ruby -c packaging/Formula/opal-autofocus.rb` instead, and note in the commit message that the install check is deferred until the repository is on GitHub.

Expected: the log shows `watching for Opal C1` and, with the camera attached, `enabled autofocus on ...`.

- [ ] **Step 3: Commit**

```bash
git add packaging/Formula
git commit -m "Add Homebrew formula with brew services support"
```

---

### Task 9: CLI integration test and CI polish

**Files:**
- Create: `Tests/OpalAutofocusCLITests/CLIBehaviourTests.swift`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Write the test**

These tests run the built binary and only assert behaviour that holds with or without a camera.

```swift
import XCTest
import Foundation

final class CLIBehaviourTests: XCTestCase {
    private var binary: URL {
        // SwiftPM puts test bundles next to the executables of the same build.
        Bundle(for: CLIBehaviourTests.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("opal-autofocus")
    }

    private func run(_ args: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = binary
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }

    func testHelpListsSubcommands() throws {
        let r = try run(["--help"])
        XCTAssertEqual(r.status, 0)
        for name in ["run", "watch", "status", "enable", "disable", "focus"] {
            XCTAssertTrue(r.stdout.contains(name), name)
        }
    }

    func testFocusOutOfRangeIsUsageError() throws {
        let r = try run(["focus", "300"])
        XCTAssertEqual(r.status, 64)
        XCTAssertTrue(r.stderr.contains("between 0 and 255"))
    }

    func testRunQuietMissingNeverFailsForAbsentDevice() throws {
        let r = try run(["run", "--timeout", "0", "--quiet-missing"])
        XCTAssertTrue(r.status == 0 || r.status == 2, "got \(r.status) stderr=\(r.stderr)")
    }
}
```

- [ ] **Step 2: Run it**

Run: `swift build && swift test --filter CLIBehaviourTests`
Expected: 3 passes. If `binary` is not found, print `Bundle(for:).bundleURL` in a failure message and adjust the relative path once; the executable is in `.build/debug/` beside `opal-autofocusPackageTests.xctest`.

- [ ] **Step 3: Make CI also build release and run the formula syntax check**

Replace the `steps` in `.github/workflows/ci.yml`:

```yaml
    steps:
      - uses: actions/checkout@v4
      - run: swift --version
      - run: swift build
      - run: swift test
      - run: swift build -c release
      - run: ruby -c packaging/Formula/opal-autofocus.rb
      - run: plutil -lint packaging/com.opal-autofocus.agent.plist
```

- [ ] **Step 4: Commit**

```bash
git add Tests .github
git commit -m "Add CLI behaviour tests and lint packaging files in CI"
```

---

### Task 10: Documentation set

**Files:**
- Modify: `README.md` (full rewrite)
- Create: `docs/ARCHITECTURE.md`, `docs/PROTOCOL.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `CLAUDE.md`

- [ ] **Step 1: README.md**

```markdown
# opal-autofocus

Keeps the Opal C1 webcam's autofocus working on macOS without running Opal
Composer.

## Why

The Opal C1 is a good UVC webcam, but out of the box its autofocus stays
parked at one distance until Opal Composer has talked to it. Composer is
heavy and no longer well maintained. It turns out the only thing Composer
sends to wake autofocus is the standard UVC "Focus, Auto" control. This tool
sends that one control whenever the camera is attached and otherwise stays
out of the way. The camera remains an ordinary UVC device for every app.

## Install

### Homebrew

    brew install h6y3/tap/opal-autofocus
    brew services start opal-autofocus

`brew services` runs `opal-autofocus watch`, a resident process that sleeps
until the camera is attached. If you would rather have nothing running while
the camera is unplugged, follow the caveats printed by `brew install` to load
the event-driven launchd agent instead.

### From source

    git clone https://github.com/h6y3/opal-autofocus.git
    cd opal-autofocus
    make install

`make install` builds a release binary into `~/.local/bin`, writes
`~/Library/LaunchAgents/com.opal-autofocus.agent.plist`, and loads it. The
agent is started by launchd only when an Opal C1 appears; it enables
autofocus and exits. Remove everything with `make uninstall`.

Requirements: macOS 13 or newer, Swift 5.9 or newer (Xcode 15 or the
Command Line Tools).

## Usage

    opal-autofocus status          # show attached cameras and focus state
    opal-autofocus enable          # turn continuous autofocus on
    opal-autofocus disable         # park the lens where it is
    opal-autofocus focus 180       # fixed focus position, 0 near to 255 far
    opal-autofocus run             # what the launchd agent runs
    opal-autofocus watch           # stay resident and handle each attach

Exit codes: 0 success, 1 no camera attached, 2 the camera rejected a request.

`focus` is the closest the hardware gets to background blur: the C1 has a
fixed aperture, so the only way to soften a background is to put the focus
plane where you want it. Composer's blur is done in software and is not part
of this tool.

## Troubleshooting

- `opal-autofocus status` prints the control values the camera reports. If
  `autofocus: off` persists after `enable`, include that output in a bug
  report together with `system_profiler SPUSBDataType | grep -A8 Opal`.
- Agent logs: `~/Library/Logs/opal-autofocus/agent.log` (make install) or
  `$(brew --prefix)/var/log/opal-autofocus.log` (brew services).
- `could not open device: kIOReturnExclusiveAccess` means another process
  holds the USB device exclusively (a browser tab with WebUSB access, for
  example). Close it and run `opal-autofocus enable`.
- Composer can stay installed; the two do not conflict. Composer's own
  background helpers may also enable autofocus after Composer has run once.

## How it works

See `docs/ARCHITECTURE.md` for the code layout and `docs/PROTOCOL.md` for
what the camera exposes and how that was found.

## Prior art

- [cansik/open-opal](https://github.com/cansik/open-opal): drives the C1
  through Luxonis depthai, which reboots the camera into a different mode.
  Useful for computer vision; not a drop-in webcam fix.
- [luxonis/depthai-core](https://github.com/luxonis/depthai-core): the
  framework the camera's chip is built around.

## License

MIT. See `LICENSE`.
```

- [ ] **Step 2: docs/ARCHITECTURE.md**

```markdown
# Architecture

## Targets

- `COpalUSB` (C): wraps IOKit's COM-style `IOUSBDeviceInterface` in three
  functions: `opal_usb_open`, `opal_usb_request`, `opal_usb_close`. Swift
  cannot call the vtable function pointers in those interfaces, so this shim
  exists. It opens the device at device level and never claims an interface,
  which is why it coexists with the system UVC driver.
- `OpalUVC` (Swift library):
  - `Models.swift`: table of supported cameras (VID, PID, camera terminal id,
    control interface). Add a model here.
  - `Controls.swift`: UVC camera terminal controls we use (selector, size).
    Add a control here.
  - `UVCRequest.swift`: packs a class request (`bmRequestType`, `bRequest`,
    `wValue = selector << 8`, `wIndex = unit << 8 | interface`) and
    little-endian payloads.
  - `OpalDevice.swift`: IOKit matching and discovery.
  - `Connection.swift`: an open handle; `perform(_:payload:)` runs one request.
  - `FocusControl.swift`: `enableAutofocus`, `disableAutofocus`, `setFocus`,
    `focusStatus`.
  - `DeviceWatcher.swift`: `IOServiceAddMatchingNotification` first-match
    callbacks on a dispatch queue.
- `OpalAutofocusCLI` (executable `opal-autofocus`): swift-argument-parser
  subcommands. `KickLoop.swift` holds the retry logic for `run` behind a
  small protocol so it is unit-tested with fakes.

## Process model

Two ways to run, both producing the same USB write:

1. Event-driven agent (`packaging/com.opal-autofocus.agent.plist`, used by
   `make install`). launchd watches IOKit for VID 0x03e7 / PID 0xf63d. On a
   match it starts `opal-autofocus run --quiet-missing`, which polls for up
   to 5 s, enables autofocus, and exits. Nothing runs while the camera is
   unplugged. `RunAtLoad` covers logging in with the camera attached.
2. Resident watcher (`opal-autofocus watch`, used by `brew services`).
   Homebrew's service DSL cannot express `LaunchEvents`, so brew users get a
   sleeping process that is woken by IOKit on attach.

## Error handling

`UVCError` carries the IOReturn and the request name. The CLI maps outcomes
to exit codes 0 / 1 / 2; `run --quiet-missing` turns "no device" into 0 so
launchd does not record a failure when the camera leaves before we start.

## Adding another Opal model

1. Read its descriptors (`system_profiler SPUSBDataType`, or the parser in
   `docs/PROTOCOL.md`) to get the camera terminal id and control interface.
2. Add a `CameraModel` to `KnownModels.all`.
3. Add its PID to the `LaunchEvents` block in the plist (one entry per PID).
4. Run `scripts/smoke.sh` against the hardware and record the result in
   `docs/PROTOCOL.md`.
```

- [ ] **Step 3: docs/PROTOCOL.md**

```markdown
# What the Opal C1 exposes

Findings from 2026-10-16 on an Opal C1 (USB `03e7:f63d`, firmware 0x0410)
on macOS 27, Apple Silicon.

## Interfaces

| # | Class | Name | Notes |
|---|---|---|---|
| 0 | 0xff vendor | `S_BULKDATA` | XLink bulk endpoints 0x01 / 0x81. Does not respond to XLink connects while the camera runs its UVC firmware. |
| 1 | 0x0e/0x01 | UVC VideoControl | Input terminal 1 (camera), processing unit 3, extension unit 4 (GUID all 0xff, reads return junk), output terminal 2. |
| 2 | 0x0e/0x02 | UVC VideoStreaming | Bulk endpoint 0x82. |
| 3 | 0x01/0x01 | Audio control | |
| 4 | 0x01/0x02 | Audio streaming | Microphone. |

## Focus controls

Camera terminal unit 1, interface 1 (`wIndex = 0x0101`):

| Control | Selector | Size | Observed | Effect |
|---|---|---|---|---|
| Focus, Auto | 0x08 | 1 | INFO 0x01, MIN 0, MAX 1, DEF 1 | SET_CUR 0 parks the lens. SET_CUR 1 enables continuous autofocus. |
| Focus, Absolute | 0x06 | 2 | INFO 0x03, MIN 0, MAX 255, DEF 130 | Honoured when Focus-Auto is 0. 0 is nearest, 255 farthest. GET_CUR returns the last written value, not the live lens position. |

Both effects were confirmed by hand: with Focus-Auto = 0 a hand held near
the lens stays blurry; after SET_CUR Focus-Auto = 1 it snaps into focus and
keeps tracking. A Laplacian-variance sharpness meter on captured frames
showed the same (122 in focus, 38 and 18 after manual positions 16 and 255,
back to 122 after Focus-Auto = 1).

Writing Focus-Auto = 1 also resets the Focus-Absolute readback to its
default.

## What Opal Composer does

Composer's `OpalCameraUVCService` helper is a standard UVC controller built
on libusb. Its autofocus path sends `SET_CUR` on `CT_FOCUS_AUTO_CONTROL`
(selector 8, one byte, value 1) to unit 1, interface 1: the same request this
tool sends. No vendor request, extension-unit write, XLink message or
firmware upload is involved.

Composer's `OpalCameraDeviceService` links Luxonis depthai and libusb. It
also contains a one-shot standard request (`bRequest 0xF5`, `wValue 0x0DA1`)
addressed to a sibling product id `03e7:f63b`; this looks like a mode switch
for a camera that enumerates in that other state and was not needed here.

## Things that did not work

- Connecting over XLink (depthai 2.15 or 2.33) to the running camera: the
  first bulk write never completes. The camera reports `FLASH_BOOTED` and
  depthai's normal path would reboot it into Luxonis firmware, which is what
  open-opal does and which changes the camera's USB identity.
- Reading the live lens position: not exposed.
- Power-cycling the hub port with `uhubctl` on a VIA Labs hub re-enumerated
  the device but did not reset its state; only a physical replug does.

## Open question

On one physical replug during research the camera came up with autofocus
already working, before this tool sent anything. Composer installs a
LaunchDaemon (`com.opalcamera.Opal.v2.cameraExtensionShim`) and a login item
(`OpalLauncher.app`); one of them may send the kick after Composer has run
once per boot. Sending Focus-Auto = 1 on every attach is harmless, so this
tool does not depend on the answer. Status: to be verified by rebooting with
those helpers disabled (see CONTRIBUTING.md, "Hardware verification").

## Method

- `system_profiler SPUSBDataType` and `ioreg -p IOUSB -l` for ids and
  interface layout; a small pyusb script to parse the UVC descriptors.
- An 80-line C program using `IOUSBDeviceInterface::DeviceRequest` to read
  and write the controls while Photo Booth or ffmpeg streamed.
- ffmpeg frame grabs plus Laplacian variance to measure focus objectively.
- `strings` and static disassembly of Composer's helpers to confirm which
  request it sends. Nothing from Composer is redistributed.
```

- [ ] **Step 4: CONTRIBUTING.md**

```markdown
# Contributing

## Build and test

    swift build
    swift test
    make smoke        # needs the camera and a preview app

CI runs `swift build`, `swift test`, a release build, and lints the formula
and plist on a macOS runner. CI has no camera, so any change to the USB path
needs a manual `make smoke` and a note in the pull request saying it was done.

## Hardware verification

Before a release, with an Opal C1:

1. `make install`, plug the camera in, confirm a new `enabled autofocus` line
   in `~/Library/Logs/opal-autofocus/agent.log`.
2. `make smoke` and answer the prompts honestly.
3. If you can, reboot with Opal Composer's helpers disabled
   (`sudo launchctl bootout system /Library/LaunchDaemons/com.opalcamera.Opal.v2.cameraExtensionShim.plist`
   and remove `Opal Composer` from System Settings > General > Login Items),
   plug the camera in, confirm it is parked, then confirm the agent fixes it.
   Record the result in `docs/PROTOCOL.md`.

## Code style

Swift defaults (4-space indent, trailing commas in multi-line literals).
Keep files to one responsibility. No comments that restate the code; a
comment is for a non-obvious constraint.

## Adding a camera or a control

See `docs/ARCHITECTURE.md`. Every table entry needs a unit test in
`Tests/OpalUVCTests` and a smoke-test result in `docs/PROTOCOL.md`.

## Changelog and releases

`CHANGELOG.md` follows Keep a Changelog. Add a line under `Unreleased` with
each user-visible change. To release:

1. Move `Unreleased` to a new version heading with today's date.
2. Bump `OpalUVC.version` in `Sources/OpalUVC/OpalUVC.swift`.
3. Tag `vX.Y.Z` and push.
4. Add `url` and `sha256` for the tag tarball to
   `packaging/Formula/opal-autofocus.rb` (`curl -L <url> | shasum -a 256`).
```

- [ ] **Step 5: CHANGELOG.md and CLAUDE.md**

`CHANGELOG.md`:

```markdown
# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `run`, `watch`, `status`, `enable`, `disable`, `focus` subcommands.
- launchd user agent triggered by IOKit matching; `make install`.
- Homebrew formula with `brew services` support.
```

`CLAUDE.md`:

```markdown
# opal-autofocus

Swift CLI and launchd agent that enables the Opal C1's autofocus via the
standard UVC Focus-Auto control. Read `docs/ARCHITECTURE.md` before changing
code and `docs/PROTOCOL.md` before touching anything USB-related.

- Build and test: `swift build && swift test`. Hardware checks: `make smoke`.
- Changes to `Sources/OpalUVC` or `Sources/COpalUSB` need a manual hardware
  check; say in the commit or PR whether it was done.
- Keep the camera and control tables (`Models.swift`, `Controls.swift`) the
  only place hardware constants live.
- Update `CHANGELOG.md` under `Unreleased` for user-visible changes.
```

- [ ] **Step 6: Check links and render**

Run: `grep -rn "OWNER" . --exclude-dir=.build --exclude-dir=.git` (expected: no output) and `ls docs/ARCHITECTURE.md docs/PROTOCOL.md CONTRIBUTING.md CHANGELOG.md CLAUDE.md LICENSE`.

- [ ] **Step 7: Commit**

```bash
git add README.md docs/ARCHITECTURE.md docs/PROTOCOL.md CONTRIBUTING.md CHANGELOG.md CLAUDE.md
git commit -m "Write README, architecture and protocol notes, contributing guide and changelog"
```

---

### Task 11: Publish, tag v0.1.0

**Files:**
- Modify: `CHANGELOG.md`, `packaging/Formula/opal-autofocus.rb`

Do this only after Tasks 4 to 7 hardware checks passed.

- [ ] **Step 1: Final local checks**

```bash
swift test
swift build -c release
git status --short   # expected: clean
```

- [ ] **Step 2: Cut the changelog**

In `CHANGELOG.md`, rename `## [Unreleased]` to `## [0.1.0] - <today's date>`, add an empty `## [Unreleased]` above it, and add link references at the bottom:

```markdown
[Unreleased]: https://github.com/h6y3/opal-autofocus/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/h6y3/opal-autofocus/releases/tag/v0.1.0
```

Commit: `git commit -am "Release 0.1.0"`.

- [ ] **Step 3: Create the GitHub repository and push**

```bash
gh auth status
gh repo create h6y3/opal-autofocus --public --source . --remote origin \
  --description "Keep the Opal C1 webcam's autofocus enabled on macOS without Opal Composer"
git push -u origin main
gh run watch --exit-status $(gh run list --limit 1 --json databaseId -q '.[0].databaseId')
```

Expected: CI passes on GitHub. If it fails, fix on `main` before tagging.

- [ ] **Step 4: Tag and release**

```bash
git tag -a v0.1.0 -m "opal-autofocus 0.1.0"
git push origin v0.1.0
gh release create v0.1.0 --title "0.1.0" --notes-file <(sed -n '/## \[0.1.0\]/,/## \[/p' CHANGELOG.md | sed '$d')
```

- [ ] **Step 5: Pin the formula to the release**

```bash
URL=https://github.com/h6y3/opal-autofocus/archive/refs/tags/v0.1.0.tar.gz
SHA=$(curl -sL "$URL" | shasum -a 256 | cut -d' ' -f1)
echo "$SHA"
```

In `packaging/Formula/opal-autofocus.rb`, add above the `head` line:

```ruby
  url "https://github.com/h6y3/opal-autofocus/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "<SHA>"
```

Commit `"Pin Homebrew formula to v0.1.0"` and push.

---

### Task 12: Homebrew tap

**Files (in a new repository `h6y3/homebrew-tap`, cloned to the scratchpad):**
- Create: `Formula/opal-autofocus.rb` (copy of the pinned formula), `README.md`

- [ ] **Step 1: Create and clone the tap**

```bash
gh repo create h6y3/homebrew-tap --public --description "Homebrew formulae by h6y3"
gh repo clone h6y3/homebrew-tap "$SCRATCH/homebrew-tap"
```

- [ ] **Step 2: Add the formula and README**

```bash
mkdir -p "$SCRATCH/homebrew-tap/Formula"
cp packaging/Formula/opal-autofocus.rb "$SCRATCH/homebrew-tap/Formula/"
```

`README.md` in the tap:

```markdown
# h6y3/homebrew-tap

    brew install h6y3/tap/opal-autofocus

| Formula | Description |
|---|---|
| [opal-autofocus](https://github.com/h6y3/opal-autofocus) | Keep the Opal C1 webcam's autofocus enabled on macOS without Opal Composer |
```

Commit `"Add opal-autofocus 0.1.0"` and push.

- [ ] **Step 3: Verify the published install path**

```bash
brew tap h6y3/tap
brew install h6y3/tap/opal-autofocus
brew test opal-autofocus
opal-autofocus --version     # expected: 0.1.0
brew audit --strict --online h6y3/tap/opal-autofocus
```

Since the Mac keeps the `make install` agent (Task 7), do not also run `brew services start`; uninstall the brew copy afterwards with `brew uninstall opal-autofocus` so only one agent is active, and note this in the final summary.

- [ ] **Step 4: Point the README at the tap**

Confirm `README.md` uses `brew install h6y3/tap/opal-autofocus` (it already should) and that `CONTRIBUTING.md` says formula changes must be copied to the tap on release. Commit and push if anything changed.
