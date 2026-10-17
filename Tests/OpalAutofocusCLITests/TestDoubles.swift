@testable import OpalAutofocusCLI

struct Boom: Error, CustomStringConvertible {
    static let message = "SET_CUR Focus-Auto failed: kIOReturnNotResponding (0xe00002ed)"
    var description: String { Boom.message }
}

/// Fails its first `failures` kicks and counts every attempt.
final class FlakyTarget: AutofocusTarget {
    let label: String
    private(set) var attempts = 0
    private var failures: Int
    init(label: String, failures: Int) {
        self.label = label
        self.failures = failures
    }
    func kick() throws {
        attempts += 1
        if failures > 0 { failures -= 1; throw Boom() }
    }
}
