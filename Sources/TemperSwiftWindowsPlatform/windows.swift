import Foundation
import Subprocess
import TemperSwiftCore
import SystemPackage

typealias fs = TemperSwiftCore.FileSystem

/// Native Windows implementation for Temper's TemperSwift-derived toolchain core.
///
/// Official Swift installers place one coherent version across three sibling
/// directories: `Toolchains`, `Runtimes`, and `Platforms`. Temper treats that
/// triple as the selectable unit.
public struct Windows: Platform {
    public init() {}

    public var defaultTemperSwiftHomeDir: FilePath {
        FilePath(localAppData) / "Temper"
    }

    public func swiftlyBinDir(_ ctx: TemperSwiftCoreContext) -> FilePath {
        ctx.mockedHomeDir.map { $0 / "bin" }
            ?? ProcessInfo.processInfo.environment["SWIFTLY_BIN_DIR"].map { FilePath($0) }
            ?? defaultTemperSwiftHomeDir / "bin"
    }

    public func swiftlyToolchainsDir(_ ctx: TemperSwiftCoreContext) -> FilePath {
        installRoot(ctx) / "Toolchains"
    }

    public var toolchainFileExtension: String { "exe" }

    public func verifyTemperSwiftSystemPrerequisites() async throws {
        guard ProcessInfo.processInfo.environment["LOCALAPPDATA"] != nil else {
            throw TemperSwiftError(message: "LOCALAPPDATA is required to manage Swift on Windows.")
        }
    }

    public func verifySystemPrerequisitesForInstall(
        _: TemperSwiftCoreContext,
        platformName _: String,
        version _: ToolchainVersion,
        requireSignatureValidation _: Bool
    ) async throws -> String? {
        nil
    }

    public func install(
        _: TemperSwiftCoreContext,
        from installer: FilePath,
        version _: ToolchainVersion,
        verbose _: Bool
    ) async throws {
        guard try await fs.exists(atPath: installer) else {
            throw TemperSwiftError(message: "\(installer) does not exist")
        }
        let configuration = Configuration(
            executable: .path(installer),
            arguments: ["/quiet", "/norestart"]
        )
        let result = try await Subprocess.run(
            configuration,
            output: .currentStandardOutput,
            error: .currentStandardError
        )
        guard result.terminationStatus.isSuccess else {
            throw RunProgramError(terminationStatus: result.terminationStatus, config: configuration)
        }
    }

    public func extractTemperSwiftAndInstall(
        _ ctx: TemperSwiftCoreContext,
        from executable: FilePath
    ) async throws {
        let bin = swiftlyBinDir(ctx)
        if !(try await fs.exists(atPath: bin)) {
            try await fs.mkdir(.parents, atPath: bin)
        }
        let destination = bin / "temper-swift.exe"
        if try await fs.exists(atPath: destination) {
            try await fs.remove(atPath: destination)
        }
        try await fs.copy(atPath: executable, toPath: destination)
    }

    public func uninstall(
        _: TemperSwiftCoreContext,
        _ version: ToolchainVersion,
        verbose _: Bool
    ) async throws {
        throw TemperSwiftError(
            message: "TemperSwift will not remove shared Windows toolchain \(version) without an installation ownership receipt. Uninstall it through Windows Installed apps for now."
        )
    }

    public func getExecutableName() -> String { "temper-swift.exe" }

    public func verifyToolchainSignature(
        _: TemperSwiftCoreContext,
        toolchainFile _: ToolchainFile,
        archive: FilePath,
        verbose _: Bool
    ) async throws {
        try await verifyAuthenticode(archive)
    }

    public func verifyTemperSwiftSignature(
        _: TemperSwiftCoreContext,
        archiveDownloadURL _: URL,
        archive: FilePath,
        verbose _: Bool
    ) async throws {
        try await verifyAuthenticode(archive)
    }

    public func detectPlatform(
        _: TemperSwiftCoreContext,
        disableConfirmation _: Bool,
        platform _: String?
    ) async throws -> PlatformDefinition {
        .windows10
    }

    public func getShell() async throws -> String { "powershell.exe" }

    public func findToolchainLocation(
        _ ctx: TemperSwiftCoreContext,
        _ toolchain: ToolchainVersion
    ) async throws -> FilePath {
        installRoot(ctx) / "Toolchains" / "\(directoryVersion(for: toolchain))+Asserts"
    }

    public func findToolchainBinDir(
        _ ctx: TemperSwiftCoreContext,
        _ toolchain: ToolchainVersion
    ) async throws -> FilePath {
        try await findToolchainLocation(ctx, toolchain) / "usr" / "bin"
    }

    public func updateEnvironmentWithToolchain(
        _ ctx: TemperSwiftCoreContext,
        _ environment: Environment,
        _ toolchain: ToolchainVersion,
        path: String
    ) async throws -> Environment {
        let version = directoryVersion(for: toolchain)
        let root = installRoot(ctx)
        let runtimeBin = root / "Runtimes" / version / "usr" / "bin"
        let sdk = root / "Platforms" / version / "Windows.platform" / "Developer" / "SDKs" / "Windows.sdk"
        let selectedPath = [runtimeBin.string, path].filter { !$0.isEmpty }.joined(separator: ";")
        return environment.updating([
            "PATH": selectedPath,
            "SDKROOT": sdk.string,
            "TEMPER_SWIFT_VERSION": version,
            "TEMPER_SWIFT_PLATFORM_ROOT": (root / "Platforms" / version).string,
        ])
    }

    public static let currentPlatform: any Platform = Windows()

    private var localAppData: String {
        ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func installRoot(_ ctx: TemperSwiftCoreContext) -> FilePath {
        if let mockedHomeDir = ctx.mockedHomeDir { return mockedHomeDir / "Programs" / "Swift" }
        if let configured = ProcessInfo.processInfo.environment["TEMPER_SWIFT_INSTALL_ROOT"] {
            return FilePath(configured)
        }
        return FilePath(localAppData) / "Programs" / "Swift"
    }

    private func directoryVersion(for toolchain: ToolchainVersion) -> String {
        switch toolchain {
        case let .stable(release):
            return "\(release.major).\(release.minor).\(release.patch)"
        case let .snapshot(snapshot):
            switch snapshot.branch {
            case let .release(major, minor, _): return "\(major).\(minor).0"
            case .main: return "main"
            }
        case .xcode:
            return "xcode"
        }
    }

    private func verifyAuthenticode(_ executable: FilePath) async throws {
        let escaped = executable.string.replacingOccurrences(of: "'", with: "''")
        let script = "if ((Get-AuthenticodeSignature -LiteralPath '\(escaped)').Status -ne 'Valid') { exit 1 }"
        let configuration = Configuration(
            executable: .name("powershell.exe"),
            arguments: ["-NoProfile", "-NonInteractive", "-Command", script]
        )
        let result = try await Subprocess.run(
            configuration,
            output: .discarded,
            error: .discarded
        )
        guard result.terminationStatus.isSuccess else {
            throw TemperSwiftError(message: "Authenticode validation failed for \(executable)")
        }
    }
}
