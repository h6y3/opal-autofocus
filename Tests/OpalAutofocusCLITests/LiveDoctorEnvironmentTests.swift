import Testing
import Foundation
@testable import OpalAutofocusCLI

@Suite struct LiveDoctorEnvironmentTests {
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    }

    @Test func plistReadsDictionary() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["ProgramArguments": ["/bin/echo"]], format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: path))
        let plist = try #require(LiveDoctorEnvironment().plist(at: path))
        #expect(plist["ProgramArguments"] as? [String] == ["/bin/echo"])
    }

    @Test func plistReturnsNilForGarbage() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Data("not a plist".utf8).write(to: URL(fileURLWithPath: path))
        #expect(LiveDoctorEnvironment().plist(at: path) == nil)
    }

    @Test func lastLinesReturnsTail() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Data("1\n2\n3\n4\n5\n6\n7\n8\n".utf8).write(to: URL(fileURLWithPath: path))
        #expect(LiveDoctorEnvironment().lastLines(of: path, count: 5) == ["4", "5", "6", "7", "8"])
    }

    @Test func lastLinesNilWhenMissing() {
        #expect(LiveDoctorEnvironment().lastLines(of: temporaryPath(), count: 5) == nil)
    }

    @Test func isLoadedFalseForUnknownLabel() {
        #expect(LiveDoctorEnvironment().isLoaded(label: "com.example.does-not-exist") == false)
    }
}
