import Foundation
@testable import TemperSwift
@testable import TemperSwiftCommands
@testable import TemperSwiftCore
import Testing

@Suite struct UnlinkTests {
    /// Tests that disabling swiftly results in swiftlyBinDir with no symlinks to toolchain binaries in it.
    @Test(.testHomeMockedToolchain()) func testUnlink() async throws {
        try await TemperSwiftTests.withTestHome {
            let swiftlyBinDir = TemperSwift.currentPlatform.swiftlyBinDir(TemperSwiftTests.ctx)
            let swiftlyBinaryPath = swiftlyBinDir / "swiftly"
            try "mockBinary".write(to: swiftlyBinaryPath, atomically: true, encoding: .utf8)

            let proxies = ["swift-build", "swift-test", "swift-run"]
            for proxy in proxies {
                let proxyPath = swiftlyBinDir / proxy
                try await fs.symlink(atPath: proxyPath, linkPath: swiftlyBinaryPath)
            }

            _ = try await TemperSwiftTests.runWithMockedIO(Unlink.self, ["unlink"])

            let disabledTemperSwiftBinDirContents = try await fs.ls(atPath: swiftlyBinDir)
            #expect(disabledTemperSwiftBinDirContents == ["swiftly"])
        }
    }
}
