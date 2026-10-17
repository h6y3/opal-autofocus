import Testing
@testable import OpalAutofocusCLI

private final class FakeFocusTarget: FocusTarget {
    let label: String
    let range: Result<ClosedRange<Int>, Boom>
    let writeError: Boom?
    private(set) var written: [Int] = []

    init(label: String, range: Result<ClosedRange<Int>, Boom>, writeError: Boom? = nil) {
        self.label = label
        self.range = range
        self.writeError = writeError
    }

    func focusRange() throws -> ClosedRange<Int> {
        try range.get()
    }

    func setFocus(_ position: Int) throws {
        written.append(position)
        if let writeError { throw writeError }
    }
}

@Suite struct FocusApplyTests {
    @Test func writesInRangePositionToEveryCamera() {
        let a = FakeFocusTarget(label: "a", range: .success(0...255))
        let b = FakeFocusTarget(label: "b", range: .success(0...255))
        var logged: [String] = []
        var failed: [String] = []
        let code = applyFocus(200, to: [a, b], log: { logged.append($0) }, fail: { failed.append($0) })
        #expect(code == ExitStatus.ok)
        #expect(a.written == [200])
        #expect(b.written == [200])
        #expect(logged == ["set focus position 200 on a", "set focus position 200 on b"])
        #expect(failed.isEmpty)
    }

    @Test func boundaryValuesAreAccepted() {
        let a = FakeFocusTarget(label: "a", range: .success(10...20))
        var logged: [String] = []
        var failed: [String] = []
        for position in [10, 20] {
            let code = applyFocus(position, to: [a], log: { logged.append($0) }, fail: { failed.append($0) })
            #expect(code == ExitStatus.ok)
        }
        #expect(a.written == [10, 20])
    }

    @Test func outOfRangeOnAnyCameraWritesNothing() {
        let a = FakeFocusTarget(label: "a", range: .success(0...255))
        let b = FakeFocusTarget(label: "b", range: .success(0...100))
        var logged: [String] = []
        var failed: [String] = []
        let code = applyFocus(150, to: [a, b], log: { logged.append($0) }, fail: { failed.append($0) })
        #expect(code == ExitStatus.usage)
        #expect(a.written.isEmpty)
        #expect(b.written.isEmpty)
        #expect(logged.isEmpty)
        #expect(failed == ["b: position 150 is outside this camera's range 0...100"])
    }

    @Test func outOfRangeWinsOverReadFailure() {
        let a = FakeFocusTarget(label: "a", range: .failure(Boom()))
        let b = FakeFocusTarget(label: "b", range: .success(0...100))
        var logged: [String] = []
        var failed: [String] = []
        let code = applyFocus(150, to: [a, b], log: { logged.append($0) }, fail: { failed.append($0) })
        #expect(code == ExitStatus.usage)
        #expect(a.written.isEmpty)
        #expect(b.written.isEmpty)
        #expect(logged.isEmpty)
        #expect(failed.contains("b: position 150 is outside this camera's range 0...100"))
    }

    @Test func readFailureSkipsThatCameraOnly() {
        let a = FakeFocusTarget(label: "a", range: .failure(Boom()))
        let b = FakeFocusTarget(label: "b", range: .success(0...255))
        var logged: [String] = []
        var failed: [String] = []
        let code = applyFocus(50, to: [a, b], log: { logged.append($0) }, fail: { failed.append($0) })
        #expect(code == ExitStatus.requestFailed)
        #expect(a.written.isEmpty)
        #expect(b.written == [50])
        #expect(failed == ["a: \(Boom.message)"])
        #expect(logged == ["set focus position 50 on b"])
    }

    @Test func writeFailureIsRequestFailure() {
        let a = FakeFocusTarget(label: "a", range: .success(0...255), writeError: Boom())
        var logged: [String] = []
        var failed: [String] = []
        let code = applyFocus(200, to: [a], log: { logged.append($0) }, fail: { failed.append($0) })
        #expect(code == ExitStatus.requestFailed)
        #expect(failed == ["a: \(Boom.message)"])
        #expect(logged.isEmpty)
    }

    @Test func noCamerasIsNoDevice() {
        var logged: [String] = []
        var failed: [String] = []
        let code = applyFocus(200, to: [], log: { logged.append($0) }, fail: { failed.append($0) })
        #expect(code == ExitStatus.noDevice)
        #expect(logged.isEmpty)
        #expect(failed == ["no Opal camera attached"])
    }
}
