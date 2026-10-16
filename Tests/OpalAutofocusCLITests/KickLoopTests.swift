import Testing
import Foundation
@testable import OpalAutofocusCLI

private struct FakeTarget: AutofocusTarget {
    let label: String
    let error: Error?
    func kick() throws { if let error { throw error } }
}

private struct Boom: Error, CustomStringConvertible {
    var description: String { "SET_CUR Focus-Auto failed: kIOReturnNotResponding (0xe00002ed)" }
}

/// Fake clock and recorders for one KickLoop run.
private final class Harness {
    var clock: TimeInterval = 0
    var slept: [TimeInterval] = []
    var logged: [String] = []

    func loop(timeout: TimeInterval, settle: TimeInterval = 0,
              find: @escaping () throws -> [AutofocusTarget]) -> KickLoop {
        KickLoop(timeout: timeout, interval: 0.25, settle: settle,
                 sleep: { self.slept.append($0); self.clock += $0 },
                 now: { Date(timeIntervalSince1970: self.clock) },
                 find: find,
                 log: { self.logged.append($0) })
    }
}

@Suite struct KickLoopTests {
    @Test func kicksEveryDevicePresentOnFirstTry() {
        let h = Harness()
        let l = h.loop(timeout: 5) { [FakeTarget(label: "a", error: nil), FakeTarget(label: "b", error: nil)] }
        #expect(l.run() == .kicked(2))
        #expect(h.slept.isEmpty)
        #expect(h.logged == ["enabled autofocus on a", "enabled autofocus on b"])
    }

    @Test func retriesUntilDeviceAppears() {
        let h = Harness()
        var calls = 0
        let l = h.loop(timeout: 5) { calls += 1; return calls < 4 ? [] : [FakeTarget(label: "a", error: nil)] }
        #expect(l.run() == .kicked(1))
        #expect(calls == 4)
        #expect(h.slept == [0.25, 0.25, 0.25])
    }

    @Test func givesUpAtTimeout() {
        let h = Harness()
        var calls = 0
        let l = h.loop(timeout: 1.0) { calls += 1; return [] }
        #expect(l.run() == .noDevice)
        #expect(calls == 5)  // t = 0, 0.25, 0.5, 0.75, 1.0
        #expect(h.slept.count == 4)
    }

    @Test func timeoutZeroTriesExactlyOnce() {
        let h = Harness()
        var calls = 0
        let l = h.loop(timeout: 0) { calls += 1; return [] }
        #expect(l.run() == .noDevice)
        #expect(calls == 1)
        #expect(h.slept.isEmpty)
    }

    @Test func partialFailureReportsMessageAndCount() {
        let h = Harness()
        let l = h.loop(timeout: 5) { [FakeTarget(label: "a", error: nil), FakeTarget(label: "b", error: Boom())] }
        #expect(l.run() == .failed(message: "b: SET_CUR Focus-Auto failed: kIOReturnNotResponding (0xe00002ed)", kicked: 1))
    }

    @Test func everyFailureIsReported() {
        let h = Harness()
        let l = h.loop(timeout: 5) { [FakeTarget(label: "a", error: Boom()), FakeTarget(label: "b", error: Boom())] }
        let detail = "SET_CUR Focus-Auto failed: kIOReturnNotResponding (0xe00002ed)"
        #expect(l.run() == .failed(message: "a: \(detail); b: \(detail)", kicked: 0))
    }

    @Test func findErrorIsTreatedAsNoDeviceThisRound() {
        let h = Harness()
        var calls = 0
        let l = h.loop(timeout: 0.5) {
            calls += 1
            if calls == 1 { throw Boom() }
            return [FakeTarget(label: "a", error: nil)]
        }
        #expect(l.run() == .kicked(1))
    }

    @Test func settlesOnceAfterDiscoveryBeforeKicking() {
        let h = Harness()
        var kickedAt: [TimeInterval] = []
        struct Recorder: AutofocusTarget {
            let label = "a"
            let onKick: () -> Void
            func kick() throws { onKick() }
        }
        let l = h.loop(timeout: 5, settle: 0.5) { [Recorder { kickedAt.append(h.clock) }] }
        #expect(l.run() == .kicked(1))
        #expect(h.slept == [0.5])
        #expect(kickedAt == [0.5])
    }

    @Test func runDefaultSettleIsHalfASecond() throws {
        #expect(try Run.parse([]).settle == 0.5)
        #expect(throws: (any Error).self) { try Run.parse(["--settle=-1"]) }
    }

    @Test func exitCodeMapping() {
        #expect(KickLoop.exitCode(for: .kicked(1), quietMissing: false) == 0)
        #expect(KickLoop.exitCode(for: .noDevice, quietMissing: false) == 1)
        #expect(KickLoop.exitCode(for: .noDevice, quietMissing: true) == 0)
        #expect(KickLoop.exitCode(for: .failed(message: "x", kicked: 0), quietMissing: true) == 2)
        #expect(KickLoop.exitCode(for: .failed(message: "x", kicked: 3), quietMissing: false) == 2)
    }

    @Test func runCommandDefaults() throws {
        let cmd = try Run.parse([])
        #expect(cmd.timeout == 5)
        #expect(!cmd.quietMissing)
        let quiet = try Run.parse(["--quiet-missing", "--timeout", "0"])
        #expect(quiet.quietMissing)
        #expect(quiet.timeout == 0)
    }

    @Test func negativeTimeoutIsRejected() {
        #expect(throws: (any Error).self) { try Run.parse(["--timeout", "-1"]) }
    }
}
