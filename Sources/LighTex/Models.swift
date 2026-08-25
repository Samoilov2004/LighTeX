import Foundation
import SwiftUI

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

struct EditorDocument: Identifiable, Equatable {
    let url: URL
    var text: String
    var isDirty: Bool
    var jumpLine: Int?
    var jumpToken: Int

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

    let id = UUID()
    let severity: Severity
    let fileURL: URL?
    let fileDisplayName: String
    let line: Int?
    let message: String

    static func == (lhs: BuildProblem, rhs: BuildProblem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
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
