import ArgumentParser
import Foundation
import TemperSwift
import TemperSwiftCore
import TemperSwiftWebsiteAPI
@preconcurrency import TSCBasic
import TSCUtility

extension TemperSwiftVersion: ExpressibleByArgument {
    public init?(argument: String) {
        try? self.init(parsing: argument)
    }
}

struct SelfUpdate: TemperSwiftCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Update the version of swiftly itself."
    )

    @OptionGroup var root: GlobalOptions

    @Option(help: .hidden) var toVersion: TemperSwiftVersion? = nil

    private enum CodingKeys: String, CodingKey {
        case root, toVersion
    }

    mutating func run() async throws {
        try await self.run(TemperSwift.createDefaultContext())
    }

    mutating func run(_ ctx: TemperSwiftCoreContext) async throws {
        try await validateTemperSwift(ctx)

        let swiftlyBin = TemperSwift.currentPlatform.swiftlyBinDir(ctx) / "swiftly"
        guard try await fs.exists(atPath: swiftlyBin) else {
            throw TemperSwiftError(
                message:
                "Self update doesn't work when swiftly has been installed externally. Please keep it updated from the source where you installed it in the first place."
            )
        }

        let _ = try await Self.execute(ctx, verbose: self.root.verbose, version: self.toVersion)
    }

    public static func execute(_ ctx: TemperSwiftCoreContext, verbose: Bool, version swiftlyVersion: TemperSwiftVersion?) async throws
        -> TemperSwiftVersion
    {
        var downloadURL: Foundation.URL?
        var version: TemperSwiftVersion? = swiftlyVersion

        await ctx.message("Checking for swiftly updates...")

        if let version {
#if os(macOS)
            downloadURL = URL(string: "https://download.swift.org/swiftly/darwin/swiftly-\(version).pkg")
#elseif os(Linux)
#if arch(x86_64)
            downloadURL = URL(string: "https://download.swift.org/swiftly/linux/swiftly-\(version)-x86_64.tar.gz")
#elseif arch(arm64)
            downloadURL = URL(string: "https://download.swift.org/swiftly/linux/swiftly-\(version)-aarch64.tar.gz")
#else
            fatalError("Unsupported architecture")
#endif
#else
            fatalError("Unsupported OS")
#endif

            // Allow newer or identical versions to help self-update testing of a release
            guard version >= TemperSwiftCore.version else {
                await ctx.print("Self-update does not support downgrading to an older version or re-installing the current version. Current version is \(TemperSwiftCore.version) and requested version is \(version).")
                return TemperSwiftCore.version
            }

            await ctx.print("Self-update requested to swiftly version \(version)")
        }

        if downloadURL == nil {
            let swiftlyRelease = try await ctx.httpClient.getCurrentTemperSwiftRelease()

            guard try swiftlyRelease.swiftlyVersion > TemperSwiftCore.version else {
                await ctx.print("Already up to date.")
                return TemperSwiftCore.version
            }
            for platform in swiftlyRelease.platforms {
#if os(macOS)
                guard platform.isDarwin else {
                    continue
                }
#elseif os(Linux)
                guard platform.isLinux else {
                    continue
                }
#endif

#if arch(x86_64)
                downloadURL = try platform.x86_64URL
#elseif arch(arm64)
                downloadURL = try platform.arm64URL
#endif
            }

            guard let downloadURL else {
                throw TemperSwiftError(
                    message:
                    "The newest release of swiftly is incompatible with your current OS and/or processor architecture."
                )
            }

            version = try swiftlyRelease.swiftlyVersion

            await ctx.print("A new version of swiftly is available: \(version!)")
        }

        guard let version, let downloadURL else { fatalError() }

        let tmpFile = fs.mktemp(ext: ".\(TemperSwift.currentPlatform.toolchainFileExtension)")
        try await fs.create(file: tmpFile, contents: nil)
        return try await fs.withTemporary(files: tmpFile) {
            let animation = PercentProgressAnimation(
                stream: stdoutStream,
                header: "Downloading swiftly \(version)"
            )
            do {
                try await ctx.httpClient.getTemperSwiftRelease(url: downloadURL).download(
                    to: tmpFile,
                    reportProgress: { progress in
                        let downloadedMiB = Double(progress.receivedBytes) / (1024.0 * 1024.0)
                        let totalMiB = Double(progress.totalBytes!) / (1024.0 * 1024.0)

                        animation.update(
                            step: progress.receivedBytes,
                            total: progress.totalBytes!,
                            text:
                            "Downloaded \(String(format: "%.1f", downloadedMiB)) MiB of \(String(format: "%.1f", totalMiB)) MiB"
                        )
                    }
                )
            } catch {
                animation.complete(success: false)
                throw error
            }
            animation.complete(success: true)

            try await TemperSwift.currentPlatform.verifyTemperSwiftSignature(
                ctx, archiveDownloadURL: downloadURL, archive: tmpFile, verbose: verbose
            )
            try await TemperSwift.currentPlatform.extractTemperSwiftAndInstall(ctx, from: tmpFile)

            await ctx.message("Successfully updated swiftly to \(version) (was \(TemperSwiftCore.version))")
            return version
        }
    }
}
