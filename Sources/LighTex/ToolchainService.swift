import Foundation

enum ToolchainService {
    private static let knownDirectories = [
        "/Library/TeX/texbin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin"
    ]

    static func detectSystem() async -> ToolchainStatus {
        await Task.detached(priority: .utility) {
            detectSystemSynchronously(environment: ProcessInfo.processInfo.environment)
        }.value
    }

    static func detectSystemSynchronously(environment: [String: String]) -> ToolchainStatus {
        if environment["LIGHTEX_SIMULATE_NO_SYSTEM_TEX"] == "1" {
            return .empty
        }
        var directories = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        directories.append(contentsOf: knownDirectories)
        let uniqueDirectories = Array(NSOrderedSet(array: directories)).compactMap { $0 as? String }

        func status(_ name: String) -> ToolExecutableStatus? {
            for directory in uniqueDirectories {
                guard let url = executable(named: name, directories: [directory]),
                      let version = firstVersionLine(executableURL: url) else { continue }
                return ToolExecutableStatus(url: url, version: version)
            }
            return nil
        }

        var engines: [LatexEngine: ToolExecutableStatus] = [:]
        for engine in LatexEngine.allCases {
            engines[engine] = status(engine.executable)
        }
        return ToolchainStatus(
            engines: engines,
            latexmk: status("latexmk"),
            synctex: status("synctex"),
            tlmgr: status("tlmgr")
        )
    }

    static func status(for record: ManagedRuntimeRecord) throws -> ToolchainStatus {
        let root = URL(fileURLWithPath: record.rootPath, isDirectory: true).standardizedFileURL

        func tool(_ name: String) throws -> ToolExecutableStatus? {
            guard let relativePath = record.tools[name] else { return nil }
            let url = try safeToolURL(relativePath: relativePath, root: root)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw RuntimeError.missingTool(name)
            }
            return ToolExecutableStatus(url: url, version: firstVersionLine(executableURL: url))
        }

        var engines: [LatexEngine: ToolExecutableStatus] = [:]
        for engine in LatexEngine.allCases {
            if let executable = try tool(engine.executable) {
                engines[engine] = executable
            }
        }
        return ToolchainStatus(
            engines: engines,
            latexmk: try tool("latexmk"),
            synctex: try tool("synctex"),
            tlmgr: try tool("tlmgr")
        )
    }

    static func buildConfiguration(
        status: ToolchainStatus,
        engine: LatexEngine,
        tool: BuildTool
    ) throws -> BuildConfiguration {
        guard let engineStatus = status.engines[engine] else {
            throw RuntimeError.missingEngine(engine.label)
        }
        let executable: URL
        switch tool {
        case .latexmk:
            guard let latexmk = status.latexmk else {
                throw RuntimeError.missingBuildTool("latexmk")
            }
            executable = latexmk.url
        case .directCompiler:
            executable = engineStatus.url
        }
        let directories = Set(
            status.engines.values.map { $0.url.deletingLastPathComponent() }
                + [status.latexmk, status.synctex, status.tlmgr]
                    .compactMap { $0?.url.deletingLastPathComponent() }
        )
        return BuildConfiguration(
            engine: engine,
            tool: tool,
            executableURL: executable,
            searchDirectories: Array(directories)
        )
    }

    static func safeToolURL(relativePath: String, root: URL) throws -> URL {
        guard !relativePath.hasPrefix("/") else {
            throw RuntimeError.invalidToolPath(relativePath)
        }
        let rootPath = root.standardizedFileURL.path + "/"
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(rootPath) else {
            throw RuntimeError.invalidToolPath(relativePath)
        }
        return candidate
    }

    private static func executable(named name: String, directories: [String]) -> URL? {
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(name)
                .resolvingSymlinksInPath()
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func firstVersionLine(executableURL: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = executableURL.lastPathComponent == "latexmk" ? ["-v"] : ["--version"]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?
                .split(separator: "\n", maxSplits: 1)
                .first
                .map(String.init)
        } catch {
            return nil
        }
    }
}

struct CommandOutput: Sendable {
    let status: Int32
    let output: String
}

enum CommandRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        searchDirectories: [URL] = []
    ) throws -> CommandOutput {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = pipe
        process.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (searchDirectories.map(\.path) + [existingPath]).joined(separator: ":")
        process.environment = environment
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandOutput(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}
