import Testing
@testable import OpalUVC

@Suite struct UVCRequestTests {
    let model = KnownModels.opalC1

    @Test func setCurrentFocusAutoPacksSelectorUnitAndInterface() {
        let r = UVCRequest.setCurrent(.focusAuto, model: model)
        #expect(r.bmRequestType == 0x21)
        #expect(r.bRequest == 0x01)
        #expect(r.wValue == 0x0800)
        #expect(r.wIndex == 0x0101)
        #expect(r.length == 1)
        #expect(!r.isInput)
    }

    @Test func getCurrentFocusAbsoluteIsTwoByteInput() {
        let r = UVCRequest.get(.getCur, .focusAbsolute, model: model)
        #expect(r.bmRequestType == 0xA1)
        #expect(r.bRequest == 0x81)
        #expect(r.wValue == 0x0600)
        #expect(r.wIndex == 0x0101)
        #expect(r.length == 2)
        #expect(r.isInput)
    }

    @Test func getInfoIsAlwaysOneByte() {
        let r = UVCRequest.get(.getInfo, .focusAbsolute, model: model)
        #expect(r.bRequest == 0x86)
        #expect(r.length == 1)
    }

    @Test func requestCodes() {
        #expect(UVCRequest.Code.getMin.rawValue == 0x82)
        #expect(UVCRequest.Code.getMax.rawValue == 0x83)
        #expect(UVCRequest.Code.getDef.rawValue == 0x87)
    }

    @Test func debugNameNamesControlAndCode() {
        #expect(UVCRequest.setCurrent(.focusAuto, model: model).debugName == "SET_CUR Focus-Auto")
        #expect(UVCRequest.get(.getDef, .focusAbsolute, model: model).debugName == "GET_DEF Focus-Absolute")
    }

    @Test func littleEndianEncode() {
        #expect(LittleEndian.encode(0x82, size: 2) == [0x82, 0x00])
        #expect(LittleEndian.encode(255, size: 2) == [0xff, 0x00])
        #expect(LittleEndian.encode(1, size: 1) == [0x01])
    }

    @Test func littleEndianDecode() {
        #expect(LittleEndian.decode([0x82, 0x00]) == 0x82)
        #expect(LittleEndian.decode([0x00, 0xff]) == 0xff00)
        #expect(LittleEndian.decode([]) == 0)
    }

    @Test(arguments: CameraTerminalControl.all)
    func everyKnownControlRoundTrips(control: CameraTerminalControl) {
        let value = (1 << (8 * control.size)) - 1
        #expect(LittleEndian.decode(LittleEndian.encode(value, size: control.size)) == value)
    }
}
