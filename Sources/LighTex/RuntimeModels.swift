import Foundation

enum TeXProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case managed
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .managed: "LighTeX Runtime"
        case .system: "System TeX"
        }
    }
}

enum RuntimeVariant: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal
    case standard
    case full

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var summary: String {
        switch self {
        case .minimal:
            "All three engines with the smallest practical package set."
        case .standard:
            "Recommended for textbooks, mathematics, figures, fonts, and bibliographies."
        case .full:
            "The complete TeX Live package set for maximum offline compatibility."
        }
    }
}

enum RuntimeArchitecture: String, Codable, Sendable {
    case arm64
    case x86_64

    static var current: RuntimeArchitecture {
        #if arch(arm64)
        .arm64
        #else
        .x86_64
        #endif
    }
}

struct RuntimeManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let runtimeVersion: String
    let texLiveYear: Int
    let assets: [RuntimeAsset]
}

struct RuntimeAsset: Codable, Equatable, Identifiable, Sendable {
    let variant: RuntimeVariant
    let architecture: RuntimeArchitecture
    let downloadURL: URL?
    let downloadParts: [RuntimeArchivePart]?
    let compressedSize: Int64
    let installedSize: Int64
    let sha256: String
    let tools: [String: String]
    var displayCompressedSize: Int64? = nil

    var id: String { "\(variant.rawValue)-\(architecture.rawValue)" }
    var presentedCompressedSize: Int64 { displayCompressedSize ?? compressedSize }

    var archiveParts: [RuntimeArchivePart] {
        if let downloadParts, !downloadParts.isEmpty {
            return downloadParts
        }
        guard let downloadURL else { return [] }
        return [RuntimeArchivePart(downloadURL: downloadURL, compressedSize: compressedSize)]
    }

    init(
        variant: RuntimeVariant,
        architecture: RuntimeArchitecture,
        downloadURL: URL? = nil,
        downloadParts: [RuntimeArchivePart]? = nil,
        compressedSize: Int64,
        installedSize: Int64,
        sha256: String,
        tools: [String: String],
        displayCompressedSize: Int64? = nil
    ) {
        self.variant = variant
        self.architecture = architecture
        self.downloadURL = downloadURL
        self.downloadParts = downloadParts
        self.compressedSize = compressedSize
        self.installedSize = installedSize
        self.sha256 = sha256
        self.tools = tools
        self.displayCompressedSize = displayCompressedSize
    }
}

struct RuntimeArchivePart: Codable, Equatable, Sendable {
    let downloadURL: URL
    let compressedSize: Int64
}

struct ManagedRuntimeRecord: Codable, Equatable, Sendable {
    let runtimeVersion: String
    let texLiveYear: Int
    let variant: RuntimeVariant
    let architecture: RuntimeArchitecture
    let rootPath: String
    let tools: [String: String]
}

struct InstalledRuntime: Identifiable, Equatable, Sendable {
    let recordURL: URL
    let record: ManagedRuntimeRecord
    let installedSize: Int64
    let isActive: Bool

    var id: String { recordURL.standardizedFileURL.path }
    var rootURL: URL { URL(fileURLWithPath: record.rootPath, isDirectory: true) }
}

struct RuntimeCacheUsage: Equatable, Sendable {
    var downloadsAndStaging: Int64 = 0
    var buildCache: Int64 = 0
}

struct RuntimeDownloadProgress: Equatable, Sendable {
    let receivedBytes: Int64
    let totalBytes: Int64
    let bytesPerSecond: Double

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
    }
}

enum RuntimeInstallState: Equatable, Sendable {
    case idle
    case checking
    case downloading(RuntimeDownloadProgress)
    case verifying
    case installing
    case ready(ManagedRuntimeRecord)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .verifying, .installing:
            true
        default:
            false
        }
    }
}

struct ToolExecutableStatus: Equatable, Sendable {
    let url: URL
    let version: String?
}

struct ToolchainStatus: Equatable, Sendable {
    var engines: [LatexEngine: ToolExecutableStatus]
    var latexmk: ToolExecutableStatus?
    var synctex: ToolExecutableStatus?
    var tlmgr: ToolExecutableStatus?

    static let empty = ToolchainStatus(engines: [:], latexmk: nil, synctex: nil, tlmgr: nil)

    var hasAnyEngine: Bool { !engines.isEmpty }

    func supports(engine: LatexEngine, tool: BuildTool) -> Bool {
        guard engines[engine] != nil else { return false }
        return tool == .directCompiler || latexmk != nil
    }
}

enum RuntimeError: LocalizedError, Equatable {
    case invalidManifest
    case invalidManifestSignature
    case unsupportedArchitecture
    case insufficientDiskSpace(required: Int64)
    case invalidArchiveHash
    case missingTool(String)
    case invalidToolPath(String)
    case noConfiguredToolchain
    case missingEngine(String)
    case missingBuildTool(String)
    case packageManagerUnavailable
    case packageNotFound(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "The runtime manifest is invalid or unsupported."
        case .invalidManifestSignature: "The runtime manifest signature could not be verified."
        case .unsupportedArchitecture: "No runtime is available for this Mac architecture."
        case let .insufficientDiskSpace(required):
            "There is not enough free disk space. LighTex needs at least \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file))."
        case .invalidArchiveHash: "The downloaded runtime failed its integrity check."
        case let .missingTool(tool): "The installed runtime does not contain \(tool)."
        case let .invalidToolPath(path): "The runtime contains an unsafe tool path: \(path)."
        case .noConfiguredToolchain: "Choose or install a LaTeX runtime before building."
        case let .missingEngine(engine): "\(engine) is not available in the selected TeX environment."
        case let .missingBuildTool(tool): "\(tool) is not available in the selected TeX environment."
        case .packageManagerUnavailable: "Package installation is available only for a managed LighTeX Runtime."
        case let .packageNotFound(file): "No TeX Live package providing \(file) was found."
        case let .commandFailed(message): message
        }
    }
}
