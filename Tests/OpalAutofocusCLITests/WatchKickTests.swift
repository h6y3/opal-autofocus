import Testing
import Foundation
@testable import OpalAutofocusCLI

private final class Harness {
    var slept: [TimeInterval] = []
    var logged: [String] = []
    var failed: [String] = []

    var kick: WatchKick {
        WatchKick(settle: 0.25,
                  sleep: { self.slept.append($0) },
                  log: { self.logged.append($0) },
                  fail: { self.failed.append($0) })
    }
}

/// What the watch command does when the watcher reports an attach.
@Suite struct WatchKickTests {
    let boom = Boom.message

    @Test func successfulKickLogsAttachedAndEnabled() {
        let h = Harness()
        h.kick.run(FlakyTarget(label: "a", failures: 0))
        #expect(h.logged == ["attached: a", "enabled autofocus on a"])
        #expect(h.failed.isEmpty)
        #expect(h.slept == [0.25])
    }

    @Test func retriesWithBackoffBeforeReportingSuccess() {
        let h = Harness()
        let target = FlakyTarget(label: "a", failures: 2)
        h.kick.run(target)
        #expect(target.attempts == 3)
        #expect(h.slept == [0.25, 0.5, 1])
        #expect(h.logged == [
            "attached: a",
            "a: attempt 1 of 3 failed: \(boom)",
            "a: attempt 2 of 3 failed: \(boom)",
            "enabled autofocus on a",
        ])
        #expect(h.failed.isEmpty)
    }

    @Test func exhaustedRetriesLandOnTheFailChannel() {
        let h = Harness()
        let target = FlakyTarget(label: "a", failures: 99)
        h.kick.run(target)
        #expect(target.attempts == 3)
        #expect(h.failed == ["a: \(boom)"])
        #expect(h.logged == [
            "attached: a",
            "a: attempt 1 of 3 failed: \(boom)",
            "a: attempt 2 of 3 failed: \(boom)",
        ])
        #expect(h.slept == [0.25, 0.5, 1])
    }
}
