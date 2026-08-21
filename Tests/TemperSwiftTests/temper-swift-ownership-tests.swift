import ArgumentParser
@testable import TemperSwift
@testable import TemperSwiftCommands
import Testing

@Suite("TemperSwift command ownership")
struct TemperSwiftOwnershipTests {
    @Test("Swift is the nested Temper command name")
    func canonicalRootCommand() {
        #expect(TemperSwiftCommands.configuration.commandName == "swift")
    }

    @Test("TemperSwift owns selection mutation parsing")
    func parsesSelectionMutation() throws {
        let command = try TemperSwiftCommands.parseAsRoot([
            "use", "--global-default", "6.4",
        ])
        #expect(command is Use)
    }

    @Test("TemperSwift owns active-selection reporting")
    func parsesSelectionReporting() throws {
        let command = try TemperSwiftCommands.parseAsRoot(["use", "--print-location"])
        #expect(command is Use)
    }

    @Test(
        "Toolchain lifecycle commands remain distinct root operations",
        arguments: [
            ["install", "6.4"],
            ["list"],
            ["update", "6.4"],
            ["uninstall", "6.4"],
            ["run", "swift", "--version"],
        ]
    )
    func lifecycleCommandsAreRootOperations(arguments: [String]) throws {
        let command = try TemperSwiftCommands.parseAsRoot(arguments)
        #expect(!(command is Use))
    }

    @Test("TemperSwift run preserves Swift package arguments")
    func runPreservesSwiftPackageArguments() throws {
        let parsed = try Run.extractProxyArguments(command: [
            "swift", "test", "--package-path", "C:\\workspace\\tool",
        ])
        #expect(parsed.command == [
            "swift", "test", "--package-path", "C:\\workspace\\tool",
        ])
        #expect(parsed.selector == nil)
    }
}
