import ArgumentParser
import OpalUVC

/// Applies one action to every attached camera and maps the result to an exit code.
func applyToAllDevices(_ what: String, _ action: (Connection) throws -> Void) throws {
    let devices = try OpalDevice.find()
    guard !devices.isEmpty else {
        Output.error("no Opal camera attached")
        throw ExitCode(ExitStatus.noDevice)
    }
    var failed = false
    for device in devices {
        do {
            try action(try device.open())
            Output.line("\(what) on \(device.label)")
        } catch {
            Output.error("\(device.label): \(error)")
            failed = true
        }
    }
    if failed { throw ExitCode(ExitStatus.requestFailed) }
}

struct Enable: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "enable", abstract: "Turn continuous autofocus on.")
    func run() throws { try applyToAllDevices("enabled autofocus") { try $0.enableAutofocus() } }
}

struct Disable: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable", abstract: "Turn autofocus off (lens stays where it is).")
    func run() throws { try applyToAllDevices("disabled autofocus") { try $0.disableAutofocus() } }
}

struct Focus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Set a fixed focus position (lower is nearer; run status to see the camera's range).")

    @Argument(help: "Lens position within the camera's range (see status).")
    var position: Int

    func validate() throws {
        let max = CameraTerminalControl.focusAbsolute.maxEncodableValue
        guard (0...max).contains(position) else {
            throw ValidationError("position must be between 0 and \(max)")
        }
    }

    func run() throws {
        let code = applyFocus(position, to: try OpalDevice.find(), log: Output.line, fail: Output.error)
        if code != ExitStatus.ok { throw ExitCode(code) }
    }
}
