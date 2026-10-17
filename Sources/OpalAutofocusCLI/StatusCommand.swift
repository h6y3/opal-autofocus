import ArgumentParser
import OpalUVC

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status", abstract: "Show attached cameras and their focus controls.")

    @Flag(help: "Print JSON (see README for the format).")
    var json = false

    func run() throws {
        let devices = try OpalDevice.find()
        if json { try renderJSON(devices) } else { try renderText(devices) }
    }

    private func renderJSON(_ devices: [OpalDevice]) throws {
        let snapshots = devices.map(CameraSnapshot.take)
        Output.line(StatusJSON.render(snapshots))
        var failed = false
        for snapshot in snapshots {
            if case .failed(let message) = snapshot.reading {
                Output.error("\(snapshot.label): \(message)")
                failed = true
            }
        }
        if snapshots.isEmpty { throw ExitCode(ExitStatus.noDevice) }
        if failed { throw ExitCode(ExitStatus.requestFailed) }
    }

    private func renderText(_ devices: [OpalDevice]) throws {
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
