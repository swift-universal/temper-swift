import Foundation
@testable import TemperSwift
@testable import TemperSwiftCommands
@testable import TemperSwiftCore
import SystemPackage
import Testing

@Suite struct SelfUninstallTests {
    // Test that swiftly uninstall successfully removes the swiftly binary and the bin directory
    @Test(.mockedTemperSwiftVersion()) func removesHomeAndBinDir() async throws {
        try await TemperSwiftTests.withTestHome {
            let swiftlyBinDir = TemperSwift.currentPlatform.swiftlyBinDir(TemperSwiftTests.ctx)
            let swiftlyHomeDir = TemperSwift.currentPlatform.swiftlyHomeDir(TemperSwiftTests.ctx)
            #expect(
                try await fs.exists(atPath: swiftlyBinDir) == true,
                "swiftly bin directory should exist"
            )
            #expect(
                try await fs.exists(atPath: swiftlyHomeDir) == true,
                "swiftly home directory should exist"
            )

            try await TemperSwiftTests.runCommand(SelfUninstall.self, ["self-uninstall"])

            #expect(
                try await fs.exists(atPath: swiftlyBinDir) == false,
                "swiftly bin directory should be removed"
            )
            if try await fs.exists(atPath: swiftlyHomeDir) {
                let contents = try await fs.ls(atPath: swiftlyHomeDir)
                #expect(
                    contents == ["Toolchains"] || contents == ["toolchains"] || contents.isEmpty,
                    "swiftly home directory should only contain 'toolchains' or be empty"
                )
            } else {
                #expect(
                    true,
                    "swiftly home directory should be removed"
                )
            }
        }
    }

    @Test(.mockedTemperSwiftVersion(), .withShell("/bin/bash")) func removesEntryFromShellProfile_bash() async throws {
        try await self.shellProfileRemovalTest()
    }

    @Test(.mockedTemperSwiftVersion(), .withShell("/bin/zsh")) func removesEntryFromShellProfile_zsh() async throws {
        try await self.shellProfileRemovalTest()
    }

    @Test(.mockedTemperSwiftVersion(), .withShell("/bin/fish")) func removesEntryFromShellProfile_fish() async throws {
        try await self.shellProfileRemovalTest()
    }

    func shellProfileRemovalTest() async throws {
        try await TemperSwiftTests.withTestHome {
            // Fresh user without swiftly installed
            try? await fs.remove(atPath: TemperSwift.currentPlatform.swiftlyConfigFile(TemperSwiftTests.ctx))
            try await TemperSwiftTests.runCommand(Init.self, ["init", "--assume-yes", "--skip-install"])

            let fishSourceLine = """
            # Added by swiftly

            source "\(TemperSwift.currentPlatform.swiftlyHomeDir(TemperSwiftTests.ctx) / "env.fish")"
            """

            let shSourceLine = """
            # Added by swiftly

            . "\(TemperSwift.currentPlatform.swiftlyHomeDir(TemperSwiftTests.ctx) / "env.sh")"
            """

            // add a few random lines to the profile file(s), both before and after the source line
            for p in [".profile", ".zprofile", ".bash_profile", ".bash_login", ".config/fish/conf.d/swiftly.fish"] {
                let profile = TemperSwiftTests.ctx.mockedHomeDir! / p
                if try await fs.exists(atPath: profile) {
                    if let profileContents = try? String(contentsOf: profile) {
                        let newContents = "# Random line before swiftly source\n" +
                            profileContents +
                            "\n# Random line after swiftly source"
                        try Data(newContents.utf8).write(to: profile, options: [.atomic])
                    }
                }
            }

            try await TemperSwiftTests.runCommand(SelfUninstall.self, ["self-uninstall", "--assume-yes"])

            for p in [".profile", ".zprofile", ".bash_profile", ".bash_login", ".config/fish/conf.d/swiftly.fish"] {
                let profile = TemperSwiftTests.ctx.mockedHomeDir! / p
                if try await fs.exists(atPath: profile) {
                    if let profileContents = try? String(contentsOf: profile) {
                        // check that the source line is removed
                        let isFishProfile = profile.extension == "fish"
                        let sourceLine = isFishProfile ? fishSourceLine : shSourceLine
                        #expect(
                            !profileContents.contains(sourceLine),
                            "swiftly source line should be removed from \(profile.string)"
                        )
                    }
                }
            }
        }
    }
}
