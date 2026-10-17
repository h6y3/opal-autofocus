import Testing
import OpalUVC
@testable import OpalAutofocusCLI

private struct FakeDoctorEnvironment: DoctorEnvironment {
    var home = "/Users/a"
    var userID: UInt32 = 501
    var executablePath = "/usr/local/bin/opal-autofocus"
    var files: Set<String> = []
    var plists: [String: [String: Any]] = [:]
    var loaded: Set<String> = []
    var cameraList: Result<[CameraSnapshot], Boom> = .success([])
    var logs: [String: [String]] = [:]

    func fileExists(_ path: String) -> Bool { files.contains(path) }
    func plist(at path: String) -> [String: Any]? { plists[path] }
    func isLoaded(label: String) -> Bool { loaded.contains(label) }
    func cameras() throws -> [CameraSnapshot] {
        switch cameraList {
        case .success(let cameras): return cameras
        case .failure(let error): throw error
        }
    }
    func lastLines(of path: String, count: Int) -> [String]? {
        guard let lines = logs[path] else { return nil }
        return Array(lines.suffix(count))
    }
}

@Suite struct DoctorTests {
    private let home = "/Users/a"
    private let executablePath = "/usr/local/bin/opal-autofocus"
    private let goodLabel = "Opal C1 (serial 1944301031042E1800, location 0x01220000)"
    private let secondLabel = "Opal C1 (serial 1944301031042E9002, location 0x02e10000)"

    private func plistPath(_ label: String) -> String {
        "\(home)/Library/LaunchAgents/\(label).plist"
    }

    private func plistPath(_ label: String, in directory: String) -> String {
        "\(directory)/Library/LaunchAgents/\(label).plist"
    }

    private func camera(autofocus: Bool = true) -> CameraSnapshot {
        CameraSnapshot(
            model: "Opal C1",
            serial: "1944301031042E1800",
            location: "0x01220000",
            label: goodLabel,
            reading: .status(FocusStatus(autofocus: autofocus, position: 130, minimum: 0, maximum: 255, defaultPosition: 130)))
    }

    private var secondCamera: CameraSnapshot {
        CameraSnapshot(
            model: "Opal C1",
            serial: "1944301031042E9002",
            location: "0x02e10000",
            label: secondLabel,
            reading: .status(FocusStatus(autofocus: false, position: 10, minimum: 0, maximum: 255, defaultPosition: 130)))
    }

    /// Event agent installed, loaded and pointing at an existing program.
    private func agentSetupEnv() -> FakeDoctorEnvironment {
        var environment = FakeDoctorEnvironment()
        let plist = plistPath(Doctor.eventAgentLabel)
        environment.files = [plist, executablePath]
        environment.plists = [plist: ["ProgramArguments": [executablePath, "run", "--quiet-missing", "--launchd"]]]
        environment.loaded = [Doctor.eventAgentLabel]
        return environment
    }

    private func healthyEnv(composerInstalled: Bool = false) -> FakeDoctorEnvironment {
        var environment = agentSetupEnv()
        environment.cameraList = .success([camera()])
        if composerInstalled {
            environment.files.insert(Doctor.composerDaemonPath)
        }
        return environment
    }

    @Test func eventAgentOnlyIsOk() {
        let result = Doctor.run(agentSetupEnv())
        #expect(result.checks[0] == CheckLine(status: .ok, topic: "setup",
                                              message: "event-driven launchd agent loaded (com.opal-autofocus.agent)", fix: nil))
        #expect(result.checks[1].topic == "agent")
    }

    @Test func brewOnlyIsOk() {
        let result = Doctor.run(brewSetupEnv(Doctor.brewLabels[0]))
        #expect(result.checks[0] == CheckLine(status: .ok, topic: "setup",
                                              message: "Homebrew watcher loaded (\(Doctor.brewLabels[0]))", fix: nil))
        #expect(result.checks[1].topic == "agent")
    }

    @Test func shBrewLabelLoadedIsOk() {
        let result = Doctor.run(brewSetupEnv(Doctor.brewLabels[0]))
        #expect(result.checks[0] == CheckLine(status: .ok, topic: "setup",
                                              message: "Homebrew watcher loaded (sh.brew.opal-autofocus)", fix: nil))
        #expect(result.checks[1] == CheckLine(status: .ok, topic: "agent",
                                              message: "sh.brew.opal-autofocus runs \(executablePath)", fix: nil))
    }

    @Test func legacyMxclLabelStillRecognised() {
        let result = Doctor.run(brewSetupEnv(Doctor.brewLabels[1]))
        #expect(result.checks[0] == CheckLine(status: .ok, topic: "setup",
                                              message: "Homebrew watcher loaded (homebrew.mxcl.opal-autofocus)", fix: nil))
    }

    @Test func eventAgentPlusShBrewLoadedFails() {
        var environment = agentSetupEnv()
        let shLabel = Doctor.brewLabels[0]
        environment.files.insert(plistPath(shLabel))
        environment.plists[plistPath(shLabel)] = ["ProgramArguments": [executablePath, "watch"]]
        environment.loaded.insert(shLabel)
        let result = Doctor.run(environment)
        #expect(result.checks[0] == CheckLine(status: .fail, topic: "setup",
                                              message: "two setups are loaded; use one",
                                              fix: "brew services stop opal-autofocus"))
        #expect(result.failed)
    }

    private func brewSetupEnv(_ label: String) -> FakeDoctorEnvironment {
        var environment = FakeDoctorEnvironment()
        let plist = plistPath(label)
        environment.files = [plist, executablePath]
        environment.plists = [plist: ["ProgramArguments": [executablePath, "watch"]]]
        environment.loaded = [label]
        return environment
    }

    @Test func bothLoadedFails() {
        let eventPlist = plistPath(Doctor.eventAgentLabel)
        let brewPlist = plistPath(Doctor.brewLabels[0])
        var environment = FakeDoctorEnvironment()
        environment.files = [eventPlist, brewPlist, executablePath]
        environment.plists = [
            eventPlist: ["ProgramArguments": [executablePath, "run", "--quiet-missing", "--launchd"]],
            brewPlist: ["ProgramArguments": [executablePath, "watch"]]]
        environment.loaded = [Doctor.eventAgentLabel, Doctor.brewLabels[0]]
        let result = Doctor.run(environment)
        #expect(result.checks[0] == CheckLine(status: .fail, topic: "setup",
                                              message: "two setups are loaded; use one",
                                              fix: "brew services stop opal-autofocus"))
        #expect(result.checks[1].topic == "agent")
    }

    @Test func loadedPlusLeftoverPlistAddsNote() {
        let brewPlist = plistPath(Doctor.brewLabels[0])
        var environment = agentSetupEnv()
        environment.files.insert(brewPlist)
        environment.plists[brewPlist] = ["ProgramArguments": [executablePath, "watch"]]
        let result = Doctor.run(environment)
        #expect(result.checks[0] == CheckLine(status: .ok, topic: "setup",
                                              message: "event-driven launchd agent loaded (com.opal-autofocus.agent)", fix: nil))
        #expect(result.checks[1] == CheckLine(status: .note, topic: "setup",
                                              message: "leftover plist, not loaded: \(brewPlist)", fix: nil))
        #expect(result.checks[2].topic == "agent")
    }

    @Test func installedNotLoadedSuggestsBootstrap() {
        let plist = plistPath(Doctor.eventAgentLabel)
        var environment = FakeDoctorEnvironment()
        environment.files = [plist]
        environment.plists = [plist: ["ProgramArguments": [executablePath, "run", "--quiet-missing", "--launchd"]]]
        let result = Doctor.run(environment)
        #expect(result.checks[0] == CheckLine(status: .fail, topic: "setup",
                                              message: "installed but not loaded",
                                              fix: "launchctl bootstrap gui/501 \"\(plist)\""))
    }

    @Test func bootstrapFixQuotesPathWithSpace() {
        let janeHome = "/Users/Jane Doe"
        let plist = plistPath(Doctor.eventAgentLabel, in: janeHome)
        var environment = FakeDoctorEnvironment(home: janeHome)
        environment.files = [plist]
        let result = Doctor.run(environment)
        #expect(result.checks[0].fix == "launchctl bootstrap gui/501 \"\(plist)\"")
    }

    @Test func brewInstalledNotLoadedSuggestsBrewStart() {
        let plist = plistPath(Doctor.brewLabels[0])
        var environment = FakeDoctorEnvironment()
        environment.files = [plist]
        environment.plists = [plist: ["ProgramArguments": [executablePath, "watch"]]]
        let result = Doctor.run(environment)
        #expect(result.checks[0] == CheckLine(status: .fail, topic: "setup",
                                              message: "installed but not loaded",
                                              fix: "brew services start opal-autofocus"))
    }

    @Test func nothingInstalledFails() {
        let result = Doctor.run(FakeDoctorEnvironment())
        #expect(result.checks[0] == CheckLine(status: .fail, topic: "setup",
                                              message: "nothing will re-enable autofocus after a replug",
                                              fix: "brew services start opal-autofocus, or make install from a source checkout"))
    }

    @Test func staleProgramPathFails() {
        let plist = plistPath(Doctor.eventAgentLabel)
        var environment = FakeDoctorEnvironment()
        environment.files = [plist]
        environment.plists = [plist: ["ProgramArguments": ["/opt/homebrew/bin/opal-autofocus", "run", "--quiet-missing", "--launchd"]]]
        let result = Doctor.run(environment)
        #expect(result.checks[1] == CheckLine(status: .fail, topic: "agent",
                                              message: "com.opal-autofocus.agent runs /opt/homebrew/bin/opal-autofocus, which does not exist",
                                              fix: "reinstall with the method that created \(plist)"))
    }

    @Test func unreadablePlistFails() {
        let plist = plistPath(Doctor.eventAgentLabel)
        var environment = FakeDoctorEnvironment()
        environment.files = [plist]
        let result = Doctor.run(environment)
        #expect(result.checks[1] == CheckLine(status: .fail, topic: "agent",
                                              message: "cannot read \(plist)",
                                              fix: "reinstall with the method that created \(plist)"))
    }

    @Test func plistWithoutProgramKeyFails() {
        let plist = plistPath(Doctor.eventAgentLabel)
        var environment = FakeDoctorEnvironment()
        environment.files = [plist]
        environment.plists = [plist: ["Label": Doctor.eventAgentLabel]]
        let result = Doctor.run(environment)
        #expect(result.checks[1] == CheckLine(status: .fail, topic: "agent",
                                              message: "cannot read \(plist)",
                                              fix: "reinstall with the method that created \(plist)"))
    }

    @Test func programKeyFallback() {
        let plist = plistPath(Doctor.eventAgentLabel)
        var environment = FakeDoctorEnvironment()
        environment.files = [plist, executablePath]
        environment.plists = [plist: ["Program": executablePath]]
        let result = Doctor.run(environment)
        #expect(result.checks[1] == CheckLine(status: .ok, topic: "agent",
                                              message: "com.opal-autofocus.agent runs \(executablePath)", fix: nil))
    }

    @Test func composerDaemonIsNoteNotFailure() {
        let result = Doctor.run(healthyEnv(composerInstalled: true))
        #expect(result.checks[2] == CheckLine(status: .note, topic: "composer",
                                              message: "Opal Composer's helper daemon is installed and can turn autofocus on by itself, "
                                                  + "so autofocus may work even when this tool is not running",
                                              fix: nil))
        #expect(!result.failed)
    }

    @Test func noComposerNoLine() {
        let result = Doctor.run(agentSetupEnv())
        #expect(!result.checks.contains { $0.topic == "composer" })
    }

    @Test func noCameraFailsWithHubHint() {
        let result = Doctor.run(FakeDoctorEnvironment())
        #expect(result.checks[1] == CheckLine(status: .fail, topic: "camera",
                                              message: "no Opal camera found",
                                              fix: "plug the camera in; if it is behind a hub, plug it into the hub or Mac directly to rule the hub out"))
    }

    @Test func cameraListErrorFails() {
        var environment = FakeDoctorEnvironment()
        environment.cameraList = .failure(Boom())
        let result = Doctor.run(environment)
        #expect(result.checks[1] == CheckLine(status: .fail, topic: "camera",
                                              message: "cannot list cameras: \(Boom.message)", fix: nil))
    }

    @Test func autofocusOffFails() {
        var environment = FakeDoctorEnvironment()
        environment.cameraList = .success([camera(autofocus: false)])
        let result = Doctor.run(environment)
        #expect(result.checks[1] == CheckLine(status: .ok, topic: "camera", message: goodLabel, fix: nil))
        #expect(result.checks[2] == CheckLine(status: .fail, topic: "controls",
                                              message: "\(goodLabel): autofocus is off",
                                              fix: "opal-autofocus enable; if it is off again after every replug, check the setup line above"))
    }

    @Test func failedControlsReadingFails() {
        var environment = FakeDoctorEnvironment()
        environment.cameraList = .success([CameraSnapshot(
            model: "Opal C1", serial: "1944301031042E1800", location: "0x01220000",
            label: goodLabel, reading: .failed(Boom.message))])
        let result = Doctor.run(environment)
        #expect(result.checks[1] == CheckLine(status: .ok, topic: "camera", message: goodLabel, fix: nil))
        #expect(result.checks[2] == CheckLine(status: .fail, topic: "controls",
                                              message: "\(goodLabel): \(Boom.message)", fix: nil))
        #expect(result.failed)
    }

    @Test func twoCamerasOneOff() {
        var environment = FakeDoctorEnvironment()
        environment.cameraList = .success([camera(), secondCamera])
        let result = Doctor.run(environment)
        #expect(result.checks[2] == CheckLine(status: .ok, topic: "controls",
                                              message: "\(goodLabel): autofocus: on, focus position: 130 (min 0, max 255, default 130)", fix: nil))
        #expect(result.checks[4] == CheckLine(status: .fail, topic: "controls",
                                              message: "\(secondLabel): autofocus is off",
                                              fix: "opal-autofocus enable; if it is off again after every replug, check the setup line above"))
        #expect(result.failed)
    }

    @Test func allGoodIsNotFailed() {
        let result = Doctor.run(healthyEnv())
        #expect(!result.failed)
        #expect(result.checks[1] == CheckLine(status: .ok, topic: "agent",
                                              message: "com.opal-autofocus.agent runs \(executablePath)", fix: nil))
        #expect(result.checks[2] == CheckLine(status: .ok, topic: "camera", message: goodLabel, fix: nil))
        #expect(result.checks[3] == CheckLine(status: .ok, topic: "controls",
                                              message: "\(goodLabel): autofocus: on, focus position: 130 (min 0, max 255, default 130)", fix: nil))
    }

    @Test func logExcerptFromStandardOutPath() {
        let plist = plistPath(Doctor.eventAgentLabel)
        var environment = agentSetupEnv()
        environment.plists[plist]?["StandardOutPath"] = "/tmp/x.log"
        environment.logs = ["/tmp/x.log": ["a", "b"]]
        let result = Doctor.run(environment)
        #expect(result.logs == [LogExcerpt(path: "/tmp/x.log", lines: ["a", "b"])])
    }

    @Test func missingLogFileIsSkipped() {
        let plist = plistPath(Doctor.eventAgentLabel)
        var environment = agentSetupEnv()
        environment.plists[plist]?["StandardOutPath"] = "/tmp/x.log"
        let result = Doctor.run(environment)
        #expect(result.logs.isEmpty)
    }

    @Test func renderMatchesSpecLayout() {
        let plist = plistPath(Doctor.eventAgentLabel)
        var environment = agentSetupEnv()
        environment.plists[plist]?["StandardOutPath"] = "/tmp/x.log"
        environment.logs = ["/tmp/x.log": ["line one", "line two"]]
        let expected = """
opal-autofocus \(OpalUVC.version) at \(executablePath)

ok    setup: event-driven launchd agent loaded (com.opal-autofocus.agent)
ok    agent: com.opal-autofocus.agent runs \(executablePath)
FAIL  camera: no Opal camera found
      fix: plug the camera in; if it is behind a hub, plug it into the hub or Mac directly to rule the hub out

recent log (/tmp/x.log):
  line one
  line two

"""
        #expect(Doctor.run(environment).render() == expected)
    }
}
