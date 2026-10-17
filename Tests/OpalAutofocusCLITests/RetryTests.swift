import Testing
import Foundation
@testable import OpalAutofocusCLI

@Suite struct RetryTests {
    @Test func backoffBetweenNonFinalAttempts() {
        var slept: [TimeInterval] = []
        var logged: [String] = []
        let r = Retry(sleep: { slept.append($0) }, log: { logged.append($0) })
        let err = r.attempt("Opal C1") { throw Boom() }
        #expect(String(describing: err!) == Boom.message)
        #expect(slept == [0.5, 1])
        #expect(logged == [
            "Opal C1: attempt 1 of 3 failed: \(Boom.message)",
            "Opal C1: attempt 2 of 3 failed: \(Boom.message)",
        ])
    }

    @Test func succeedingWorkIsRunOnceWithoutBackoff() {
        var slept: [TimeInterval] = []
        var calls = 0
        let r = Retry(sleep: { slept.append($0) }, log: { _ in })
        #expect(r.attempt("Opal C1") { calls += 1 } == nil)
        #expect(calls == 1)
        #expect(slept.isEmpty)
    }

    @Test func recoversAfterTransientFailures() {
        var calls = 0
        let r = Retry(sleep: { _ in }, log: { _ in })
        let err = r.attempt("Opal C1") {
            calls += 1
            if calls < 3 { throw Boom() }
        }
        #expect(err == nil)
        #expect(calls == 3)
    }

    @Test func noDelaysMeansOneAttempt() {
        var calls = 0
        let r = Retry(delays: [], sleep: { _ in Issue.record("slept") }, log: { _ in })
        #expect(r.attempt("Opal C1") { calls += 1; throw Boom() } != nil)
        #expect(calls == 1)
    }
}
