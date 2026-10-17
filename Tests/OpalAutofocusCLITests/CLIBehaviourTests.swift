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
        for name in ["run", "watch", "status", "enable", "disable", "focus"] {
            #expect(r.stdout.contains(name), "missing \(name)")
        }
    }

    @Test func focusOutOfRangeIsUsageError() throws {
        let r = try run(["focus", "70000"])
        #expect(r.status == 64)
        #expect(r.stderr.contains("between 0 and 65535"))
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
