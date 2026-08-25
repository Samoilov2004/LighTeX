import Foundation

enum SyncTeXService {
    static func target(
        forSource sourceURL: URL,
        line: Int,
        previewPDFURL: URL,
        projectURL: URL,
        executableURL: URL?
    ) async -> PDFJumpTarget? {
        guard let executableURL else { return nil }
        return await Task.detached(priority: .userInitiated) {
            resolveTarget(
                forSource: sourceURL,
                line: line,
                previewPDFURL: previewPDFURL,
                projectURL: projectURL,
                executableURL: executableURL
            )
        }.value
    }

    private static func resolveTarget(
        forSource sourceURL: URL,
        line: Int,
        previewPDFURL: URL,
        projectURL: URL,
        executableURL: URL
    ) -> PDFJumpTarget? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = [
            "view",
            "-i", "\(max(1, line)):1:\(sourceURL.path)",
            "-o", previewPDFURL.path
        ]
        process.currentDirectoryURL = projectURL
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = environment()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        return target(from: output)
    }

    static func target(from output: String) -> PDFJumpTarget? {
        var page: Int?
        var x: Double?
        var y: Double?

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if page == nil,
               line.hasPrefix("Page:"),
               let parsedPage = Int(line.dropFirst("Page:".count)),
               parsedPage > 0 {
                page = parsedPage
            } else if page != nil, x == nil, line.hasPrefix("x:") {
                x = Double(line.dropFirst(2))
            } else if page != nil, y == nil, line.hasPrefix("y:") {
                y = Double(line.dropFirst(2))
            }

            if let page, x != nil, y != nil {
                return PDFJumpTarget(page: page, x: x, yFromTop: y)
            }
        }
        return page.map { PDFJumpTarget(page: $0, x: x, yFromTop: y) }
    }

    private static func environment() -> [String: String] {
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
        environment["PATH"] = [environment["PATH"], fallbackPath]
            .compactMap { $0 }
            .joined(separator: ":")
        return environment
    }
}
