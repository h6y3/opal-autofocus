import Testing
@testable import OpalUVC

@Suite struct EnableSequenceTests {
    /// A cold camera reports Focus-Auto = 1 while its lens is parked and ignores a
    /// write of 1, so enabling must move the control from 0 to 1.
    @Test func enableWritesZeroThenOne() {
        let steps = Connection.enableAutofocusSteps(model: KnownModels.opalC1)
        let focusAuto = UVCRequest.setCurrent(.focusAuto, model: KnownModels.opalC1)
        #expect(steps.map(\.request) == [focusAuto, focusAuto])
        #expect(steps.map(\.payload) == [[0x00], [0x01]])
    }
}
