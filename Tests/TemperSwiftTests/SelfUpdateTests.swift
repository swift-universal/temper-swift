import Foundation
@testable import TemperSwift
@testable import TemperSwiftCommands
@testable import TemperSwiftCore
import Testing

@Suite struct SelfUpdateTests {
    private static var newMajorVersion: TemperSwiftVersion {
        TemperSwiftVersion(major: TemperSwiftCore.version.major + 1, minor: 0, patch: 0)
    }

    private static var newMinorVersion: TemperSwiftVersion {
        TemperSwiftVersion(major: TemperSwiftCore.version.major, minor: TemperSwiftCore.version.minor + 1, patch: 0)
    }

    private static var newPatchVersion: TemperSwiftVersion {
        TemperSwiftVersion(major: TemperSwiftCore.version.major, minor: TemperSwiftCore.version.minor, patch: TemperSwiftCore.version.patch + 1)
    }

    private static var newDevVersion: TemperSwiftVersion {
        TemperSwiftVersion(major: TemperSwiftCore.version.major, minor: TemperSwiftCore.version.minor, patch: TemperSwiftCore.version.patch + 1, suffix: "dev")
    }

    func runSelfUpdateTest(latestVersion: TemperSwiftVersion) async throws {
        try await TemperSwiftTests.withTestHome {
            try await TemperSwiftTests.withMockedTemperSwiftVersion(latestTemperSwiftVersion: latestVersion) {
                let updatedVersion = try await SelfUpdate.execute(TemperSwiftTests.ctx, verbose: true, version: nil)
                #expect(latestVersion == updatedVersion)
            }
        }
    }

    @Test func selfUpdate() async throws {
        try await self.runSelfUpdateTest(latestVersion: Self.newPatchVersion)
        try await self.runSelfUpdateTest(latestVersion: Self.newMinorVersion)
        try await self.runSelfUpdateTest(latestVersion: Self.newMajorVersion)
    }

    /// Verify updating the most up-to-date toolchain has no effect.
    @Test func selfUpdateAlreadyUpToDate() async throws {
        try await self.runSelfUpdateTest(latestVersion: TemperSwiftCore.version)
    }

    @Test func selfUpdateToUserSpecifiedVersion() async throws {
        try await TemperSwiftTests.withTestHome {
            // GIVEN: swiftly is installed, and at the latest published version
            try await TemperSwiftTests.withMockedTemperSwiftVersion(latestTemperSwiftVersion: TemperSwiftCore.version) {
                // WHEN: An attempt is made to self-update to an equal version
                var updatedVersion = try await SelfUpdate.execute(TemperSwiftTests.ctx, verbose: true, version: TemperSwiftCore.version)
                // THEN: There is no change to the swiftly version
                #expect(updatedVersion == TemperSwiftCore.version)

                // WHEN: An attempt is made to self-update to an older version
                updatedVersion = try await SelfUpdate.execute(TemperSwiftTests.ctx, verbose: true, version: TemperSwiftVersion(major: TemperSwiftCore.version.major - 1, minor: 0, patch: 0))
                // THEN: There is no change to the swiftly version
                #expect(updatedVersion == TemperSwiftCore.version)

                // WHEN: An attempt is made to self-update to a newer development version
                updatedVersion = try await SelfUpdate.execute(TemperSwiftTests.ctx, verbose: true, version: Self.newDevVersion)
                // THEN: swiftly is updated to the new version
                #expect(updatedVersion == Self.newDevVersion)
            }
        }
    }
}
