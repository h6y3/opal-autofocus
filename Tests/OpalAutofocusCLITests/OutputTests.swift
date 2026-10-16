import Testing
import Foundation
@testable import OpalAutofocusCLI

@Suite struct OutputTests {
    @Test func stampPrefixesUTCTimestamp() {
        let date = Date(timeIntervalSince1970: 1_792_183_562)  // 2026-10-16T20:46:02Z
        #expect(Output.stamp("enabled autofocus on X", at: date) == "2026-10-16T20:46:02Z enabled autofocus on X")
    }

    @Test func stampDefaultsToNow() {
        let line = Output.stamp("hello")
        #expect(line.hasSuffix(" hello"))
        #expect(line.count == "2026-10-16T20:46:02Z hello".count)
    }
}
