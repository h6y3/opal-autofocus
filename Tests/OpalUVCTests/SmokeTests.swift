import Testing
@testable import OpalUVC

@Test func versionIsSemver() {
    let parts = OpalUVC.version.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}
