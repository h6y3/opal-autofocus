/// UVC Camera Terminal controls (USB Video Class 1.1, table 4-9).
public struct CameraTerminalControl: Equatable, Sendable {
    public let name: String
    public let selector: UInt8
    public let size: Int

    public static let focusAbsolute = CameraTerminalControl(name: "Focus-Absolute", selector: 0x06, size: 2)
    public static let focusAuto = CameraTerminalControl(name: "Focus-Auto", selector: 0x08, size: 1)

    public static let all: [CameraTerminalControl] = [focusAbsolute, focusAuto]
}
