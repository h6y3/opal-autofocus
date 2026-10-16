import Foundation
import IOKit

public enum UVCError: Error, CustomStringConvertible {
    case ioKit(IOReturn, String)
    case openFailed(IOReturn)

    public var description: String {
        switch self {
        case .ioKit(let code, let request):
            return "\(request) failed: \(UVCError.name(of: code))"
        case .openFailed(let code):
            return "could not open device: \(UVCError.name(of: code))"
        }
    }

    /// IOReturn values are built from function-like C macros that Swift does not import,
    /// so the ones we name are listed by value (IOKit/IOReturn.h and IOUSBLib.h).
    static let knownCodes: [UInt32: String] = [
        0xe00002bc: "kIOReturnError",
        0xe00002bd: "kIOReturnNoMemory",
        0xe00002c0: "kIOReturnNoDevice",
        0xe00002c2: "kIOReturnBadArgument",
        0xe00002c5: "kIOReturnExclusiveAccess",
        0xe00002c7: "kIOReturnUnsupported",
        0xe00002cd: "kIOReturnNotOpen",
        0xe00002d5: "kIOReturnBusy",
        0xe00002d6: "kIOReturnTimeout",
        0xe00002d9: "kIOReturnNotAttached",
        0xe00002e2: "kIOReturnNotPermitted",
        0xe00002eb: "kIOReturnAborted",
        0xe00002ed: "kIOReturnNotResponding",
        0xe00002f0: "kIOReturnNotFound",
        0xe000404f: "kIOUSBPipeStalled",
    ]

    static func name(of code: IOReturn) -> String {
        let raw = UInt32(bitPattern: code)
        let hex = String(format: "0x%08x", raw)
        if let n = knownCodes[raw] { return "\(n) (\(hex))" }
        return "IOReturn (\(hex))"
    }
}
