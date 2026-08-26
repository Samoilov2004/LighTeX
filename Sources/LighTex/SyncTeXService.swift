import Foundation

enum SyncTeXService {
    static func sourceTarget(
        forPDF previewPDFURL: URL,
        page: Int,
        x: Double,
        yFromTop: Double,
        projectURL: URL,
        executableURL: URL?
    ) async -> PDFSourceTarget? {
        guard let executableURL else { return nil }
        return await Task.detached(priority: .userInitiated) {
            resolveSourceTarget(
                previewPDFURL: previewPDFURL,
                page: page,
                x: x,
                yFromTop: yFromTop,
                projectURL: projectURL,
                executableURL: executableURL
            )
        }.value
    }

    static func target(
        forSource sourceURL: URL,
        line: Int,
        column: Int = 1,
        previewPDFURL: URL,
        projectURL: URL,
        executableURL: URL?
    ) async -> PDFJumpTarget? {
        guard let executableURL else { return nil }
        return await Task.detached(priority: .userInitiated) {
            resolveTarget(
                forSource: sourceURL,
                line: line,
                column: column,
                previewPDFURL: previewPDFURL,
                projectURL: projectURL,
                executableURL: executableURL
            )
        }.value
    }

    private static func resolveTarget(
        forSource sourceURL: URL,
        line: Int,
        column: Int,
        previewPDFURL: URL,
        projectURL: URL,
        executableURL: URL
    ) -> PDFJumpTarget? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = [
            "view",
            "-i", sourcePositionArgument(sourceURL: sourceURL, line: line, column: column),
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

    static func sourcePositionArgument(sourceURL: URL, line: Int, column: Int) -> String {
        "\(max(1, line)):\(max(1, column)):\(sourceURL.path)"
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

    static func editPositionArgument(
        previewPDFURL: URL,
        page: Int,
        x: Double,
        yFromTop: Double
    ) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        let xValue = String(format: "%.3f", locale: locale, x)
        let yValue = String(format: "%.3f", locale: locale, yFromTop)
        return "\(max(1, page)):\(xValue):\(yValue):\(previewPDFURL.path)"
    }

    static func sourceTarget(from output: String, projectURL: URL) -> PDFSourceTarget? {
        var input: String?
        var line: Int?
        var column: Int?
        for rawLine in output.components(separatedBy: .newlines) {
            let value = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("Input:") {
                input = String(value.dropFirst("Input:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if value.hasPrefix("Line:") {
                line = Int(value.dropFirst("Line:".count))
            } else if value.hasPrefix("Column:") {
                column = Int(value.dropFirst("Column:".count))
            }
        }
        guard let input, let line, line >= 0 else { return nil }
        let inputURL = URL(fileURLWithPath: input, relativeTo: projectURL).standardizedFileURL
        return PDFSourceTarget(
            fileURL: inputURL,
            line: max(1, line),
            column: max(1, (column ?? 0) + ((column ?? -1) >= 0 ? 1 : 0))
        )
    }

    private static func resolveSourceTarget(
        previewPDFURL: URL,
        page: Int,
        x: Double,
        yFromTop: Double,
        projectURL: URL,
        executableURL: URL
    ) -> PDFSourceTarget? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = [
            "edit",
            "-o",
            editPositionArgument(
                previewPDFURL: previewPDFURL,
                page: page,
                x: x,
                yFromTop: yFromTop
            )
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
              let output = String(data: data, encoding: .utf8) else { return nil }
        return sourceTarget(from: output, projectURL: projectURL)
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
