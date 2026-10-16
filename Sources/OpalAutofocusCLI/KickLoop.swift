import Foundation
import OpalUVC

protocol AutofocusTarget {
    var label: String { get }
    func kick() throws
}

extension OpalDevice: AutofocusTarget {
    func kick() throws { try open().enableAutofocus() }
}

enum KickOutcome: Equatable {
    case kicked(Int)
    case noDevice
    case failed(message: String, kicked: Int)
}

/// Polls for cameras until one appears or the timeout passes, then enables autofocus on each.
struct KickLoop {
    var timeout: TimeInterval
    var interval: TimeInterval = 0.25
    /// Pause between finding the camera and sending the control, because the
    /// USB device can be registered before the UVC driver has bound to it.
    var settle: TimeInterval = 0
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var now: () -> Date = Date.init
    var find: () throws -> [AutofocusTarget]
    var log: (String) -> Void = { Output.line($0) }

    func run() -> KickOutcome {
        let deadline = now().addingTimeInterval(timeout)
        while true {
            let targets = (try? find()) ?? []
            if !targets.isEmpty {
                if settle > 0 { sleep(settle) }
                return kick(targets)
            }
            if now() >= deadline { return .noDevice }
            sleep(interval)
        }
    }

    private func kick(_ targets: [AutofocusTarget]) -> KickOutcome {
        var kicked = 0
        var failures: [String] = []
        for target in targets {
            do {
                try target.kick()
                kicked += 1
                log("enabled autofocus on \(target.label)")
            } catch {
                failures.append("\(target.label): \(error)")
            }
        }
        if !failures.isEmpty { return .failed(message: failures.joined(separator: "; "), kicked: kicked) }
        return .kicked(kicked)
    }

    static func exitCode(for outcome: KickOutcome, quietMissing: Bool) -> Int32 {
        switch outcome {
        case .kicked: return ExitStatus.ok
        case .noDevice: return quietMissing ? ExitStatus.ok : ExitStatus.noDevice
        case .failed: return ExitStatus.requestFailed
        }
    }
}
