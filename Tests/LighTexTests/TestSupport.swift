import Foundation
@testable import LighTex

func scannerFindsExpectedFilesAndMain() throws -> Bool {
    let root = try makeFixtureProject()
    defer { try? FileManager.default.removeItem(at: root) }
    let tree = ProjectScanner.projectTree(in: root)
    let texFiles = ProjectScanner.texFiles(in: root)
    return !tree.isEmpty
        && texFiles.count == 2
        && ProjectScanner.preferredEntryPoint(from: texFiles)?.lastPathComponent == "main.tex"
}

func scannerIgnoresBuildDirectory() throws -> Bool {
    let root = try makeFixtureProject()
    defer { try? FileManager.default.removeItem(at: root) }
    return !ProjectScanner.texFiles(in: root).contains {
        $0.path.contains("/build/")
    }
}

func parserFindsFileLineAndMessage() -> Bool {
    let root = URL(fileURLWithPath: "/tmp/LighTexParser")
    let log = "main.tex:42: Undefined control sequence"
    let problems = BuildProblemParser.parse(log, projectURL: root)
    return problems.count == 1
        && problems[0].fileDisplayName == "main.tex"
        && problems[0].line == 42
        && problems[0].message == "Undefined control sequence"
}

func cacheKeyIsStableAndDistinct() -> Bool {
    LatexBuildService.stableKey("project") == LatexBuildService.stableKey("project")
        && LatexBuildService.stableKey("project") != LatexBuildService.stableKey("other")
}

func latexBuildProducesPDF() async throws -> Bool {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let entry = root.appendingPathComponent("main.tex")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try """
    \\documentclass{article}
    \\begin{document}
    LighTex smoke test.
    \\end{document}
    """.write(to: entry, atomically: true, encoding: .utf8)

    let cache = try? LatexBuildService.cacheDirectory(
        projectURL: root,
        entryFileURL: entry
    )
    defer {
        try? FileManager.default.removeItem(at: root)
        if let cache { try? FileManager.default.removeItem(at: cache) }
    }

    let status = ToolchainService.detectSystemSynchronously(
        environment: ProcessInfo.processInfo.environment
    )
    let configuration = try ToolchainService.buildConfiguration(
        status: status,
        engine: .pdfLaTeX,
        tool: .latexmk
    )
    let result = await LatexBuildService.build(
        projectURL: root,
        entryFileURL: entry,
        configuration: configuration
    )
    return result.succeeded
        && result.previewPDF != nil
        && FileManager.default.fileExists(
            atPath: entry.deletingPathExtension().appendingPathExtension("pdf").path
        )
}

private func makeFixtureProject() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("sections"),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("build"),
        withIntermediateDirectories: true
    )
    try "\\documentclass{article}".write(
        to: root.appendingPathComponent("main.tex"),
        atomically: true,
        encoding: .utf8
    )
    try "Introduction".write(
        to: root.appendingPathComponent("sections/introduction.tex"),
        atomically: true,
        encoding: .utf8
    )
    try "ignored".write(
        to: root.appendingPathComponent("build/generated.tex"),
        atomically: true,
        encoding: .utf8
    )
    return root
}
