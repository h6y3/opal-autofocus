import ArgumentParser

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check the install, the camera and known interference, and print fixes. Changes nothing.",
        discussion: "Exits 0 when every check passes and 1 when any check failed.")

    func run() throws {
        let report = Doctor.run(LiveDoctorEnvironment())
        print(report.render(), terminator: "")
        if report.failed { throw ExitCode(1) }
    }
}
