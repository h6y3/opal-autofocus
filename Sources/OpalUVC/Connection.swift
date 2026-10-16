import Foundation
import IOKit
import COpalUSB

/// An open device-level handle. Released when the object goes away.
public final class Connection {
    public let device: OpalDevice
    private let handle: OpaquePointer

    init(device: OpalDevice) throws {
        var out: OpaquePointer? = nil
        let kr = opal_usb_open(device.service, &out)
        guard kr == KERN_SUCCESS, let out else { throw UVCError.openFailed(kr) }
        self.device = device
        self.handle = out
    }

    deinit { opal_usb_close(handle) }

    /// Runs one control request. Returns the bytes read for IN requests, [] for OUT.
    public func perform(_ request: UVCRequest, payload: [UInt8] = []) throws -> [UInt8] {
        var buffer = request.isInput ? [UInt8](repeating: 0, count: Int(request.length)) : payload
        precondition(buffer.count == Int(request.length), "payload must be \(request.length) bytes")
        var done: UInt32 = 0
        let kr = buffer.withUnsafeMutableBytes { raw in
            opal_usb_request(handle, request.bmRequestType, request.bRequest, request.wValue,
                             request.wIndex, raw.baseAddress, request.length, &done)
        }
        guard kr == KERN_SUCCESS else { throw UVCError.ioKit(kr, request.debugName) }
        return request.isInput ? Array(buffer.prefix(Int(done))) : []
    }
}
