import ArgumentParser
import OpalUVC

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status", abstract: "Show attached cameras and their focus controls.")

    func run() throws {
        let devices = try OpalDevice.find()
        guard !devices.isEmpty else {
            Output.line("no Opal camera attached")
            throw ExitCode(ExitStatus.noDevice)
        }
        var failed = false
        for device in devices {
            Output.line(device.label)
            do {
                Output.line("  " + (try device.open().focusStatus().summary))
            } catch {
                Output.error("\(device.label): \(error)")
                failed = true
            }
        }
        if failed { throw ExitCode(ExitStatus.requestFailed) }
    }
}
