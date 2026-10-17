import ArgumentParser
import OpalUVC

@main
struct OpalAutofocus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "opal-autofocus",
        abstract: "Keep the Opal C1 webcam's autofocus enabled without Opal Composer.",
        version: OpalUVC.version,
        subcommands: [Run.self, Watch.self, Status.self, DoctorCommand.self, Enable.self, Disable.self, Focus.self]
    )
}
