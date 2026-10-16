import Testing
@testable import OpalUVC

@Suite struct FocusStatusTests {
    @Test func summaryLine() {
        let s = FocusStatus(autofocus: true, position: 130, minimum: 0, maximum: 255, defaultPosition: 130)
        #expect(s.summary == "autofocus: on, focus position: 130 (min 0, max 255, default 130)")
    }

    @Test func summaryWhenOff() {
        let s = FocusStatus(autofocus: false, position: 255, minimum: 0, maximum: 255, defaultPosition: 130)
        #expect(s.summary == "autofocus: off, focus position: 255 (min 0, max 255, default 130)")
    }
}
