import Foundation
import OpalUVC

/// The real system behind `DoctorEnvironment`: the user's launchd plists,
/// `launchctl print`, the camera and the agent log. Doctor only reads through it.
struct LiveDoctorEnvironment: DoctorEnvironment {
    var home: String { FileManager.default.homeDirectoryForCurrentUser.path }
    var userID: UInt32 { getuid() }
    var executablePath: String {
        Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
    }

    func fileExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func plist(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        do {
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        } catch {
            return nil
        }
    }

    func isLoaded(label: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(userID)/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    func cameras() throws -> [CameraSnapshot] {
        try OpalDevice.find().map(CameraSnapshot.take)
    }

    func lastLines(of path: String, count: Int) -> [String]? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.suffix(count))
    }
}
