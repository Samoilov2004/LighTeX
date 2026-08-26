import Foundation
import SwiftUI
import CryptoKit

enum LatexEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case pdfLaTeX
    case xeLaTeX
    case luaLaTeX

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdfLaTeX: "pdfLaTeX"
        case .xeLaTeX: "XeLaTeX"
        case .luaLaTeX: "LuaLaTeX"
        }
    }

    var executable: String {
        switch self {
        case .pdfLaTeX: "pdflatex"
        case .xeLaTeX: "xelatex"
        case .luaLaTeX: "lualatex"
        }
    }

    var latexmkFlag: String {
        switch self {
        case .pdfLaTeX: "-pdf"
        case .xeLaTeX: "-xelatex"
        case .luaLaTeX: "-lualatex"
        }
    }
}

enum BuildTool: String, Codable, CaseIterable, Identifiable, Sendable {
    case latexmk
    case directCompiler

    var id: String { rawValue }

    var label: String {
        switch self {
        case .latexmk: "latexmk"
        case .directCompiler: "Direct compiler"
        }
    }
}

struct BuildConfiguration: Sendable {
    let engine: LatexEngine
    let tool: BuildTool
    let executableURL: URL
    let searchDirectories: [URL]
}

struct RecentProject: Codable, Hashable, Identifiable {
    let path: String
    var lastOpened: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var name: String { url.lastPathComponent }

    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

struct DocumentOutlineItem: Identifiable, Hashable, Sendable {
    let fileURL: URL
    let line: Int
    let title: String
    let level: Int

    var id: String { "\(fileURL.path)#\(line)#\(title)" }
}

struct PDFJumpTarget: Equatable, Sendable {
    let page: Int
    let x: Double?
    let yFromTop: Double?
}

struct PDFSourceTarget: Equatable, Sendable {
    let fileURL: URL
    let line: Int
    let column: Int
}

struct DocumentRevision: Equatable, Sendable {
    let modificationDate: Date?
    let fileSize: Int64
    let fileIdentifier: String?
    let contentHash: String

    static func read(from url: URL) throws -> (revision: DocumentRevision, text: String) {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return (try make(for: url, data: data), text)
    }

    static func make(for url: URL, text: String) throws -> DocumentRevision {
        try make(for: url, data: Data(text.utf8))
    }

    static func fileIdentifier(for url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey])
        return values?.fileResourceIdentifier.map { String(describing: $0) }
    }

    private static func make(for url: URL, data: Data) throws -> DocumentRevision {
        let values = try url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
            .fileResourceIdentifierKey
        ])
        return DocumentRevision(
            modificationDate: values.contentModificationDate,
            fileSize: Int64(values.fileSize ?? data.count),
            fileIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }
}

enum ExternalChangeState: Equatable, Sendable {
    case none
    case modified
    case deleted
}

enum DocumentSaveResult: Equatable, Sendable {
    case notNeeded
    case saved
    case failed(String)

    var succeeded: Bool {
        switch self {
        case .notNeeded, .saved: true
        case .failed: false
        }
    }
}

enum CloseRequestKind: Equatable, Sendable {
    case document(URL)
    case project
    case switchProject(URL)
    case application
}

struct CloseRequest: Equatable, Sendable {
    let kind: CloseRequestKind
    let documentNames: [String]
}

enum CloseDecision: Equatable, Sendable {
    case save
    case discard
    case cancel
}

struct EditorDocument: Identifiable, Equatable, Sendable {
    var url: URL
    var text: String
    var isDirty: Bool
    var jumpLine: Int?
    var jumpToken: Int
    var revision: DocumentRevision
    var externalChangeState: ExternalChangeState = .none

    var id: URL { url }
    var displayName: String { url.lastPathComponent }
}

struct BuildProblem: Identifiable, Hashable, Sendable {
    enum Severity: String, Sendable {
        case error
        case warning

        var symbol: String {
            switch self {
            case .error: "xmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .error: .red
            case .warning: .orange
            }
        }
    }

    let severity: Severity
    let fileURL: URL?
    let fileDisplayName: String
    let line: Int?
    let message: String

    var id: String {
        "\(severity.rawValue)|\(fileURL?.path ?? fileDisplayName)|\(line ?? 0)|\(message)"
    }

    static func == (lhs: BuildProblem, rhs: BuildProblem) -> Bool {
        lhs.severity == rhs.severity
            && lhs.fileURL == rhs.fileURL
            && lhs.line == rhs.line
            && lhs.message == rhs.message
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(severity)
        hasher.combine(fileURL)
        hasher.combine(line)
        hasher.combine(message)
    }
}

struct BuildDiagnosticGroup: Identifiable, Equatable, Sendable {
    let primary: BuildProblem
    let related: [BuildProblem]

    var id: String { primary.id }
}

enum ProblemsPanelTab: String, CaseIterable, Identifiable {
    case problems = "Problems"
    case log = "Log"

    var id: String { rawValue }
}

enum BuildState: Equatable {
    case idle
    case building
    case success
    case failure

    var label: String {
        switch self {
        case .idle: "Ready"
        case .building: "Building…"
        case .success: "Build succeeded"
        case .failure: "Build failed"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "circle"
        case .building: "arrow.triangle.2.circlepath"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: .secondary
        case .building: .secondary
        case .success: .green
        case .failure: .red
        }
    }
}
