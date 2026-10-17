import Foundation
import OpalUVC

enum CheckStatus: Equatable {
    case ok, note, fail   // rendered "ok", "note", "FAIL"
}

struct CheckLine: Equatable {
    let status: CheckStatus
    let topic: String
    let message: String
    let fix: String?
}

struct LogExcerpt: Equatable {
    let path: String
    let lines: [String]
}

struct DoctorReport: Equatable {
    let header: String
    let checks: [CheckLine]
    let logs: [LogExcerpt]

    var failed: Bool { checks.contains { $0.status == .fail } }

    func render() -> String {
        var lines = [header, ""]
        for check in checks {
            lines.append(check.status.statusWord.padding(toLength: 6, withPad: " ", startingAt: 0)
                + "\(check.topic): \(check.message)")
            if let fix = check.fix {
                lines.append("      fix: \(fix)")
            }
        }
        for excerpt in logs {
            lines.append("")
            lines.append("recent log (\(excerpt.path)):")
            lines.append(contentsOf: excerpt.lines.map { "  \($0)" })
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

enum Doctor {
    static let eventAgentLabel = "com.opal-autofocus.agent"
    static let brewLabels = ["sh.brew.opal-autofocus", "homebrew.mxcl.opal-autofocus"]
    static let composerDaemonPath = "/Library/LaunchDaemons/com.opalcamera.Opal.v2.cameraExtensionShim.plist"

    static func run(_ env: DoctorEnvironment) -> DoctorReport {
        var checks: [CheckLine] = []
        appendSetupChecks(env, to: &checks)
        appendAgentChecks(env, to: &checks)
        appendComposerCheck(env, to: &checks)
        appendCameraChecks(env, to: &checks)
        return DoctorReport(
            header: "opal-autofocus \(OpalUVC.version) at \(env.executablePath)",
            checks: checks,
            logs: logExcerpts(env))
    }

    private static func appendSetupChecks(_ env: DoctorEnvironment, to checks: inout [CheckLine]) {
        let eventPlist = plistPath(env, eventAgentLabel)
        let eventLoaded = env.isLoaded(label: eventAgentLabel)
        let brewLoadedLabel = brewLabels.first { env.isLoaded(label: $0) }

        if eventLoaded && brewLoadedLabel != nil {
            checks.append(CheckLine(status: .fail, topic: "setup",
                                    message: "two setups are loaded; use one",
                                    fix: "brew services stop opal-autofocus"))
            return
        }
        if eventLoaded || brewLoadedLabel != nil {
            let message = eventLoaded
                ? "event-driven launchd agent loaded (\(eventAgentLabel))"
                : "Homebrew watcher loaded (\(brewLoadedLabel!))"
            checks.append(CheckLine(status: .ok, topic: "setup", message: message, fix: nil))
            if eventLoaded {
                for label in brewLabels {
                    let path = plistPath(env, label)
                    if env.fileExists(path) {
                        checks.append(CheckLine(status: .note, topic: "setup",
                                                message: "leftover plist, not loaded: \(path)", fix: nil))
                    }
                }
            } else if env.fileExists(eventPlist) {
                checks.append(CheckLine(status: .note, topic: "setup",
                                        message: "leftover plist, not loaded: \(eventPlist)", fix: nil))
            }
            return
        }
        let eventInstalled = env.fileExists(eventPlist)
        let brewInstalled = brewLabels.contains { env.fileExists(plistPath(env, $0)) }
        if eventInstalled || brewInstalled {
            let fix = eventInstalled
                ? "launchctl bootstrap gui/\(env.userID) \"\(eventPlist)\""
                : "brew services start opal-autofocus"
            checks.append(CheckLine(status: .fail, topic: "setup", message: "installed but not loaded", fix: fix))
            return
        }
        checks.append(CheckLine(status: .fail, topic: "setup",
                                message: "nothing will re-enable autofocus after a replug",
                                fix: "brew services start opal-autofocus, or make install from a source checkout"))
    }

    private static func appendAgentChecks(_ env: DoctorEnvironment, to checks: inout [CheckLine]) {
        for label in [eventAgentLabel] + brewLabels {
            let path = plistPath(env, label)
            guard env.fileExists(path) else { continue }
            let fix = "reinstall with the method that created \(path)"
            guard let plist = env.plist(at: path), let program = program(of: plist) else {
                checks.append(CheckLine(status: .fail, topic: "agent", message: "cannot read \(path)", fix: fix))
                continue
            }
            if env.fileExists(program) {
                checks.append(CheckLine(status: .ok, topic: "agent", message: "\(label) runs \(program)", fix: nil))
            } else {
                checks.append(CheckLine(status: .fail, topic: "agent",
                                        message: "\(label) runs \(program), which does not exist", fix: fix))
            }
        }
    }

    private static func program(of plist: [String: Any]) -> String? {
        if let arguments = plist["ProgramArguments"] as? [String], let first = arguments.first, !first.isEmpty {
            return first
        }
        return plist["Program"] as? String
    }

    private static func appendComposerCheck(_ env: DoctorEnvironment, to checks: inout [CheckLine]) {
        guard env.fileExists(composerDaemonPath) else { return }
        checks.append(CheckLine(
            status: .note,
            topic: "composer",
            message: "Opal Composer's helper daemon is installed and can turn autofocus on by itself, "
                + "so autofocus may work even when this tool is not running",
            fix: nil))
    }

    private static func appendCameraChecks(_ env: DoctorEnvironment, to checks: inout [CheckLine]) {
        let cameras: [CameraSnapshot]
        do {
            cameras = try env.cameras()
        } catch {
            checks.append(CheckLine(status: .fail, topic: "camera", message: "cannot list cameras: \(error)", fix: nil))
            return
        }
        if cameras.isEmpty {
            checks.append(CheckLine(status: .fail, topic: "camera", message: "no Opal camera found",
                                    fix: "plug the camera in; if it is behind a hub, plug it into the hub or Mac directly to rule the hub out"))
            return
        }
        for camera in cameras {
            checks.append(CheckLine(status: .ok, topic: "camera", message: camera.label, fix: nil))
            appendControlCheck(camera, to: &checks)
        }
    }

    private static func appendControlCheck(_ camera: CameraSnapshot, to checks: inout [CheckLine]) {
        switch camera.reading {
        case .failed(let message):
            checks.append(CheckLine(status: .fail, topic: "controls", message: "\(camera.label): \(message)", fix: nil))
        case .status(let status):
            if status.autofocus {
                checks.append(CheckLine(status: .ok, topic: "controls", message: "\(camera.label): \(status.summary)", fix: nil))
            } else {
                checks.append(CheckLine(status: .fail, topic: "controls",
                                        message: "\(camera.label): autofocus is off",
                                        fix: "opal-autofocus enable; if it is off again after every replug, check the setup line above"))
            }
        }
    }

    private static func logExcerpts(_ env: DoctorEnvironment) -> [LogExcerpt] {
        var seenPaths = Set<String>()
        var excerpts: [LogExcerpt] = []
        for label in [eventAgentLabel] + brewLabels {
            let path = plistPath(env, label)
            guard env.fileExists(path), let plist = env.plist(at: path),
                  let logPath = plist["StandardOutPath"] as? String,
                  seenPaths.insert(logPath).inserted else { continue }
            if let lines = env.lastLines(of: logPath, count: 5) {
                excerpts.append(LogExcerpt(path: logPath, lines: lines))
            }
        }
        return excerpts
    }

    private static func plistPath(_ env: DoctorEnvironment, _ label: String) -> String {
        "\(env.home)/Library/LaunchAgents/\(label).plist"
    }
}

private extension CheckStatus {
    var statusWord: String {
        switch self {
        case .ok: return "ok"
        case .note: return "note"
        case .fail: return "FAIL"
        }
    }
}
