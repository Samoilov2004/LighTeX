import Foundation

struct BuildResult: Sendable {
    let succeeded: Bool
    let log: String
    let previewPDF: URL?
    let projectPDF: URL?
    let problems: [BuildProblem]
    let missingPackageFile: String?
}

enum LatexBuildService {
    static func build(
        projectURL: URL,
        entryFileURL: URL,
        configuration: BuildConfiguration
    ) async -> BuildResult {
        await Task.detached(priority: .userInitiated) {
            runBuild(
                projectURL: projectURL,
                entryFileURL: entryFileURL,
                configuration: configuration
            )
        }.value
    }

    static func cacheDirectory(projectURL: URL, entryFileURL: URL) throws -> URL {
        let buildsRoot: URL
        if let override = ProcessInfo.processInfo.environment["LIGHTEX_BUILD_CACHE_DIRECTORY"] {
            buildsRoot = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let caches = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            buildsRoot = caches
                .appendingPathComponent("LighTex", isDirectory: true)
                .appendingPathComponent("Builds", isDirectory: true)
        }
        let key = stableKey(projectURL.path + "|" + entryFileURL.path)
        let directory = buildsRoot.appendingPathComponent(key, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    static func stableKey(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func runBuild(
        projectURL: URL,
        entryFileURL: URL,
        configuration: BuildConfiguration
    ) -> BuildResult {
        let fileManager = FileManager.default
        let cacheURL: URL

        do {
            cacheURL = try cacheDirectory(
                projectURL: projectURL,
                entryFileURL: entryFileURL
            )
        } catch {
            return failure(
                "LighTex could not create its build cache.\n\(error.localizedDescription)",
                projectURL: projectURL
            )
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = configuration.executableURL
        process.arguments = arguments(
            configuration: configuration,
            cacheURL: cacheURL,
            entryFileURL: entryFileURL
        )
        process.currentDirectoryURL = entryFileURL.deletingLastPathComponent()
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = buildEnvironment(searchDirectories: configuration.searchDirectories)

        do {
            try process.run()
        } catch {
            return failure(
                """
                LighTex could not start the LaTeX compiler.

                Open Settings → LaTeX and verify the selected runtime.
                \(error.localizedDescription)
                """,
                projectURL: projectURL
            )
        }

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var output = String(data: outputData, encoding: .utf8) ?? "No compiler output."
        let cachedPDF = cacheURL
            .appendingPathComponent(entryFileURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("pdf")

        guard process.terminationStatus == 0,
              fileManager.fileExists(atPath: cachedPDF.path) else {
            if process.terminationStatus == 127 || output.contains("No such file or directory") {
                let tool = configuration.tool == .latexmk
                    ? "latexmk"
                    : configuration.engine.executable
                output = """
                LighTex could not find \(tool).

                Install a LighTeX Runtime or choose another engine in Settings → LaTeX.

                \(output)
                """
            }
            return failure(output, projectURL: projectURL)
        }

        let projectPDF = entryFileURL
            .deletingPathExtension()
            .appendingPathExtension("pdf")

        do {
            let temporaryPDF = entryFileURL
                .deletingLastPathComponent()
                .appendingPathComponent(".lightex-\(UUID().uuidString).pdf")
            try fileManager.copyItem(at: cachedPDF, to: temporaryPDF)

            if fileManager.fileExists(atPath: projectPDF.path) {
                _ = try fileManager.replaceItemAt(projectPDF, withItemAt: temporaryPDF)
            } else {
                try fileManager.moveItem(at: temporaryPDF, to: projectPDF)
            }
        } catch {
            return BuildResult(
                succeeded: false,
                log: output + "\n\nThe PDF compiled, but LighTex could not copy it into the project:\n"
                    + error.localizedDescription,
                previewPDF: cachedPDF,
                projectPDF: nil,
                problems: BuildProblemParser.parse(output, projectURL: projectURL),
                missingPackageFile: Self.missingPackageFile(in: output)
            )
        }

        return BuildResult(
            succeeded: true,
            log: output,
            previewPDF: cachedPDF,
            projectPDF: projectPDF,
            problems: BuildProblemParser.parse(output, projectURL: projectURL),
            missingPackageFile: nil
        )
    }

    private static func arguments(
        configuration: BuildConfiguration,
        cacheURL: URL,
        entryFileURL: URL
    ) -> [String] {
        let common = [
            "-interaction=nonstopmode",
            "-halt-on-error",
            "-file-line-error",
            "-synctex=1",
            "-output-directory=\(cacheURL.path)",
            entryFileURL.lastPathComponent
        ]

        switch configuration.tool {
        case .latexmk:
            return [configuration.engine.latexmkFlag] + common
        case .directCompiler:
            return common
        }
    }

    private static func buildEnvironment(searchDirectories: [URL]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/Library/TeX/texbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")
        environment["PATH"] = [
            searchDirectories.map(\.path).joined(separator: ":"),
            environment["PATH"],
            fallbackPath
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        return environment
    }

    private static func failure(_ log: String, projectURL: URL) -> BuildResult {
        BuildResult(
            succeeded: false,
            log: log,
            previewPDF: nil,
            projectPDF: nil,
            problems: BuildProblemParser.parse(log, projectURL: projectURL),
            missingPackageFile: missingPackageFile(in: log)
        )
    }

    static func missingPackageFile(in log: String) -> String? {
        let patterns = [
            #"File [`']([^`']+\.(?:sty|cls|def|fd|bst))[`'] not found"#,
            #"I can't find file [`']([^`']+)[`']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(log.startIndex..<log.endIndex, in: log)
            guard let match = regex.firstMatch(in: log, range: range),
                  let fileRange = Range(match.range(at: 1), in: log) else {
                continue
            }
            return String(log[fileRange])
        }
        return nil
    }
}

enum BuildProblemParser {
    static func groups(
        from problems: [BuildProblem],
        missingPackageFile: String?
    ) -> [BuildDiagnosticGroup] {
        let errors = problems.filter { $0.severity == .error }
        let warnings = problems.filter { $0.severity == .warning }
        var groups: [BuildDiagnosticGroup] = []

        if let primary = errors.first {
            groups.append(BuildDiagnosticGroup(
                primary: primary,
                related: Array(errors.dropFirst())
            ))
        } else if let missingPackageFile {
            groups.append(BuildDiagnosticGroup(
                primary: BuildProblem(
                    severity: .error,
                    fileURL: nil,
                    fileDisplayName: "Build",
                    line: nil,
                    message: "The package providing \(missingPackageFile) is not installed."
                ),
                related: []
            ))
        }

        groups.append(contentsOf: warnings.map {
            BuildDiagnosticGroup(primary: $0, related: [])
        })
        return groups
    }

    static func parse(_ log: String, projectURL: URL) -> [BuildProblem] {
        var problems: [BuildProblem] = []
        var seen: Set<String> = []

        for rawLine in log.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let match = fileLineMatch(in: line) {
                let filePath = match.file
                let url = URL(fileURLWithPath: filePath, relativeTo: projectURL)
                    .standardizedFileURL
                let severity: BuildProblem.Severity = line.localizedCaseInsensitiveContains("warning")
                    ? .warning
                    : .error
                let key = "\(url.path):\(match.line):\(match.message)"
                guard seen.insert(key).inserted else { continue }
                problems.append(BuildProblem(
                    severity: severity,
                    fileURL: url,
                    fileDisplayName: url.lastPathComponent,
                    line: match.line,
                    message: cleanedMessage(match.message)
                ))
            } else if line.hasPrefix("!") {
                let message = cleanedMessage(String(line.dropFirst()))
                guard seen.insert(message).inserted else { continue }
                problems.append(BuildProblem(
                    severity: .error,
                    fileURL: nil,
                    fileDisplayName: "Build",
                    line: nil,
                    message: message
                ))
            }
        }

        if problems.isEmpty,
           log.localizedCaseInsensitiveContains("could not find") {
            problems.append(BuildProblem(
                severity: .error,
                fileURL: nil,
                fileDisplayName: "Compiler",
                line: nil,
                message: "LaTeX compiler not found. Check Settings → LaTeX."
            ))
        }
        return problems
    }

    private static func fileLineMatch(in line: String) -> (file: String, line: Int, message: String)? {
        let pattern = #"^(.+?\.(?:tex|sty|cls|bib)):(\d+):\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let result = regex.firstMatch(in: line, range: range),
              let fileRange = Range(result.range(at: 1), in: line),
              let lineRange = Range(result.range(at: 2), in: line),
              let messageRange = Range(result.range(at: 3), in: line),
              let lineNumber = Int(line[lineRange]) else {
            return nil
        }
        return (
            String(line[fileRange]),
            lineNumber,
            String(line[messageRange])
        )
    }

    private static func cleanedMessage(_ message: String) -> String {
        message
            .replacingOccurrences(of: "LaTeX Error:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
