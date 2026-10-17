public struct FocusStatus: Equatable, Sendable {
    public let autofocus: Bool
    public let position: Int
    public let minimum: Int
    public let maximum: Int
    public let defaultPosition: Int

    public init(autofocus: Bool, position: Int, minimum: Int, maximum: Int, defaultPosition: Int) {
        self.autofocus = autofocus
        self.position = position
        self.minimum = minimum
        self.maximum = maximum
        self.defaultPosition = defaultPosition
    }

    public var summary: String {
        "autofocus: \(autofocus ? "on" : "off"), focus position: \(position) "
            + "(min \(minimum), max \(maximum), default \(defaultPosition))"
    }
}

public struct ControlWrite: Equatable, Sendable {
    public let request: UVCRequest
    public let payload: [UInt8]
}

extension Connection {
    /// A freshly plugged-in Opal reports Focus-Auto = 1 while its lens is parked and
    /// ignores a write of 1. Autofocus starts only when the control goes from 0 to 1.
    public static func enableAutofocusSteps(model: CameraModel) -> [ControlWrite] {
        let request = UVCRequest.setCurrent(.focusAuto, model: model)
        return [ControlWrite(request: request, payload: [0]), ControlWrite(request: request, payload: [1])]
    }

    /// Turns continuous autofocus on.
    public func enableAutofocus() throws {
        for step in Connection.enableAutofocusSteps(model: device.model) {
            _ = try perform(step.request, payload: step.payload)
        }
    }

    /// Parks the lens at its current position.
    public func disableAutofocus() throws {
        try set(.focusAuto, value: 0)
    }

    /// Manual focus within focusRange(); lower is nearer.
    public func setFocus(_ position: Int) throws {
        try set(.focusAuto, value: 0)
        try set(.focusAbsolute, value: position)
    }

    public func focusRange() throws -> ClosedRange<Int> {
        let minimum = try get(.focusAbsolute, .getMin)
        let maximum = try get(.focusAbsolute, .getMax)
        return minimum...maximum
    }

    public func focusStatus() throws -> FocusStatus {
        FocusStatus(
            autofocus: try get(.focusAuto, .getCur) != 0,
            position: try get(.focusAbsolute, .getCur),
            minimum: try get(.focusAbsolute, .getMin),
            maximum: try get(.focusAbsolute, .getMax),
            defaultPosition: try get(.focusAbsolute, .getDef))
    }

    func set(_ control: CameraTerminalControl, value: Int) throws {
        let request = UVCRequest.setCurrent(control, model: device.model)
        _ = try perform(request, payload: LittleEndian.encode(value, size: control.size))
    }

    func get(_ control: CameraTerminalControl, _ code: UVCRequest.Code) throws -> Int {
        LittleEndian.decode(try perform(UVCRequest.get(code, control, model: device.model)))
    }
}
