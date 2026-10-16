import Testing
import IOKit
@testable import OpalUVC

@Suite struct UVCErrorTests {
    @Test func descriptionNamesRequestAndCode() {
        let e = UVCError.ioKit(IOReturn(bitPattern: 0xe00002ed), "SET_CUR Focus-Auto")
        #expect(e.description == "SET_CUR Focus-Auto failed: kIOReturnNotResponding (0xe00002ed)")
    }

    @Test func descriptionForExclusiveAccess() {
        let e = UVCError.openFailed(IOReturn(bitPattern: 0xe00002c5))
        #expect(e.description == "could not open device: kIOReturnExclusiveAccess (0xe00002c5)")
    }

    @Test func pipeStallIsNamed() {
        #expect(UVCError.name(of: IOReturn(bitPattern: 0xe000404f)) == "kIOUSBPipeStalled (0xe000404f)")
    }

    @Test func unknownCodeFallsBackToHex() {
        let e = UVCError.ioKit(IOReturn(bitPattern: 0xe0001234), "GET_CUR Focus-Absolute")
        #expect(e.description == "GET_CUR Focus-Absolute failed: IOReturn (0xe0001234)")
    }
}
