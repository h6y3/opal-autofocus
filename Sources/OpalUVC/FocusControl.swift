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

extension Connection {
    /// Turns continuous autofocus on. This is the write Opal Composer sends.
    public func enableAutofocus() throws {
        try set(.focusAuto, value: 1)
    }

    /// Parks the lens at its current position.
    public func disableAutofocus() throws {
        try set(.focusAuto, value: 0)
    }

    /// Manual focus. 0 is nearest, 255 is farthest on the Opal C1.
    public func setFocus(_ position: UInt8) throws {
        try set(.focusAuto, value: 0)
        try set(.focusAbsolute, value: Int(position))
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
