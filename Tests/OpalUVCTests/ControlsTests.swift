import Testing
@testable import OpalUVC

@Suite struct ControlsTests {
    @Test func maxEncodableValueFollowsControlSize() {
        #expect(CameraTerminalControl.focusAbsolute.maxEncodableValue == 65535)
        #expect(CameraTerminalControl.focusAuto.maxEncodableValue == 255)
    }
}
