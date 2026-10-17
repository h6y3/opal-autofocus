import Foundation

/// Runs work once, then once more after each delay until it succeeds; returns the last error.
struct Retry {
    var delays: [TimeInterval] = [0.5, 1]
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var log: (String) -> Void = { Output.line($0) }

    func attempt(_ label: String, _ work: () throws -> Void) -> Error? {
        let attempts = delays.count + 1
        for (n, delay) in delays.enumerated() {
            do {
                try work()
                return nil
            } catch {
                log("\(label): attempt \(n + 1) of \(attempts) failed: \(error)")
                sleep(delay)
            }
        }
        do {
            try work()
            return nil
        } catch {
            return error
        }
    }
}
