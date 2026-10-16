import Foundation

enum ExitStatus {
    static let ok: Int32 = 0
    static let noDevice: Int32 = 1
    static let requestFailed: Int32 = 2
}

enum Output {
    static func line(_ message: String) {
        print(message)
        fflush(stdout)
    }

    static func error(_ message: String) {
        FileHandle.standardError.write(Data(("opal-autofocus: " + message + "\n").utf8))
    }

    static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}
