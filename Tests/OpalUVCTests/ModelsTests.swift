import Testing
@testable import OpalUVC

@Suite struct ModelsTests {
    @Test func opalC1Constants() {
        let m = KnownModels.opalC1
        #expect(m.vendorID == 0x03e7)
        #expect(m.productID == 0xf63d)
        #expect(m.cameraTerminalID == 1)
        #expect(m.controlInterface == 1)
    }

    @Test func matchFindsKnownAndRejectsUnknown() {
        #expect(KnownModels.match(vendorID: 0x03e7, productID: 0xf63d) == KnownModels.opalC1)
        #expect(KnownModels.match(vendorID: 0x03e7, productID: 0xf63b) == nil)
    }

    @Test func allModelsHaveUniqueIDs() {
        let ids = KnownModels.all.map { "\($0.vendorID):\($0.productID)" }
        #expect(Set(ids).count == ids.count)
    }
}
