import Foundation
import Subprocess
@testable import TemperSwift
@testable import TemperSwiftCommands
@testable import TemperSwiftCore
import SystemPackage
import Testing

@Suite struct PlatformTests {
    func mockToolchainDownload(version: String) async throws -> (FilePath, ToolchainVersion, FilePath) {
        let mockDownloader = MockToolchainDownloader(executables: ["swift"])
        let version = try! ToolchainVersion(parsing: version)
        let ext = TemperSwift.currentPlatform.toolchainFileExtension
        let tmpDir = fs.mktemp()
        try! await fs.mkdir(.parents, atPath: tmpDir)
        let mockedToolchainFile = tmpDir / "swift-\(version).\(ext)"
        let mockedToolchain = try await mockDownloader.makeMockedToolchain(toolchain: version, name: tmpDir.lastComponent!.string)
        try mockedToolchain.write(to: mockedToolchainFile)

        return (mockedToolchainFile, version, tmpDir)
    }

    @Test(.testHome(), .mockedTemperSwiftVersion()) func install() async throws {
        // GIVEN: a toolchain has been downloaded
        var (mockedToolchainFile, version, tmpDir) = try await self.mockToolchainDownload(version: "5.7.1")
        var cleanup = [tmpDir]
        defer {
            for dir in cleanup {
                try? FileManager.default.removeItem(atPath: dir)
            }
        }

        // WHEN: the platform installs the toolchain
        try await TemperSwift.currentPlatform.install(TemperSwiftTests.ctx, from: mockedToolchainFile, version: version, verbose: true)
        // THEN: the toolchain is extracted in the toolchains directory
        var toolchains = try await fs.ls(atPath: TemperSwift.currentPlatform.swiftlyToolchainsDir(TemperSwiftTests.ctx))
        #expect(1 == toolchains.count)

        // GIVEN: a second toolchain has been downloaded
        (mockedToolchainFile, version, tmpDir) = try await self.mockToolchainDownload(version: "5.8.0")
        cleanup += [tmpDir]
        // WHEN: the platform installs the toolchain
        try await TemperSwift.currentPlatform.install(TemperSwiftTests.ctx, from: mockedToolchainFile, version: version, verbose: true)
        // THEN: the toolchain is added to the toolchains directory
        toolchains = try await fs.ls(atPath: TemperSwift.currentPlatform.swiftlyToolchainsDir(TemperSwiftTests.ctx))
        #expect(2 == toolchains.count)

        // GIVEN: an identical toolchain has been downloaded
        (mockedToolchainFile, version, tmpDir) = try await self.mockToolchainDownload(version: "5.8.0")
        cleanup += [tmpDir]
        // WHEN: the platform installs the toolchain
        try await TemperSwift.currentPlatform.install(TemperSwiftTests.ctx, from: mockedToolchainFile, version: version, verbose: true)
        // THEN: the toolchains directory remains the same
        toolchains = try await fs.ls(atPath: TemperSwift.currentPlatform.swiftlyToolchainsDir(TemperSwiftTests.ctx))
        #expect(2 == toolchains.count)
    }

    @Test(.testHome(), .mockedTemperSwiftVersion()) func uninstall() async throws {
        // GIVEN: toolchains have been downloaded, and installed
        var (mockedToolchainFile, version, tmpDir) = try await self.mockToolchainDownload(version: "5.8.0")
        var cleanup = [tmpDir]
        defer {
            for dir in cleanup {
                try? FileManager.default.removeItem(atPath: dir)
            }
        }
        try await TemperSwift.currentPlatform.install(TemperSwiftTests.ctx, from: mockedToolchainFile, version: version, verbose: true)
        (mockedToolchainFile, version, tmpDir) = try await self.mockToolchainDownload(version: "5.6.3")
        cleanup += [tmpDir]
        try await TemperSwift.currentPlatform.install(TemperSwiftTests.ctx, from: mockedToolchainFile, version: version, verbose: true)
        // WHEN: one of the toolchains is uninstalled
        try await TemperSwift.currentPlatform.uninstall(TemperSwiftTests.ctx, version, verbose: true)
        // THEN: there is only one remaining toolchain installed
        var toolchains = try await fs.ls(atPath: TemperSwift.currentPlatform.swiftlyToolchainsDir(TemperSwiftTests.ctx))
        #expect(1 == toolchains.count)

        // GIVEN; there is only one toolchain installed
        // WHEN: a non-existent toolchain is uninstalled
        try? await TemperSwift.currentPlatform.uninstall(TemperSwiftTests.ctx, ToolchainVersion(parsing: "5.9.1"), verbose: true)
        // THEN: there is the one remaining toolchain that is still installed
        toolchains = try await fs.ls(atPath: TemperSwift.currentPlatform.swiftlyToolchainsDir(TemperSwiftTests.ctx))
        #expect(1 == toolchains.count)

        // GIVEN: there is only one toolchain installed
        // WHEN: the last toolchain is uninstalled
        try await TemperSwift.currentPlatform.uninstall(TemperSwiftTests.ctx, ToolchainVersion(parsing: "5.8.0"), verbose: true)
        // THEN: there are no toolchains installed
        toolchains = try await fs.ls(atPath: TemperSwift.currentPlatform.swiftlyToolchainsDir(TemperSwiftTests.ctx))
        #expect(0 == toolchains.count)
    }

#if os(macOS)
    @Test(.mockedTemperSwiftVersion(), .testHome()) func findXcodeToolchainLocation() async throws {
        // GIVEN: the xcode toolchain
        // AND there is xcode installed
        guard let swiftLocation = try? await run(.name("xcrun"), arguments: ["-f", "swift"], output: .string(limit: 1024 * 10)).standardOutput, swiftLocation != "" else {
            return
        }

        // WHEN: the location of the xcode toolchain can be found
        let toolchainLocation = try await TemperSwift.currentPlatform.findToolchainLocation(TemperSwiftTests.ctx, .xcodeVersion)

        // THEN: the xcode toolchain matches the currently selected xcode toolchain
        #expect(toolchainLocation.string == swiftLocation.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "/usr/bin/swift", with: ""))
    }
#endif

#if os(macOS) || os(Linux)
    @Test(
        .mockedTemperSwiftVersion(),
        .mockHomeToolchains(),
        arguments: [
            "/a/b/c:SWIFTLY_BIN_DIR:/d/e/f",
            "SWIFTLY_BIN_DIR:/abcde",
            "/defgh:SWIFTLY_BIN_DIR",
            "/xyzabc:/1/3/4",
            "",
        ]
    ) func proxyEnv(_ path: String) async throws {
        // GIVEN: a PATH that may contain the swiftly bin directory
        let env: Environment = .custom(["PATH": path.replacing("SWIFTLY_BIN_DIR", with: TemperSwift.currentPlatform.swiftlyBinDir(TemperSwiftTests.ctx).string)])

        // WHEN: proxying to an installed toolchain
        let newEnv = try await TemperSwift.currentPlatform.proxyEnvironment(TemperSwiftTests.ctx, env: env, toolchain: .newStable)

        // THEN: the toolchain's bin directory is added to the beginning of the PATH
        // #expect(newEnv.description == "")
        #expect(newEnv.description.contains("PATH: \"\((try await TemperSwift.currentPlatform.findToolchainLocation(TemperSwiftTests.ctx, .newStable)) / "usr/bin"):"))

        // AND: the swiftly bin directory is removed from the PATH
        #expect(!newEnv.description.contains(TemperSwift.currentPlatform.swiftlyBinDir(TemperSwiftTests.ctx).string))
        #expect(!newEnv.description.contains(TemperSwift.currentPlatform.swiftlyBinDir(TemperSwiftTests.ctx).string))
    }
#endif
}
