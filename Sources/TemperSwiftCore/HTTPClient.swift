import _StringProcessing
import Foundation
import HTTPTypes
import OpenAPIRuntime
#if os(Windows)
import OpenAPIURLSession
#else
import AsyncHTTPClient
import OpenAPIAsyncHTTPClient
#endif
import TemperSwiftDownloadAPI
import TemperSwiftWebsiteAPI
import SystemPackage

extension TemperSwiftWebsiteAPI.Components.Schemas.TemperSwiftRelease {
    public var swiftlyVersion: TemperSwiftVersion {
        get throws {
            guard let releaseVersion = try? TemperSwiftVersion(parsing: self.version) else {
                throw TemperSwiftError(message: "Invalid swiftly version reported: \(self.version)")
            }

            return releaseVersion
        }
    }
}

extension TemperSwiftWebsiteAPI.Components.Schemas.TemperSwiftReleasePlatformArtifacts {
    public var isDarwin: Bool {
        self.platform.value1 == .darwin
    }

    public var isLinux: Bool {
        self.platform.value1 == .linux
    }

    public var x86_64URL: URL {
        get throws {
            guard let url = URL(string: self.x8664) else {
                throw TemperSwiftError(message: "The swiftly x86_64 URL is invalid: \(self.x8664)")
            }

            return url
        }
    }

    public var arm64URL: URL {
        get throws {
            guard let url = URL(string: self.arm64) else {
                throw TemperSwiftError(message: "The swiftly arm64 URL is invalid: \(self.arm64)")
            }

            return url
        }
    }
}

extension TemperSwiftWebsiteAPI.Components.Schemas.TemperSwiftPlatformIdentifier {
    public init(
        _ knownTemperSwiftPlatformIdentifier: TemperSwiftWebsiteAPI.Components.Schemas
            .KnownTemperSwiftPlatformIdentifier
    ) {
        self.init(value1: knownTemperSwiftPlatformIdentifier)
    }
}

public struct ToolchainFile: Sendable {
    public var category: String
    public var platform: String
    public var version: String
    public var file: String

    public init(category: String, platform: String, version: String, file: String) {
        self.category = category
        self.platform = platform
        self.version = version
        self.file = file
    }
}

public protocol HTTPRequestExecutor: Sendable {
    func getCurrentTemperSwiftRelease() async throws
        -> TemperSwiftWebsiteAPI.Components.Schemas.TemperSwiftRelease
    func getReleaseToolchains() async throws -> [TemperSwiftWebsiteAPI.Components.Schemas.Release]
    func getSnapshotToolchains(
        branch: TemperSwiftWebsiteAPI.Components.Schemas.SourceBranch,
        platform: TemperSwiftWebsiteAPI.Components.Schemas.PlatformIdentifier
    ) async throws -> TemperSwiftWebsiteAPI.Components.Schemas.DevToolchains
    func getGpgKeys() async throws -> OpenAPIRuntime.HTTPBody
    func getTemperSwiftRelease(url: URL) async throws -> OpenAPIRuntime.HTTPBody
    func getTemperSwiftReleaseSignature(url: URL) async throws -> OpenAPIRuntime.HTTPBody
    func getSwiftToolchainFile(_ toolchainFile: ToolchainFile) async throws
        -> OpenAPIRuntime.HTTPBody
    func getSwiftToolchainFileSignature(_ toolchainFile: ToolchainFile) async throws
        -> OpenAPIRuntime.HTTPBody
}

struct TemperSwiftUserAgentMiddleware: ClientMiddleware {
    package func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        // Adds the `Authorization` header field with the provided value.
        request.headerFields[.userAgent] = "swiftly/\(TemperSwiftCore.version)"
        return try await next(request, body, baseURL)
    }
}

/// An `HTTPRequestExecutor` backed by a shared `HTTPClient`. This makes actual network requests.
public final class HTTPRequestExecutorImpl: HTTPRequestExecutor {
#if !os(Windows)
    public let httpClient: HTTPClient
#endif

    public init() {
#if !os(Windows)
        var proxy: HTTPClient.Configuration.Proxy?

        func getProxyFromEnv(keys: [String]) -> HTTPClient.Configuration.Proxy? {
            let environment = ProcessInfo.processInfo.environment
            for key in keys {
                if let proxyString = environment[key],
                   let url = URL(string: proxyString),
                   let host = url.host,
                   let port = url.port
                {
                    return .server(host: host, port: port)
                }
            }
            return nil
        }

        if let httpProxy = getProxyFromEnv(keys: ["http_proxy", "HTTP_PROXY"]) {
            proxy = httpProxy
        }
        if let httpsProxy = getProxyFromEnv(keys: ["https_proxy", "HTTPS_PROXY"]) {
            proxy = httpsProxy
        }

        if proxy != nil {
            self.httpClient = HTTPClient(
                eventLoopGroupProvider: .singleton,
                configuration: HTTPClient.Configuration(proxy: proxy)
            )
        } else {
            self.httpClient = HTTPClient.shared
        }
#endif
    }

    deinit {
#if !os(Windows)
        if httpClient !== HTTPClient.shared {
            try? httpClient.syncShutdown()
        }
#endif
    }

    private func websiteClient() throws -> TemperSwiftWebsiteAPI.Client {
        let swiftlyUserAgent = TemperSwiftUserAgentMiddleware()
        let transport: ClientTransport

#if os(Windows)
        transport = URLSessionTransport()
#else
        let config = AsyncHTTPClientTransport.Configuration(
            client: self.httpClient, timeout: .seconds(30)
        )
        transport = AsyncHTTPClientTransport(configuration: config)
#endif

        return Client(
            serverURL: try TemperSwiftWebsiteAPI.Servers.productionURL(),
            transport: transport,
            middlewares: [swiftlyUserAgent]
        )
    }

    private func downloadClient(baseURL: URL) throws -> TemperSwiftDownloadAPI.Client {
        let swiftlyUserAgent = TemperSwiftUserAgentMiddleware()
        let transport: ClientTransport

#if os(Windows)
        transport = URLSessionTransport()
#else
        let config = AsyncHTTPClientTransport.Configuration(
            client: self.httpClient, timeout: .seconds(30)
        )
        transport = AsyncHTTPClientTransport(configuration: config)
#endif

        return TemperSwiftDownloadAPI.Client(
            serverURL: baseURL,
            transport: transport,
            middlewares: [swiftlyUserAgent]
        )
    }

    public func getCurrentTemperSwiftRelease() async throws
        -> TemperSwiftWebsiteAPI.Components.Schemas.TemperSwiftRelease
    {
        let response = try await self.websiteClient().getCurrentTemperSwiftRelease()
        return try response.ok.body.json
    }

    public func getReleaseToolchains() async throws -> [
        TemperSwiftWebsiteAPI.Components.Schemas
            .Release
    ] {
        let response = try await self.websiteClient().listReleases()
        return try response.ok.body.json
    }

    public func getSnapshotToolchains(
        branch: TemperSwiftWebsiteAPI.Components.Schemas.SourceBranch,
        platform: TemperSwiftWebsiteAPI.Components.Schemas.PlatformIdentifier
    ) async throws -> TemperSwiftWebsiteAPI.Components.Schemas.DevToolchains {
        let response = try await self.websiteClient().listDevToolchains(
            .init(path: .init(branch: branch, platform: platform)))
        return try response.ok.body.json
    }

    public func getGpgKeys() async throws -> OpenAPIRuntime.HTTPBody {
        let response = try await downloadClient(baseURL: TemperSwiftDownloadAPI.Servers.productionURL())
            .swiftGpgKeys(
                .init())

        return try response.ok.body.plainText
    }

    public func getTemperSwiftRelease(url: URL) async throws -> OpenAPIRuntime.HTTPBody {
        guard
            try url.host(percentEncoded: false)
            == Servers.productionDownloadURL().host(percentEncoded: false),
            let match = try #/\/swiftly\/(?<platform>.+)\/(?<file>.+)/#.wholeMatch(
                in: url.path(percentEncoded: false))
        else {
            throw TemperSwiftError(
                message:
                "Unexpected TemperSwift download URL format: \(url.path(percentEncoded: false))")
        }

        let response = try await downloadClient(
            baseURL: TemperSwiftDownloadAPI.Servers.productionDownloadURL()
        )
        .downloadTemperSwiftRelease(
            .init(
                path: .init(
                    platform: String(match.output.platform), file: String(match.output.file)
                ))
        )

        return try response.ok.body.binary
    }

    public func getTemperSwiftReleaseSignature(url: URL) async throws -> OpenAPIRuntime.HTTPBody {
        guard
            try url.host(percentEncoded: false)
            == Servers.productionDownloadURL().host(percentEncoded: false),
            let match = try #/\/swiftly\/(?<platform>.+)\/(?<file>.+).sig/#.wholeMatch(
                in: url.path(percentEncoded: false))
        else {
            throw TemperSwiftError(
                message:
                "Unexpected TemperSwift signature URL format: \(url.path(percentEncoded: false))")
        }

        let response = try await downloadClient(
            baseURL: TemperSwiftDownloadAPI.Servers.productionDownloadURL()
        )
        .getTemperSwiftReleaseSignature(
            .init(
                path: .init(
                    platform: String(match.output.platform), file: String(match.output.file)
                ))
        )

        return try response.ok.body.binary
    }

    public func getSwiftToolchainFile(_ toolchainFile: ToolchainFile) async throws
        -> OpenAPIRuntime.HTTPBody
    {
        let response = try await downloadClient(
            baseURL: TemperSwiftDownloadAPI.Servers.productionDownloadURL()
        )
        .downloadSwiftToolchain(
            .init(
                path: .init(
                    category: String(toolchainFile.category),
                    platform: String(toolchainFile.platform),
                    version: String(toolchainFile.version), file: String(toolchainFile.file)
                )))
        if response == .notFound {
            throw try DownloadNotFoundError(
                url: Servers.productionDownloadURL().appendingPathComponent(toolchainFile.category)
                    .appendingPathComponent(toolchainFile.platform).appendingPathComponent(
                        toolchainFile.version
                    ).appendingPathComponent(toolchainFile.file))
        }

        return try response.ok.body.binary
    }

    public func getSwiftToolchainFileSignature(_ toolchainFile: ToolchainFile) async throws
        -> OpenAPIRuntime.HTTPBody
    {
        let response = try await downloadClient(
            baseURL: TemperSwiftDownloadAPI.Servers.productionDownloadURL()
        )
        .getSwiftToolchainSignature(
            .init(
                path: .init(
                    category: String(toolchainFile.category),
                    platform: String(toolchainFile.platform),
                    version: String(toolchainFile.version), file: String(toolchainFile.file)
                )))

        return try response.ok.body.binary
    }
}

extension TemperSwiftWebsiteAPI.Components.Schemas.Release {
    var stableName: String {
        let components = self.name.components(separatedBy: ".")
        if components.count == 2 {
            return self.name + ".0"
        } else {
            return self.name
        }
    }
}

extension TemperSwiftWebsiteAPI.Components.Schemas.Architecture {
    public init(_ knownArchitecture: TemperSwiftWebsiteAPI.Components.Schemas.KnownArchitecture) {
        self.init(value1: knownArchitecture, value2: knownArchitecture.rawValue)
    }

    public init(_ string: String) {
        self.init(value2: string)
    }
}

extension TemperSwiftWebsiteAPI.Components.Schemas.PlatformIdentifier {
    public init(
        _ knownPlatformIdentifier: TemperSwiftWebsiteAPI.Components.Schemas.KnownPlatformIdentifier
    ) {
        self.init(value1: knownPlatformIdentifier)
    }

    public init(_ string: String) {
        self.init(value2: string)
    }
}

extension TemperSwiftWebsiteAPI.Components.Schemas.SourceBranch {
    public init(_ knownSourceBranch: TemperSwiftWebsiteAPI.Components.Schemas.KnownSourceBranch) {
        self.init(value1: knownSourceBranch)
    }

    public init(_ string: String) {
        self.init(value2: string)
    }
}

extension TemperSwiftWebsiteAPI.Components.Schemas.Architecture {
    static let x8664: TemperSwiftWebsiteAPI.Components.Schemas.Architecture = .init(
        TemperSwiftWebsiteAPI.Components.Schemas.KnownArchitecture.x8664)
    static let aarch64: TemperSwiftWebsiteAPI.Components.Schemas.Architecture = .init(
        TemperSwiftWebsiteAPI.Components.Schemas.KnownArchitecture.aarch64)
}

extension TemperSwiftWebsiteAPI.Components.Schemas.Platform {
    /// platformDef is a mapping from the 'name' field of the swift.org platform object
    /// to swiftly's PlatformDefinition, if possible.
    var platformDef: PlatformDefinition? {
        // NOTE: some of these platforms are represented on swift.org metadata, but not supported by swiftly and so they don't have constants in PlatformDefinition
        switch self.name {
        case "Ubuntu 14.04":
            PlatformDefinition(
                name: "ubuntu1404", nameFull: "ubuntu14.04", namePretty: "Ubuntu 14.04"
            )
        case "Ubuntu 15.10":
            PlatformDefinition(
                name: "ubuntu1510", nameFull: "ubuntu15.10", namePretty: "Ubuntu 15.10"
            )
        case "Ubuntu 16.04":
            PlatformDefinition(
                name: "ubuntu1604", nameFull: "ubuntu16.04", namePretty: "Ubuntu 16.04"
            )
        case "Ubuntu 16.10":
            PlatformDefinition(
                name: "ubuntu1610", nameFull: "ubuntu16.10", namePretty: "Ubuntu 16.10"
            )
        case "Ubuntu 18.04":
            PlatformDefinition(
                name: "ubuntu1804", nameFull: "ubuntu18.04", namePretty: "Ubuntu 18.04"
            )
        case "Ubuntu 20.04":
            PlatformDefinition.ubuntu2004
        case "Amazon Linux 2":
            PlatformDefinition.amazonlinux2
        case "CentOS 8":
            PlatformDefinition(name: "centos8", nameFull: "centos8", namePretty: "CentOS 8")
        case "CentOS 7":
            PlatformDefinition(name: "centos7", nameFull: "centos7", namePretty: "CentOS 7")
        case "Windows 10":
            PlatformDefinition(name: "win10", nameFull: "windows10", namePretty: "Windows 10")
        case "Ubuntu 22.04":
            PlatformDefinition.ubuntu2204
        case "Red Hat Universal Base Image 9":
            PlatformDefinition.rhel9
        case "Ubuntu 24.04":
            PlatformDefinition(
                name: "ubuntu2404", nameFull: "ubuntu24.04", namePretty: "Ubuntu 24.04"
            )
        case "Ubuntu 26.04":
            PlatformDefinition(
                name: "ubuntu2604", nameFull: "ubuntu26.04", namePretty: "Ubuntu 26.04"
            )
        case "Debian 12":
            PlatformDefinition(
                name: "debian12", nameFull: "debian12", namePretty: "Debian GNU/Linux 12"
            )
        case "Debian 13":
            PlatformDefinition(
                name: "debian13", nameFull: "debian13", namePretty: "Debian GNU/Linux 13"
            )
        case "Fedora 39":
            PlatformDefinition(
                name: "fedora39", nameFull: "fedora39", namePretty: "Fedora Linux 39"
            )
        case "Fedora 41":
            PlatformDefinition(
                name: "fedora41", nameFull: "fedora41", namePretty: "Fedora Linux 41"
            )
        default:
            nil
        }
    }

    func matches(_ platform: PlatformDefinition) -> Bool {
        guard let myPlatform = self.platformDef else {
            return false
        }

        return myPlatform.name == platform.name
    }
}

extension TemperSwiftWebsiteAPI.Components.Schemas.DevToolchainForArch {
    private static func snapshotRegex() -> Regex<(Substring, Substring?, Substring?, Substring?, Substring)> {
        try! Regex("swift(?:-(\\d+)\\.(\\d+)(?:\\.([a-zA-Z0-9]+))?)?-DEVELOPMENT-SNAPSHOT-(\\d{4}-\\d{2}-\\d{2})")
    }

    func parseSnapshot() throws -> ToolchainVersion.Snapshot? {
        guard let match = try? Self.snapshotRegex().firstMatch(in: self.dir) else {
            return nil
        }

        let branch: ToolchainVersion.Snapshot.Branch
        if let majorString = match.output.1, let minorString = match.output.2 {
            guard let major = Int(majorString), let minor = Int(minorString) else {
                throw TemperSwiftError(
                    message: "malformatted release branch: \"\(majorString).\(minorString)\"")
            }
            let patch = match.output.3.map(String.init)
            branch = .releaseNormalized(major: major, minor: minor, patch: patch)
        } else {
            branch = .main
        }

        return ToolchainVersion.Snapshot(branch: branch, date: String(match.output.4))
    }
}

public struct DownloadProgress {
    public let receivedBytes: Int
    public let totalBytes: Int?
}

public struct DownloadNotFoundError: LocalizedError {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

/// HTTPClient wrapper used for interfacing with various REST APIs and downloading things.
public struct TemperSwiftHTTPClient: Sendable {
    public let httpRequestExecutor: HTTPRequestExecutor

    public init(httpRequestExecutor: HTTPRequestExecutor) {
        self.httpRequestExecutor = httpRequestExecutor
    }

    /// Return the current TemperSwift release using the swift.org API.
    public func getCurrentTemperSwiftRelease() async throws
        -> TemperSwiftWebsiteAPI.Components.Schemas.TemperSwiftRelease
    {
        try await self.httpRequestExecutor.getCurrentTemperSwiftRelease()
    }

    /// Return an array of released Swift versions that match the given filter, up to the provided
    /// limit (default unlimited).
    public func getReleaseToolchains(
        platform: PlatformDefinition,
        arch a: TemperSwiftWebsiteAPI.Components.Schemas.Architecture? = nil,
        limit: Int? = nil,
        filter: ((ToolchainVersion.StableRelease) -> Bool)? = nil
    ) async throws -> [ToolchainVersion.StableRelease] {
        let arch = a ?? cpuArch

        let releases = try await self.httpRequestExecutor.getReleaseToolchains()

        var swiftOrgFiltered: [ToolchainVersion.StableRelease] = try releases.compactMap {
            swiftOrgRelease in
            if platform.name != PlatformDefinition.macOS.name {
                // If the platform isn't xcode then verify that there is an offering for this platform name and arch
                guard
                    let swiftOrgPlatform = swiftOrgRelease.platforms.first(where: {
                        $0.matches(platform)
                    })
                else {
                    return nil
                }

                guard case let archs = swiftOrgPlatform.archs, archs.contains(arch) else {
                    return nil
                }
            }

            guard let version = try? ToolchainVersion(parsing: swiftOrgRelease.stableName),
                  case let .stable(release) = version
            else {
                throw TemperSwiftError(
                    message:
                    "error parsing swift.org release version: \(swiftOrgRelease.stableName)")
            }

            if let filter {
                guard filter(release) else {
                    return nil
                }
            }

            return release
        }

        swiftOrgFiltered.sort(by: >)

        return if let limit {
            Array(swiftOrgFiltered.prefix(limit))
        } else {
            swiftOrgFiltered
        }
    }

    public struct SnapshotBranchNotFoundError: LocalizedError {
        public var branch: ToolchainVersion.Snapshot.Branch
    }

    /// Return an array of Swift snapshots that match the given filter, up to the provided
    /// limit (default unlimited).
    public func getSnapshotToolchains(
        platform: PlatformDefinition,
        arch a: String? = nil,
        branch: ToolchainVersion.Snapshot.Branch,
        limit: Int? = nil,
        filter: ((ToolchainVersion.Snapshot) -> Bool)? = nil
    ) async throws -> [ToolchainVersion.Snapshot] {
        let platformId: TemperSwiftWebsiteAPI.Components.Schemas.PlatformIdentifier =
            switch platform.name
        {
        // These are new platforms that aren't yet in the list of known platforms in the OpenAPI schema
        case PlatformDefinition.ubuntu2404.name, PlatformDefinition.ubuntu2604.name,
             PlatformDefinition.debian12.name, PlatformDefinition.debian13.name,
             PlatformDefinition.fedora39.name, PlatformDefinition.fedora41.name:
            .init(platform.name)

        case PlatformDefinition.ubuntu2204.name:
            .init(.ubuntu2204)
        case PlatformDefinition.ubuntu2004.name:
            .init(.ubuntu2004)
        case PlatformDefinition.rhel9.name:
            .init(.ubi9)
        case PlatformDefinition.amazonlinux2.name:
            .init(.amazonlinux2)
        case PlatformDefinition.macOS.name:
            .init(.macos)
        case PlatformDefinition.windows10.name:
            .init(.windows10)
        default:
            throw TemperSwiftError(
                message: "No snapshot toolchains available for platform \(platform.name)")
        }

        let sourceBranch: TemperSwiftWebsiteAPI.Components.Schemas.SourceBranch =
            switch branch
        {
        case .main:
            .init(.main)
        case let .release(major, minor, patch):
            .init("\(major).\(minor)\(patch.map { ".\($0)" } ?? "")")
        }

        let devToolchains = try await self.httpRequestExecutor.getSnapshotToolchains(
            branch: sourceBranch, platform: platformId
        )

        let arch = a ?? cpuArch.value2

        // These are the available snapshots for the branch, platform, and architecture
        let swiftOrgSnapshots =
            if platform.name == PlatformDefinition.macOS.name
        {
            devToolchains.universal
                ?? [TemperSwiftWebsiteAPI.Components.Schemas.DevToolchainForArch]()
        } else if arch == "aarch64" {
            devToolchains.aarch64
                ?? [TemperSwiftWebsiteAPI.Components.Schemas.DevToolchainForArch]()
        } else if arch == "x86_64" {
            devToolchains.x8664 ?? [TemperSwiftWebsiteAPI.Components.Schemas.DevToolchainForArch]()
        } else {
            [TemperSwiftWebsiteAPI.Components.Schemas.DevToolchainForArch]()
        }

        // Convert these into toolchain snapshot versions that match the filter
        var matchingSnapshots = try swiftOrgSnapshots.map { try $0.parseSnapshot() }.compactMap {
            $0
        }
        .filter { toolchainVersion in
            if let filter {
                guard filter(toolchainVersion) else {
                    return false
                }
            }

            return true
        }

        matchingSnapshots.sort(by: >)

        return if let limit {
            Array(matchingSnapshots.prefix(limit))
        } else {
            matchingSnapshots
        }
    }

    public func getGpgKeys() async throws -> OpenAPIRuntime.HTTPBody {
        try await self.httpRequestExecutor.getGpgKeys()
    }

    public func getTemperSwiftRelease(url: URL) async throws -> OpenAPIRuntime.HTTPBody {
        try await self.httpRequestExecutor.getTemperSwiftRelease(url: url)
    }

    public func getTemperSwiftReleaseSignature(url: URL) async throws -> OpenAPIRuntime.HTTPBody {
        try await self.httpRequestExecutor.getTemperSwiftReleaseSignature(url: url)
    }

    public func getSwiftToolchainFile(_ toolchainFile: ToolchainFile) async throws
        -> OpenAPIRuntime.HTTPBody
    {
        try await self.httpRequestExecutor.getSwiftToolchainFile(toolchainFile)
    }

    public func getSwiftToolchainFileSignature(_ toolchainFile: ToolchainFile) async throws
        -> OpenAPIRuntime.HTTPBody
    {
        try await self.httpRequestExecutor.getSwiftToolchainFileSignature(toolchainFile)
    }
}

extension OpenAPIRuntime.HTTPBody {
    public func download(
        to destination: FilePath, reportProgress: ((DownloadProgress) async -> Void)? = nil
    )
        async throws
    {
        let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: destination.string))

        defer {
            try? fileHandle.close()
        }

        let expectedBytes: Int?
        switch self.length {
        case .unknown:
            expectedBytes = nil
        case let .known(count):
            expectedBytes = Int(count)
        }

        var lastUpdate = Date()
        var receivedBytes = 0
        for try await buffer in self {
            receivedBytes += buffer.count

            try fileHandle.write(contentsOf: buffer)

            let now = Date()
            if let reportProgress,
               lastUpdate.distance(to: now) > 0.25 || receivedBytes == expectedBytes
            {
                lastUpdate = now
                await reportProgress(
                    DownloadProgress(
                        receivedBytes: receivedBytes,
                        totalBytes: expectedBytes
                    )
                )
            }
        }

        try fileHandle.synchronize()
    }
}
