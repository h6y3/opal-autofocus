/// A camera we know how to talk to. Add a new entry for another Opal model;
/// the unit and interface ids come from the camera's UVC descriptors.
public struct CameraModel: Equatable, Sendable {
    public let name: String
    public let vendorID: UInt16
    public let productID: UInt16
    public let cameraTerminalID: UInt8
    public let controlInterface: UInt8

    public init(name: String, vendorID: UInt16, productID: UInt16, cameraTerminalID: UInt8, controlInterface: UInt8) {
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.cameraTerminalID = cameraTerminalID
        self.controlInterface = controlInterface
    }
}

public enum KnownModels {
    public static let opalC1 = CameraModel(
        name: "Opal C1", vendorID: 0x03e7, productID: 0xf63d, cameraTerminalID: 1, controlInterface: 1)

    public static let all: [CameraModel] = [opalC1]

    public static func match(vendorID: UInt16, productID: UInt16) -> CameraModel? {
        all.first { $0.vendorID == vendorID && $0.productID == productID }
    }
}
