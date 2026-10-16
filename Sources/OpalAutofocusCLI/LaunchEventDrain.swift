import Foundation
import XPC

/// launchd keeps relaunching a job started by an IOKit matching event until the job
/// takes that event off the stream, so `run --launchd` registers a handler and waits
/// briefly for the pending event before doing its work.
struct LaunchEventDrain {
    static let ioKitStream = "com.apple.iokit.matching"

    var timeout: TimeInterval
    var register: (String, @escaping () -> Void) -> Void = LaunchEventDrain.registerWithXPC

    /// Returns true if an event was consumed, false if none arrived in time
    /// (for example when launchd started the job because of RunAtLoad).
    func wait() -> Bool {
        let got = DispatchSemaphore(value: 0)
        register(Self.ioKitStream) { got.signal() }
        return got.wait(timeout: .now() + timeout) == .success
    }

    static func registerWithXPC(_ stream: String, _ deliver: @escaping () -> Void) {
        xpc_set_event_stream_handler(stream, DispatchQueue.global()) { _ in deliver() }
    }
}
