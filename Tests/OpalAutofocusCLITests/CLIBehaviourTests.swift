import Testing
import Foundation
import OpalUVC

/// True when an Opal is plugged in. Tests that would send USB requests skip in that
/// case so running the suite never changes a camera's focus settings.
let opalAttached = ((try? OpalDevice.find()) ?? []).isEmpty == false

/// Runs the built opal-autofocus binary. These assertions hold with or without a camera attached.
@Suite struct CLIBehaviourTests {
    static let binary: URL = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return root.appendingPathComponent(".build/debug/opal-autofocus")
    }()

    private func run(_ args: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = Self.binary
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    @Test func binaryExists() {
        #expect(FileManager.default.isExecutableFile(atPath: Self.binary.path))
    }

    @Test func helpListsSubcommands() throws {
        let r = try run(["--help"])
        #expect(r.status == 0)
        for name in ["run", "watch", "status", "doctor", "enable", "disable", "focus"] {
            #expect(r.stdout.contains(name), "missing \(name)")
        }
    }

    @Test func doctorRuns() throws {
        let r = try run(["doctor"])
        #expect(r.status == 0 || r.status == 1, "doctor exit \(r.status), stderr: \(r.stderr)")
        #expect(r.stdout.hasPrefix("opal-autofocus "), "stdout starts with: \(r.stdout)")
    }

    @Test func focusOutOfRangeIsUsageError() throws {
        let r = try run(["focus", "70000"])
        #expect(r.status == 64)
        #expect(r.stderr.contains("between 0 and 65535"))
    }

    @Test(.disabled(if: opalAttached, "needs no camera attached"))
    func statusJSONWithoutCameraIsOnlyJSON() throws {
        let r = try run(["status", "--json"])
        #expect(r.status == 1, "status \(r.status) stderr \(r.stderr)")
        let parsed = try JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any]
        #expect((parsed?["cameras"] as? [Any])?.isEmpty == true)
        #expect(parsed?["schema"] as? Int == 1)
    }

    @Test(.enabled(if: opalAttached, "needs a camera"))
    func statusJSONWithCameraParses() throws {
        let r = try run(["status", "--json"])
        #expect(r.status == 0, "status \(r.status) stderr \(r.stderr)")
        let parsed = try JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any]
        let cameras = try #require(parsed?["cameras"] as? [[String: Any]])
        #expect(cameras.count >= 1)
        #expect(cameras[0]["model"] as? String == "Opal C1")
    }

    @Test(.disabled(if: opalAttached, "would write to the attached camera"))
    func runWithoutCameraQuietMissingExitsZero() throws {
        let r = try run(["run", "--timeout", "0", "--quiet-missing"])
        #expect(r.status == 0, "status \(r.status) stderr \(r.stderr)")
        #expect(r.stdout.isEmpty)
    }

    @Test(.disabled(if: opalAttached, "would write to the attached camera"))
    func runWithoutCameraReportsMissingDevice() throws {
        let r = try run(["run", "--timeout", "0"])
        #expect(r.status == 1)
        #expect(r.stderr.contains("no Opal camera appeared"))
    }
}
