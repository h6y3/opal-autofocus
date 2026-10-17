import Testing
import Foundation
@testable import OpalUVC

@Suite struct DeviceDiscoveryTests {
    @Test func matchingDictionaryCarriesVendorAndProduct() {
        let dict = OpalDevice.matchingDictionary(for: KnownModels.opalC1) as NSDictionary
        #expect(dict["IOProviderClass"] as? String == "IOUSBHostDevice")
        #expect(dict["idVendor"] as? Int == 0x03e7)
        #expect(dict["idProduct"] as? Int == 0xf63d)
    }

    @Test func findReturnsOnlyKnownModels() throws {
        let devices = try OpalDevice.find()
        for d in devices {
            #expect(KnownModels.all.contains(d.model))
            #expect(!d.label.isEmpty)
        }
    }

    @Test func findWithUnknownModelReturnsNothing() throws {
        let bogus = CameraModel(name: "none", vendorID: 0xffff, productID: 0xffff, cameraTerminalID: 1, controlInterface: 1)
        #expect(try OpalDevice.find(models: [bogus]).isEmpty)
    }

    @Test func labelFallsBackToModelNameWhenSerialAndLocationAreUnknown() {
        let withIdentity = OpalDevice(model: KnownModels.opalC1, serial: "1944", locationID: 0x01220000)
        #expect(withIdentity.label == "Opal C1 (serial 1944, location 0x01220000)")
        // A terminated service may have lost its registry properties.
        let bare = OpalDevice(model: KnownModels.opalC1, serial: nil, locationID: 0)
        #expect(bare.label == "Opal C1")
    }
}
