import Combine
import Foundation

enum RuntimeConfiguration {
    static var manifestURL: URL {
        ProcessInfo.processInfo.environment["LIGHTEX_RUNTIME_MANIFEST_URL"]
            .flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/Samoilov2004/LighTeX/releases/download/runtime-latest/runtime-manifest.json")!
    }
    static var signatureURL: URL {
        ProcessInfo.processInfo.environment["LIGHTEX_RUNTIME_SIGNATURE_URL"]
            .flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/Samoilov2004/LighTeX/releases/download/runtime-latest/runtime-manifest.sig")!
    }
    private static let developmentPublicKey = "ypmAAFFVK3x/OdzoPWUQPMOiq9XPc6tAfRlOHVVsJJ0="

    static var publicKeyData: Data {
        let environmentValue = ProcessInfo.processInfo.environment["LIGHTEX_RUNTIME_PUBLIC_KEY_BASE64"]
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "LighTexRuntimePublicKey") as? String
        return Data(base64Encoded: environmentValue ?? bundleValue ?? developmentPublicKey) ?? Data()
    }
}

@MainActor
final class RuntimeManager: ObservableObject {
    @Published private(set) var systemStatus: ToolchainStatus = .empty
    @Published private(set) var activeStatus: ToolchainStatus = .empty
    @Published private(set) var manifest: RuntimeManifest?
    @Published private(set) var installState: RuntimeInstallState = .checking
    @Published private(set) var manifestError: String?
    @Published private(set) var isInstallingPackage = false
    @Published private(set) var packageOperationMessage: String?

    let settings: AppSettings

    private let manifestURL: URL
    private let signatureURL: URL
    private let publicKeyData: Data
    private var installTask: Task<Void, Never>?
    private var packageTask: Task<Void, Never>?
    private var downloadClient: RuntimeDownloadClient?

    var isSetupComplete: Bool {
        switch settings.texProvider {
        case .system:
            systemStatus.hasAnyEngine
        case .managed:
            activeStatus.hasAnyEngine
        case nil:
            false
        }
    }

    var currentStatus: ToolchainStatus {
        settings.texProvider == .system ? systemStatus : activeStatus
    }

    var activeManagedRecord: ManagedRuntimeRecord? {
        guard settings.texProvider == .managed,
              let path = settings.managedRuntimeRecordPath else { return nil }
        return Self.readRecord(at: URL(fileURLWithPath: path))
    }

    init(
        settings: AppSettings,
        manifestURL: URL = RuntimeConfiguration.manifestURL,
        signatureURL: URL = RuntimeConfiguration.signatureURL,
        publicKeyData: Data = RuntimeConfiguration.publicKeyData,
        startsAutomatically: Bool = true
    ) {
        self.settings = settings
        self.manifestURL = manifestURL
        self.signatureURL = signatureURL
        self.publicKeyData = publicKeyData
        if startsAutomatically {
            Task { [weak self] in
                await self?.bootstrap()
            }
        }
    }

    func bootstrap() async {
        installState = .checking
        async let detectedSystem = ToolchainService.detectSystem()
        let managedRecord = loadManagedRecord()
        systemStatus = await detectedSystem

        if let managedRecord {
            do {
                activeStatus = try ToolchainService.status(for: managedRecord)
                if settings.texProvider == .managed {
                    installState = .ready(managedRecord)
                } else {
                    installState = .idle
                }
            } catch {
                activeStatus = .empty
                if settings.texProvider == .managed {
                    settings.texProvider = nil
                    installState = .failed(error.localizedDescription)
                } else {
                    installState = .idle
                }
            }
        } else {
            activeStatus = .empty
            if settings.texProvider == .managed {
                settings.texProvider = nil
            }
            installState = .idle
        }

        if ProcessInfo.processInfo.environment["LIGHTEX_SNAPSHOT_SKIP_SETUP"] == "1",
           settings.texProvider == nil,
           systemStatus.hasAnyEngine {
            useSystemTeX()
        }

        await loadManifest()
        if settings.texProvider == nil,
           let rawVariant = ProcessInfo.processInfo.environment["LIGHTEX_RUNTIME_AUTOINSTALL_VARIANT"],
           let variant = RuntimeVariant(rawValue: rawVariant) {
            await performInstall(variant)
        }
    }

    func refreshSystemStatus() {
        Task { [weak self] in
            guard let self else { return }
            self.systemStatus = await ToolchainService.detectSystem()
            if self.settings.texProvider == .system {
                self.activeStatus = self.systemStatus
            }
        }
    }

    func useSystemTeX() {
        guard systemStatus.hasAnyEngine else { return }
        settings.texProvider = .system
        activeStatus = systemStatus
        selectFirstAvailableEngineIfNeeded(in: systemStatus)
        installState = .idle
    }

    func useManagedRuntime() {
        guard let record = loadManagedRecord() else { return }
        do {
            let status = try ToolchainService.status(for: record)
            activeStatus = status
            settings.texProvider = .managed
            selectFirstAvailableEngineIfNeeded(in: status)
            installState = .ready(record)
        } catch {
            installState = .failed(error.localizedDescription)
        }
    }

    func loadManifest() async {
        manifestError = nil
        do {
            let manifestData = try await Self.fetchData(from: manifestURL)
            let signature = try await Self.fetchData(from: signatureURL)
            try RuntimeSecurity.verifyManifest(
                manifestData,
                signature: signature,
                publicKey: publicKeyData
            )
            let decoded = try JSONDecoder().decode(RuntimeManifest.self, from: manifestData)
            try Self.validate(decoded)
            manifest = decoded
        } catch {
            manifest = nil
            manifestError = Self.manifestErrorMessage(for: error)
        }
    }

    func asset(for variant: RuntimeVariant) -> RuntimeAsset? {
        manifest?.assets.first {
            $0.variant == variant && $0.architecture == RuntimeArchitecture.current
        }
    }

    func install(_ variant: RuntimeVariant) {
        guard !installState.isBusy else { return }
        installTask?.cancel()
        installTask = Task { [weak self] in
            guard let self else { return }
            await self.performInstall(variant)
        }
    }

    func cancelInstall() {
        downloadClient?.cancel()
        installTask?.cancel()
        installTask = nil
        installState = .idle
    }

    func retryManifest() {
        Task { [weak self] in
            await self?.loadManifest()
        }
    }

    func buildConfiguration(engine: LatexEngine, tool: BuildTool) throws -> BuildConfiguration {
        guard isSetupComplete else { throw RuntimeError.noConfiguredToolchain }
        return try ToolchainService.buildConfiguration(
            status: currentStatus,
            engine: engine,
            tool: tool
        )
    }

    func supports(engine: LatexEngine, tool: BuildTool) -> Bool {
        isSetupComplete && currentStatus.supports(engine: engine, tool: tool)
    }

    var syncTeXURL: URL? { currentStatus.synctex?.url }

    func installMissingPackage(for file: String, completion: @escaping @MainActor (Bool) -> Void) {
        guard settings.texProvider == .managed,
              let tlmgr = currentStatus.tlmgr else {
            packageOperationMessage = RuntimeError.packageManagerUnavailable.localizedDescription
            completion(false)
            return
        }
        packageTask?.cancel()
        packageTask = Task { [weak self] in
            guard let self else { return }
            self.isInstallingPackage = true
            self.packageOperationMessage = "Searching TeX Live for \(file)…"
            let searchDirectories = self.currentStatus.engines.values.map {
                $0.url.deletingLastPathComponent()
            }
            do {
                let package = try await Task.detached(priority: .userInitiated) {
                    let search = try CommandRunner.run(
                        executableURL: tlmgr.url,
                        arguments: ["search", "--global", "--file", "/\(file)"],
                        searchDirectories: searchDirectories
                    )
                    guard search.status == 0,
                          let package = Self.packageName(fromSearchOutput: search.output) else {
                        throw RuntimeError.packageNotFound(file)
                    }
                    let install = try CommandRunner.run(
                        executableURL: tlmgr.url,
                        arguments: ["install", package],
                        searchDirectories: searchDirectories
                    )
                    guard install.status == 0 else {
                        throw RuntimeError.commandFailed(install.output)
                    }
                    return package
                }.value
                self.packageOperationMessage = "Installed \(package)."
                self.isInstallingPackage = false
                completion(true)
            } catch {
                self.packageOperationMessage = error.localizedDescription
                self.isInstallingPackage = false
                completion(false)
            }
        }
    }

    nonisolated static func packageName(fromSearchOutput output: String) -> String? {
        output.split(separator: "\n").lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                line.hasSuffix(":") && !line.contains("/") && line.count > 1
            }
            .map { String($0.dropLast()) }
    }

    private func performInstall(_ variant: RuntimeVariant) async {
        if manifest == nil { await loadManifest() }
        guard let manifest, let asset = asset(for: variant) else {
            installState = .failed(manifestError ?? RuntimeError.unsupportedArchitecture.localizedDescription)
            return
        }

        let fileManager = FileManager.default
        do {
            let base = try Self.runtimeBaseDirectory()
            try Self.checkDiskSpace(at: base, required: asset.installedSize + asset.compressedSize)
            let downloads = base.appendingPathComponent("Downloads", isDirectory: true)
            try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
            let archive = downloads.appendingPathComponent("\(UUID().uuidString).zip")
            defer { try? fileManager.removeItem(at: archive) }
            let client = RuntimeDownloadClient()
            downloadClient = client
            installState = .downloading(RuntimeDownloadProgress(
                receivedBytes: 0,
                totalBytes: asset.presentedCompressedSize,
                bytesPerSecond: 0
            ))
            let downloaded = try await client.download(
                from: asset.downloadURL,
                to: archive,
                expectedBytes: asset.presentedCompressedSize
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.installState = .downloading(progress)
                }
            }
            downloadClient = nil
            guard !Task.isCancelled else { throw CancellationError() }
            installState = .verifying
            let hash = try await Task.detached(priority: .userInitiated) {
                try RuntimeSecurity.sha256(of: downloaded)
            }.value
            guard hash.localizedCaseInsensitiveCompare(asset.sha256) == .orderedSame else {
                throw RuntimeError.invalidArchiveHash
            }
            installState = .installing
            let record = try await Task.detached(priority: .userInitiated) {
                try RuntimeInstallationService.install(
                    archiveURL: downloaded,
                    manifest: manifest,
                    asset: asset,
                    baseDirectory: base
                )
            }.value
            settings.managedRuntimeRecordPath = Self.recordURL(for: record).path
            settings.texProvider = .managed
            activeStatus = try ToolchainService.status(for: record)
            selectFirstAvailableEngineIfNeeded(in: activeStatus)
            installState = .ready(record)
        } catch is CancellationError {
            installState = .idle
        } catch {
            downloadClient = nil
            installState = .failed(error.localizedDescription)
        }
    }

    private func loadManagedRecord() -> ManagedRuntimeRecord? {
        guard let path = settings.managedRuntimeRecordPath else {
            debugLog("No managed runtime record path is configured.")
            return nil
        }
        let url = URL(fileURLWithPath: path)
        guard let record = Self.readRecord(at: url) else {
            debugLog("Could not decode managed runtime record at \(path).")
            settings.managedRuntimeRecordPath = nil
            return nil
        }
        guard FileManager.default.fileExists(atPath: record.rootPath) else {
            debugLog("Managed runtime root is missing at \(record.rootPath).")
            settings.managedRuntimeRecordPath = nil
            return nil
        }
        debugLog("Loaded managed runtime at \(record.rootPath).")
        return record
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LIGHTEX_RUNTIME_DEBUG"] == "1" {
            print("[LighTeX Runtime] \(message)")
        }
        #endif
    }

    private func selectFirstAvailableEngineIfNeeded(in status: ToolchainStatus) {
        if status.engines[settings.latexEngine] == nil,
           let first = LatexEngine.allCases.first(where: { status.engines[$0] != nil }) {
            settings.latexEngine = first
        }
        if settings.buildTool == .latexmk, status.latexmk == nil {
            settings.buildTool = .directCompiler
        }
    }

    private static func fetchData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func manifestErrorMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .badServerResponse, .fileDoesNotExist, .resourceUnavailable:
                return "The runtime catalog is unavailable on the release server. Publish runtime-latest or retry later."
            case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return "LighTex could not reach the runtime catalog. Check your internet connection and retry."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    nonisolated static func validate(_ manifest: RuntimeManifest) throws {
        guard manifest.schemaVersion == 1,
              !manifest.runtimeVersion.isEmpty,
              manifest.runtimeVersion.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
              !manifest.assets.isEmpty else {
            throw RuntimeError.invalidManifest
        }
        var ids = Set<String>()
        for asset in manifest.assets {
            guard ids.insert(asset.id).inserted,
                  asset.compressedSize > 0,
                  asset.installedSize > 0,
                  (asset.displayCompressedSize == nil || asset.presentedCompressedSize > 0),
                  asset.sha256.range(of: #"^[a-fA-F0-9]{64}$"#, options: .regularExpression) != nil else {
                throw RuntimeError.invalidManifest
            }
            let root = URL(fileURLWithPath: "/runtime", isDirectory: true)
            for tool in asset.tools.values {
                _ = try ToolchainService.safeToolURL(relativePath: tool, root: root)
            }
        }
    }

    static func runtimeBaseDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["LIGHTEX_RUNTIME_BASE_DIRECTORY"] {
            let base = URL(fileURLWithPath: override, isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return base
        }
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = applicationSupport
            .appendingPathComponent("LighTeX", isDirectory: true)
            .appendingPathComponent("Runtimes", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    nonisolated static func recordURL(for record: ManagedRuntimeRecord) -> URL {
        URL(fileURLWithPath: record.rootPath, isDirectory: true)
            .appendingPathComponent(".lightex-runtime.json")
    }

    nonisolated static func readRecord(at url: URL) -> ManagedRuntimeRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ManagedRuntimeRecord.self, from: data)
    }

    private static func checkDiskSpace(at url: URL, required: Int64) throws {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < required {
            throw RuntimeError.insufficientDiskSpace(required: required)
        }
    }
}

enum RuntimeInstallationService {
    static func install(
        archiveURL: URL,
        manifest: RuntimeManifest,
        asset: RuntimeAsset,
        baseDirectory: URL
    ) throws -> ManagedRuntimeRecord {
        let fileManager = FileManager.default
        let parent = baseDirectory
            .appendingPathComponent(manifest.runtimeVersion, isDirectory: true)
            .appendingPathComponent(asset.variant.rawValue, isDirectory: true)
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let target = parent.appendingPathComponent(asset.architecture.rawValue, isDirectory: true)
        let staging = baseDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let backup = baseDirectory.appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            let output = try CommandRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archiveURL.path, staging.path]
            )
            guard output.status == 0 else {
                throw RuntimeError.commandFailed(output.output)
            }
            let stagedRecord = ManagedRuntimeRecord(
                runtimeVersion: manifest.runtimeVersion,
                texLiveYear: manifest.texLiveYear,
                variant: asset.variant,
                architecture: asset.architecture,
                rootPath: staging.path,
                tools: asset.tools
            )
            let status = try ToolchainService.status(for: stagedRecord)
            for engine in LatexEngine.allCases where status.engines[engine] == nil {
                throw RuntimeError.missingTool(engine.executable)
            }
            guard status.latexmk != nil else { throw RuntimeError.missingTool("latexmk") }
            guard status.synctex != nil else { throw RuntimeError.missingTool("synctex") }
            guard status.tlmgr != nil else { throw RuntimeError.missingTool("tlmgr") }

            let record = ManagedRuntimeRecord(
                runtimeVersion: manifest.runtimeVersion,
                texLiveYear: manifest.texLiveYear,
                variant: asset.variant,
                architecture: asset.architecture,
                rootPath: target.path,
                tools: asset.tools
            )
            let data = try JSONEncoder().encode(record)
            try data.write(
                to: staging.appendingPathComponent(".lightex-runtime.json"),
                options: .atomic
            )

            if fileManager.fileExists(atPath: target.path) {
                try fileManager.moveItem(at: target, to: backup)
            }
            do {
                try fileManager.moveItem(at: staging, to: target)
            } catch {
                if fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.moveItem(at: backup, to: target)
                }
                throw error
            }
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.removeItem(at: backup)
            }
            return record
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }
}
