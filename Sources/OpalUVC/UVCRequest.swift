/// One UVC class request on the default control pipe.
public struct UVCRequest: Equatable, Sendable {
    public enum Code: UInt8, Sendable {
        case setCur = 0x01
        case getCur = 0x81
        case getMin = 0x82
        case getMax = 0x83
        case getInfo = 0x86
        case getDef = 0x87

        var name: String {
            switch self {
            case .setCur: return "SET_CUR"
            case .getCur: return "GET_CUR"
            case .getMin: return "GET_MIN"
            case .getMax: return "GET_MAX"
            case .getInfo: return "GET_INFO"
            case .getDef: return "GET_DEF"
            }
        }
    }

    public let bmRequestType: UInt8
    public let bRequest: UInt8
    public let wValue: UInt16
    public let wIndex: UInt16
    public let length: UInt16
    public let debugName: String

    public var isInput: Bool { bmRequestType & 0x80 != 0 }

    public static func setCurrent(_ control: CameraTerminalControl, model: CameraModel) -> UVCRequest {
        UVCRequest(
            bmRequestType: 0x21, bRequest: Code.setCur.rawValue,
            wValue: UInt16(control.selector) << 8,
            wIndex: UInt16(model.cameraTerminalID) << 8 | UInt16(model.controlInterface),
            length: UInt16(control.size),
            debugName: "\(Code.setCur.name) \(control.name)")
    }

    public static func get(_ code: Code, _ control: CameraTerminalControl, model: CameraModel) -> UVCRequest {
        UVCRequest(
            bmRequestType: 0xA1, bRequest: code.rawValue,
            wValue: UInt16(control.selector) << 8,
            wIndex: UInt16(model.cameraTerminalID) << 8 | UInt16(model.controlInterface),
            length: code == .getInfo ? 1 : UInt16(control.size),
            debugName: "\(code.name) \(control.name)")
    }
}

public enum LittleEndian {
    public static func encode(_ value: Int, size: Int) -> [UInt8] {
        (0..<size).map { UInt8((value >> (8 * $0)) & 0xff) }
    }

    public static func decode(_ bytes: [UInt8]) -> Int {
        bytes.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
    }
}
