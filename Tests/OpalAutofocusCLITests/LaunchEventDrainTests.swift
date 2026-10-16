import Testing
import Foundation
@testable import OpalAutofocusCLI

@Suite struct LaunchEventDrainTests {
    @Test func registersIOKitStreamAndReturnsOnceAnEventArrives() {
        var registered: [String] = []
        let drain = LaunchEventDrain(timeout: 2) { stream, deliver in
            registered.append(stream)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { deliver() }
        }
        let start = Date()
        #expect(drain.wait() == true)
        #expect(registered == ["com.apple.iokit.matching"])
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test func givesUpAfterTimeoutWhenNoEventComes() {
        let drain = LaunchEventDrain(timeout: 0.1) { _, _ in }
        #expect(drain.wait() == false)
    }

    @Test func runAcceptsLaunchdFlag() throws {
        #expect(try Run.parse(["--launchd"]).launchd)
        #expect(try !Run.parse([]).launchd)
    }
}
