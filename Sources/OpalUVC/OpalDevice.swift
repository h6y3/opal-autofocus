import Foundation
import IOKit
import IOKit.usb

/// One attached camera, backed by an IOKit service handle.
public final class OpalDevice {
    public let model: CameraModel
    public let serial: String?
    public let locationID: UInt32
    let service: io_service_t

    init(service: io_service_t, model: CameraModel) {
        self.service = service
        self.model = model
        self.serial = (OpalDevice.property(service, "kUSBSerialNumberString")
            ?? OpalDevice.property(service, "USB Serial Number")) as? String
        self.locationID = (OpalDevice.property(service, "locationID") as? NSNumber)?.uint32Value ?? 0
    }

    deinit { IOObjectRelease(service) }

    /// "0x01220000"; the location string shown in labels and JSON output.
    public var locationString: String {
        String(format: "0x%08x", locationID)
    }

    /// "Opal C1 (serial 1944..., location 0x01220000)"
    public var label: String {
        "\(model.name) (serial \(serial ?? "unknown"), location \(locationString))"
    }

    public static func matchingDictionary(for model: CameraModel) -> CFMutableDictionary {
        let dict = IOServiceMatching("IOUSBHostDevice")!
        let mutable = dict as NSMutableDictionary
        mutable["idVendor"] = Int(model.vendorID)
        mutable["idProduct"] = Int(model.productID)
        return dict
    }

    public static func model(for service: io_service_t, among models: [CameraModel]) -> CameraModel? {
        guard let vendor = (property(service, "idVendor") as? NSNumber)?.uint16Value,
              let product = (property(service, "idProduct") as? NSNumber)?.uint16Value else { return nil }
        return models.first { $0.vendorID == vendor && $0.productID == product }
    }

    public static func find(models: [CameraModel] = KnownModels.all) throws -> [OpalDevice] {
        var found: [OpalDevice] = []
        for model in models {
            var iterator: io_iterator_t = 0
            // IOServiceGetMatchingServices consumes one reference to the dictionary.
            let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary(for: model), &iterator)
            guard kr == KERN_SUCCESS else { throw UVCError.ioKit(kr, "IOServiceGetMatchingServices") }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                found.append(OpalDevice(service: service, model: model))
            }
        }
        return found
    }

    public func open() throws -> Connection {
        try Connection(device: self)
    }

    static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
