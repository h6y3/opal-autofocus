import Testing
import Foundation
import OpalUVC
@testable import OpalAutofocusCLI

private struct ParseFailure: Error {}

private func parse(_ json: String) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
        throw ParseFailure()
    }
    return object
}

private func camerasIn(_ parsed: [String: Any]) throws -> [[String: Any]] {
    guard let array = parsed["cameras"] as? [[String: Any]] else { throw ParseFailure() }
    return array
}

private func firstCamera(_ parsed: [String: Any]) throws -> [String: Any] {
    guard let camera = try camerasIn(parsed).first else { throw ParseFailure() }
    return camera
}

private func range(_ string: String, _ needle: String) throws -> Range<String.Index> {
    guard let found = string.range(of: needle) else { throw ParseFailure() }
    return found
}

@Suite struct StatusJSONTests {
    private let attached = CameraSnapshot(
        model: "Opal C1",
        serial: "1944301031042E1800",
        location: "0x01220000",
        label: "Opal C1 (serial 1944301031042E1800, location 0x01220000)",
        reading: .status(FocusStatus(autofocus: true, position: 130, minimum: 0, maximum: 255, defaultPosition: 130)))

    @Test func rendersOneCamera() throws {
        let parsed = try parse(StatusJSON.render([attached]))
        #expect(parsed["schema"] as? Int == 1)
        let camera = try firstCamera(parsed)
        #expect(camera["model"] as? String == "Opal C1")
        #expect(camera["serial"] as? String == "1944301031042E1800")
        #expect(camera["location"] as? String == "0x01220000")
        #expect(camera["autofocus"] as? Bool == true)
        #expect(camera["position"] as? Int == 130)
        #expect(camera["minimum"] as? Int == 0)
        #expect(camera["maximum"] as? Int == 255)
        #expect(camera["default"] as? Int == 130)
        #expect(Set(camera.keys) == ["model", "serial", "location", "autofocus", "position", "minimum", "maximum", "default"])
    }

    @Test func nullSerialIsExplicitNull() throws {
        let parsed = try parse(StatusJSON.render([CameraSnapshot(
            model: "Opal C1",
            serial: nil,
            location: "0x01220000",
            label: "Opal C1 (serial unknown, location 0x01220000)",
            reading: .status(FocusStatus(autofocus: false, position: 130, minimum: 0, maximum: 255, defaultPosition: 130)))]))
        let camera = try firstCamera(parsed)
        #expect(camera["serial"] is NSNull)
    }

    @Test func failedCameraHasErrorAndNoFocusFields() throws {
        let parsed = try parse(StatusJSON.render([CameraSnapshot(
            model: "Opal C1",
            serial: "1944301031042E1800",
            location: "0x01220000",
            label: "Opal C1 (serial 1944301031042E1800, location 0x01220000)",
            reading: .failed(Boom.message))]))
        let camera = try firstCamera(parsed)
        #expect(Set(camera.keys) == ["model", "serial", "location", "error"])
        #expect(camera["error"] as? String == Boom.message)
    }

    @Test func noCameras() throws {
        let parsed = try parse(StatusJSON.render([]))
        #expect(parsed["schema"] as? Int == 1)
        #expect(try camerasIn(parsed).isEmpty)
    }

    @Test func keysAreSortedAndPretty() throws {
        let json = StatusJSON.render([attached])
        #expect(json.contains("\"cameras\" : ["))
        #expect(json.contains("\"schema\" : 1"))
        #expect(try range(json, "\"cameras\"").lowerBound < range(json, "\"schema\"").lowerBound)
    }
}
