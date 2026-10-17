import Foundation

/// What `watch` does for one attached camera: settle, then send the writes through `Retry`.
struct WatchKick {
    var settle: TimeInterval
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var log: (String) -> Void
    var fail: (String) -> Void

    func run(_ target: AutofocusTarget) {
        log("attached: \(target.label)")
        if settle > 0 { sleep(settle) }
        let retry = Retry(sleep: sleep, log: log)
        if let error = retry.attempt(target.label, { try target.kick() }) {
            fail("\(target.label): \(error)")
        } else {
            log("enabled autofocus on \(target.label)")
        }
    }
}
