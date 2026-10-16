import ArgumentParser
import Foundation
import OpalUVC

struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Stay running and enable autofocus each time an Opal is attached.",
        discussion: "Use this when launchd IOKit events are not available (for example under brew services).")

    @Option(help: "Seconds to wait after attach before sending the control, so enumeration can settle.")
    var settle: Double = 0.5

    func validate() throws {
        guard settle >= 0 else { throw ValidationError("settle must be 0 or more seconds") }
    }

    func run() throws {
        let settle = self.settle
        let watcher = DeviceWatcher { device in
            Output.line("\(Output.timestamp()) attached: \(device.label)")
            Thread.sleep(forTimeInterval: settle)
            do {
                try device.open().enableAutofocus()
                Output.line("\(Output.timestamp()) enabled autofocus on \(device.label)")
            } catch {
                Output.error("\(Output.timestamp()) \(device.label): \(error)")
            }
        }
        try watcher.start()
        Output.line("\(Output.timestamp()) watching for \(KnownModels.all.map(\.name).joined(separator: ", "))")
        withExtendedLifetime(watcher) { dispatchMain() }
    }
}
