import ArgumentParser
import Foundation
import Subprocess
import TemperSwift
import TemperSwiftCore

public enum TemperSwiftProxy {
    public static func main(
        commandName: String = "temper-swift",
        includesSystemToolchains: Bool = true
    ) async throws {
        try await TemperSwiftCommandInvocation.$commandName.withValue(commandName) {
            try await TemperSwiftCommandInvocation.$includesSystemToolchains.withValue(includesSystemToolchains) {
                try await run()
            }
        }
    }

    private static func run() async throws {
        let ctx = TemperSwiftCoreContext()

        do {
            let zero = CommandLine.arguments[0]
            guard let binName = zero
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/")
                .last
                .map(String.init)
            else {
                fatalError("Could not determine the binary name for proxying")
            }

            let normalizedBinName = binName.lowercased()
            guard !["temper-swift", "temper-swift.exe"].contains(normalizedBinName) else {
                // Treat this as the standalone TemperSwift command, bootstrapping its
                // installation if necessary.
                let configResult: Result<Config, any Error>
                do {
                    configResult = Result<Config, any Error>.success(try await Config.load(ctx))
                } catch {
                    configResult = Result<Config, any Error>.failure(error)
                }

                switch configResult {
                case .success:
                    await TemperSwiftCommands.main()
                    return
                case let .failure(err):
                    guard CommandLine.arguments.count > 0 else { fatalError("argv is not set") }

                    if CommandLine.arguments.count == 1 {
                        // The user ran TemperSwift with no extra arguments in an uninstalled environment, so bootstrap init.
                        //  a simple init.
                        try await Init.execute(ctx, assumeYes: false, noModifyProfile: false, overwrite: false, platform: nil, verbose: false, skipInstall: false, quietShellFollowup: false)
                        return
                    } else if CommandLine.arguments.count >= 2 && ["init", "--generate-completion-script"].contains(CommandLine.arguments[1]) {
                        // Let the user run the init command or completion script generation with arguments, if any.
                        await TemperSwiftCommands.main()
                        return
                    } else if CommandLine.arguments.count == 2 && ["--help", "--experimental-dump-help"].contains(CommandLine.arguments[1]) {
                        // Just print help information.
                        await TemperSwiftCommands.main()
                        return
                    } else {
                        // This will throw if the configuration couldn't be loaded and give the user an actionable message.
                        throw err
                    }
                }
            }

            var config = try await Config.load(ctx)

            let (toolchain, result) = try await selectToolchain(ctx, config: &config)

            // Abort on any errors relating to swift version files
            if case let .swiftVersionFile(_, _, error) = result, let error = error {
                throw error
            }

            guard let toolchain = toolchain else {
                throw TemperSwiftError(message: "No installed Swift toolchain is selected by a .swift-version file or the global default. Use `temper swift use <toolchain version>`, or install and select one with `temper swift install --use <toolchain version>`.")
            }

            // Prevent circularities with a memento environment variable
            let processEnvironment = ProcessInfo.processInfo.environment
            guard processEnvironment["TEMPER_SWIFT_PROXY_IN_PROGRESS"] == nil,
                  processEnvironment["SWIFTLY_PROXY_IN_PROGRESS"] == nil
            else {
                throw TemperSwiftError(message: "Circular TemperSwift proxy invocation")
            }

            let env = try await TemperSwift.currentPlatform.proxyEnvironment(ctx, env: .inherit, toolchain: toolchain)

            let cmdConfig = Configuration(
                executable: .name(binName),
                arguments: Arguments(Array(CommandLine.arguments[1...])),
                environment: env.updating(["TEMPER_SWIFT_PROXY_IN_PROGRESS": "1"])
            )

            let cmdResult = try await Subprocess.run(
                cmdConfig,
                input: .currentStandardInput,
                output: .currentStandardOutput,
                error: .currentStandardError
            )

            if !cmdResult.terminationStatus.isSuccess {
                throw RunProgramError(terminationStatus: cmdResult.terminationStatus, config: cmdConfig)
            }
        } catch let terminated as RunProgramError {
            switch terminated.terminationStatus {
            case let .exited(code):
                exit(Int32(truncatingIfNeeded: code))
#if !os(Windows)
            case .signaled:
                exit(1)
#endif
            }
        } catch let error as TemperSwiftError {
            await ctx.message(error.message)
            exit(1)
        } catch {
            await ctx.message("\(error)")
            exit(1)
        }
    }
}
