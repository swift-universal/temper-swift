import Foundation
#if os(Linux)
import TemperSwiftLinuxPlatform
#elseif os(macOS)
import TemperSwiftMacOSPlatform
#elseif os(Windows)
import TemperSwiftWindowsPlatform
#endif
import TemperSwiftCore
import SystemPackage

/// The non-CLI Swift toolchain engine used by Temper and programmatic consumers.
public enum TemperSwift {
    public static func createDefaultContext(
        format: TemperSwiftCore.OutputFormat = .text
    ) -> TemperSwiftCoreContext {
        TemperSwiftCoreContext(format: format)
    }

    /// The directories required to install and select Swift toolchains.
    public static func requiredDirectories(_ ctx: TemperSwiftCoreContext) -> [FilePath] {
        [
            currentPlatform.swiftlyHomeDir(ctx),
            currentPlatform.swiftlyBinDir(ctx),
            currentPlatform.swiftlyToolchainsDir(ctx),
        ]
    }

#if os(Linux)
    public static let currentPlatform = Linux.currentPlatform
#elseif os(macOS)
    public static let currentPlatform = MacOS.currentPlatform
#elseif os(Windows)
    public static let currentPlatform = Windows.currentPlatform
#endif
}
