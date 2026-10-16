import ArgumentParser
import OpalUVC

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Enable autofocus on any attached Opal, waiting briefly for it to appear, then exit.",
        discussion: "This is what the launchd agent runs when the camera is attached.")

    @Option(help: "Seconds to keep looking for the camera before giving up.")
    var timeout: Double = 5

    @Option(help: "Seconds to wait after finding the camera before sending the control.")
    var settle: Double = 0.5

    @Flag(help: "Exit 0 instead of 1 when no camera appears (for launchd).")
    var quietMissing = false

    @Flag(help: "Consume the pending launchd IOKit event first (set by the launchd agent).")
    var launchd = false

    func validate() throws {
        guard timeout >= 0 else { throw ValidationError("timeout must be 0 or more seconds") }
        guard settle >= 0 else { throw ValidationError("settle must be 0 or more seconds") }
    }

    func run() throws {
        if launchd { _ = LaunchEventDrain(timeout: 1).wait() }
        let loop = KickLoop(timeout: timeout, settle: settle, find: { try OpalDevice.find() },
                            log: { Output.line(Output.stamp($0)) })
        let outcome = loop.run()
        switch outcome {
        case .kicked:
            break
        case .noDevice:
            if !quietMissing { Output.error(Output.stamp("no Opal camera appeared within \(timeout) s")) }
        case .failed(let message, let kicked):
            Output.error(Output.stamp("\(message) (\(kicked) other device(s) succeeded)"))
        }
        let code = KickLoop.exitCode(for: outcome, quietMissing: quietMissing)
        if code != ExitStatus.ok { throw ExitCode(code) }
    }
}
