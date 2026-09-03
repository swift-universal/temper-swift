// swift-tools-version:6.2

import PackageDescription

let swiftSettings = [
    SwiftSetting.enableUpcomingFeature("MemberImportVisibility"),
]

// TemperSwiftCore calls NIOCore.TimeAmount.seconds in its non-Windows transport
// configuration without importing NIOCore at file scope. SE-0444
// MemberImportVisibility requires the DEFINING module to be imported in the
// file, and no Package.swift edit can substitute for that import - declaring the
// NIOCore product dependency (done below) is necessary but not sufficient,
// verified by building on Linux with the dependency declared and the same two
// errors still raised at HTTPClient.swift:170 and :190.
//
// This scoped setting is the Package.swift-only path: it relaxes the diagnostic
// for this one target instead of dropping it for all ten. Composition intent is
// still recorded by the NIOCore dependency.
//
// RESOLVED: the source fix was taken. HTTPClient.swift now imports NIOCore in
// its non-Windows branch, so TemperSwiftCore no longer needs the diagnostic
// relaxed and carries the same settings as the other nine targets. The scoped
// empty array is gone rather than left in place as a no-op, because a setting
// that exists only to disable something is a claim about the code that is no
// longer true.
let temperSwiftCoreSwiftSettings: [SwiftSetting] = swiftSettings

#if os(Windows)
let releaseTargets: [Target] = []
#else
let releaseTargets: [Target] = [
    .executableTarget(
        name: "build-temper-swift-release",
        dependencies: [
            .target(name: "TemperSwiftCore"),
            .target(name: "TemperSwiftLinuxPlatform", condition: .when(platforms: [.linux])),
            .target(name: "TemperSwiftMacOSPlatform", condition: .when(platforms: [.macOS])),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "_NIOFileSystem", package: "swift-nio"),
        ],
        path: "Tools/build-temper-swift-release",
        exclude: ["musl-clang"],
    ),
]
#endif

let package = Package(
    name: "temper-swift",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "TemperSwift", targets: ["TemperSwift"]),
        .library(name: "TemperSwiftCommands", targets: ["TemperSwiftCommands"]),
        .executable(
            name: "temper-swift",
            targets: ["TemperSwiftExecutable"]
        ),
        .executable(
            name: "test-temper-swift",
            targets: ["TestTemperSwift"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/swift-server/async-http-client", from: "1.24.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-async-http-client", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.80.0"),
        // 2.37 adds NOCRYPT on Windows, avoiding WinCrypt's X509_NAME collision
        // with BoringSSL when building against current Windows SDKs.
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.37.2"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", from: "0.7.2"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.7.2"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.2"),
        .package(url: "https://github.com/apple/swift-system", from: "1.4.2"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "1.0.0", traits: []),
        // This dependency provides the correct version of the formatter so that you can run `swift run swiftformat Package.swift Plugins/ Sources/ Tests/`
        .package(url: "https://github.com/nicklockwood/SwiftFormat", exact: "0.49.18"),
    ],
    targets: [
        .target(
            name: "TemperSwift",
            dependencies: [
                .target(name: "TemperSwiftCore"),
                .target(name: "TemperSwiftLinuxPlatform", condition: .when(platforms: [.linux])),
                .target(name: "TemperSwiftMacOSPlatform", condition: .when(platforms: [.macOS])),
                .target(name: "TemperSwiftWindowsPlatform", condition: .when(platforms: [.windows])),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "TemperSwiftCommands",
            dependencies: [
                .target(name: "TemperSwift"),
                .target(name: "TemperSwiftCore"),
                .target(name: "TemperSwiftWebsiteAPI"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "TemperSwiftExecutable",
            dependencies: ["TemperSwiftCommands"]
        ),
        .executableTarget(
            name: "TestTemperSwift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "TemperSwiftCore"),
                .target(name: "TemperSwiftLinuxPlatform", condition: .when(platforms: [.linux])),
                .target(name: "TemperSwiftMacOSPlatform", condition: .when(platforms: [.macOS])),
                .target(name: "TemperSwiftWindowsPlatform", condition: .when(platforms: [.windows])),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "TemperSwiftCore",
            dependencies: [
                "TemperSwiftDownloadAPI",
                "TemperSwiftWebsiteAPI",
                .product(
                    name: "AsyncHTTPClient",
                    package: "async-http-client",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                // TemperSwiftCore uses NIOCore.TimeAmount.seconds in the
                // non-Windows transport configuration but only received NIOCore
                // transitively through AsyncHTTPClient. MemberImportVisibility
                // surfaced that as a build failure on Linux. Declaring the
                // dependency here is the composition-level fix; same platform
                // condition as AsyncHTTPClient, since the usage is in the same
                // #if branch.
                .product(
                    name: "NIOCore",
                    package: "swift-nio",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(
                    name: "OpenAPIAsyncHTTPClient",
                    package: "swift-openapi-async-http-client",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "OpenAPIURLSession",
                    package: "swift-openapi-urlsession",
                    condition: .when(platforms: [.windows])
                ),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ],
            swiftSettings: temperSwiftCoreSwiftSettings,
            plugins: ["GenerateCommandModels"]
        ),
        .target(
            name: "TemperSwiftDownloadAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .target(
            name: "TemperSwiftWebsiteAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .target(
            name: "TemperSwiftDocs",
            path: "Documentation"
        ),
        .plugin(
            name: "GenerateDocsReference",
            capability: .command(
                intent: .custom(
                    verb: "generate-docs-reference",
                    description: "Generate a documentation reference for TemperSwift."
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "This command generates documentation."),
                ]
            ),
            dependencies: ["generate-docs-reference"]
        ),
        .plugin(
            name: "GenerateCommandModels",
            capability: .buildTool(),
            dependencies: [
                "generate-command-models",
            ]
        ),
        .executableTarget(
            name: "generate-docs-reference",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/generate-docs-reference"
        ),
        .executableTarget(
            name: "generate-command-models",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            path: "Tools/generate-command-models"
        ),
        .target(
            name: "TemperSwiftLinuxPlatform",
            dependencies: [
                "TemperSwiftCore",
                "CTemperSwiftLibArchive",
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            swiftSettings: swiftSettings,
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
        .target(
            name: "TemperSwiftMacOSPlatform",
            dependencies: [
                "TemperSwiftCore",
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "TemperSwiftWindowsPlatform",
            dependencies: [
                "TemperSwiftCore",
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            swiftSettings: swiftSettings
        ),
        .systemLibrary(
            name: "CTemperSwiftLibArchive",
            pkgConfig: "libarchive",
            providers: [
                .apt(["libarchive-dev"]),
            ]
        ),
        .testTarget(
            name: "TemperSwiftTests",
            dependencies: [
                "TemperSwift",
                "TemperSwiftCommands",
                "TemperSwiftCore",
                "TemperSwiftWebsiteAPI",
                .target(name: "TemperSwiftMacOSPlatform", condition: .when(platforms: [.macOS])),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            resources: [
                .embedInCode("mock-signing-key-private.pgp"),
            ],
            swiftSettings: swiftSettings
        ),
    ] + releaseTargets
)
