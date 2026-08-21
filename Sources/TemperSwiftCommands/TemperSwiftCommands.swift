import ArgumentParser
import Foundation
import TemperSwift
import TemperSwiftCore
import SystemPackage

typealias fs = TemperSwiftCore.FileSystem

extension FilePath: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(argument)
    }

    public static var defaultCompletionKind: CompletionKind {
        CompletionKind.file()
    }
}

public struct GlobalOptions: ParsableArguments {
    @Flag(name: [.customShort("y"), .long], help: "Disable confirmation prompts by assuming 'yes'")
    var assumeYes: Bool = false

    @Flag(help: "Enable verbose reporting from TemperSwift")
    var verbose: Bool = false

    public init() {}
}

public struct TemperSwiftCommands: TemperSwiftCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
        commandName: TemperSwiftCommandInvocation.commandName ?? "swift",
        abstract: "Install, select, and manage Swift toolchains.",

        version: String(describing: TemperSwiftCore.version),

        subcommands: [
            Install.self,
            ListAvailable.self,
            Use.self,
            Uninstall.self,
            List.self,
            Update.self,
            Init.self,
            SelfUpdate.self,
            Run.self,
            SelfUninstall.self,
            Link.self,
            Unlink.self,
        ]
        )
    }

    public init() {}

    public mutating func run(_: TemperSwiftCoreContext) async throws {}
}

/// Programmatic entry point for hosts that compose the TemperSwift command family.
public enum TemperSwiftCommandRunner {
    public static func run(
        arguments: [String],
        commandName: String? = nil,
        proxyExecutablePath: String? = nil,
        includesSystemToolchains: Bool = true
    ) async throws {
        try await TemperSwiftCommandInvocation.$commandName.withValue(commandName) {
            try await TemperSwiftCommandInvocation.$proxyExecutablePath.withValue(proxyExecutablePath) {
                try await TemperSwiftCommandInvocation.$includesSystemToolchains.withValue(includesSystemToolchains) {
                    do {
                        var command = try TemperSwiftCommands.parseAsRoot(arguments)
                        if var asyncCommand = command as? any AsyncParsableCommand {
                            try await asyncCommand.run()
                        } else {
                            try command.run()
                        }
                    } catch {
                        guard TemperSwiftCommands.exitCode(for: error).isSuccess else { throw error }
                        Swift.print(TemperSwiftCommandInvocation.hosted(TemperSwiftCommands.fullMessage(for: error)))
                    }
                }
            }
        }
    }
}

enum TemperSwiftCommandInvocation {
    @TaskLocal static var commandName: String?
    @TaskLocal static var proxyExecutablePath: String?
    @TaskLocal static var includesSystemToolchains = true

    static func proxyExecutable(_ ctx: TemperSwiftCoreContext) async -> FilePath? {
        if let proxyExecutablePath { return FilePath(proxyExecutablePath) }
        return try? await TemperSwift.currentPlatform.findTemperSwiftBin(ctx)
    }

    static func hosted(_ message: String) -> String {
        guard let commandName else { return message }
        return message
            .replacingOccurrences(of: "TemperSwift", with: commandName)
            .replacingOccurrences(of: "swiftly", with: commandName)
    }

    static var currentlyUnlinkedMessage: String {
        guard let commandName else { return Messages.currentlyUnlinked }
        return """
        \(commandName) is not linked to the active Swift toolchain. Select an installed
        Swift version to establish the executable proxy links:

            $ \(commandName) use <version>


        """
    }
}

public protocol TemperSwiftCommand: AsyncParsableCommand {
    mutating func run(_ ctx: TemperSwiftCoreContext) async throws
}

extension Data {
    func append(to file: FilePath) throws {
        if let fileHandle = FileHandle(forWritingAtPath: file.string) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: file, options: .atomic)
        }
    }
}

extension TemperSwiftCommand {
    @discardableResult
    public mutating func validateTemperSwift(_ ctx: TemperSwiftCoreContext) async throws -> () -> Void {
        for requiredDir in TemperSwift.requiredDirectories(ctx) {
            guard try await fs.exists(atPath: requiredDir) else {
                do {
                    try await fs.mkdir(.parents, atPath: requiredDir)
                } catch {
                    throw TemperSwiftError(message: "Failed to create required directory \"\(requiredDir)\": \(error)")
                }
                continue
            }
        }

        // Verify that the configuration exists and can be loaded
        _ = try await Config.load(ctx)

        let shouldUpdateTemperSwift: Bool
        if let swiftlyRelease = try? await ctx.httpClient.getCurrentTemperSwiftRelease() {
            shouldUpdateTemperSwift = try swiftlyRelease.swiftlyVersion > TemperSwiftCore.version
        } else {
            shouldUpdateTemperSwift = false
        }

        return {
            if shouldUpdateTemperSwift {
                let updateMessage = """
                -----------------------------
                A new release of swiftly is available.
                Please run `swiftly self-update` to update.
                -----------------------------\n
                """

                if let data = updateMessage.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        }
    }

    public static func handlePathChange(_ ctx: TemperSwiftCoreContext) async throws {
        let shell =
            if let s = ProcessInfo.processInfo.environment["SHELL"]
        {
            s
        } else {
            try await TemperSwift.currentPlatform.getShell()
        }

        // Fish doesn't cache its path, so this instruction is not necessary.
        if !shell.hasSuffix("fish") {
            await ctx.message(
                """
                NOTE: TemperSwift has updated some elements in your path and your shell may not yet be
                aware of the changes. You can update your shell's environment by running

                hash -r

                or restarting your shell.

                """)
        }
    }
}
