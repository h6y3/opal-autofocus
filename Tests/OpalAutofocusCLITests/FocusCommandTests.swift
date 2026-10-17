import Testing
import ArgumentParser
@testable import OpalAutofocusCLI

@Suite struct FocusCommandTests {
    @Test func focusAcceptsRange() throws {
        #expect(try Focus.parse(["0"]).position == 0)
        #expect(try Focus.parse(["255"]).position == 255)
        #expect(try Focus.parse(["65535"]).position == 65535)
        #expect(try Focus.parse(["300"]).position == 300)
    }

    @Test(arguments: [["65536"], ["-1"], ["abc"], []])
    func focusRejectsBadInput(args: [String]) {
        #expect(throws: (any Error).self) { try Focus.parse(args) }
    }

    @Test func validationErrorExitCodeIsUsage() {
        do {
            _ = try Focus.parse(["70000"])
            Issue.record("expected error")
        } catch {
            #expect(Focus.exitCode(for: error) == ExitCode(64))
        }
    }

    @Test func subcommandsRegistered() {
        let names = OpalAutofocus.configuration.subcommands.map { $0.configuration.commandName ?? "" }
        #expect(Set(names) == ["run", "watch", "status", "doctor", "enable", "disable", "focus"])
    }
}
