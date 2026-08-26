import Foundation

enum ProjectTemplateOrigin: String, Codable, Sendable {
    case builtIn
    case user
}

enum TemplatePreviewStyle: String, Codable, Sendable {
    case article
    case mathematics
    case textbook
    case presentation
}

struct TemplateBlueprint: Equatable, Sendable {
    let files: [String: String]
    let directories: [String]
}

struct ProjectTemplate: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let summary: String
    let origin: ProjectTemplateOrigin
    let runtimeRequirement: String
    let entryFile: String
    let previewStyle: TemplatePreviewStyle
    let createdAt: Date?
    let userDirectory: URL?
    let blueprint: TemplateBlueprint?

    var isUserTemplate: Bool { origin == .user }
}

struct TemplateSourceDraft: Identifiable, Equatable {
    let sourceURL: URL
    let suggestedName: String

    var id: String { sourceURL.standardizedFileURL.path }
}

enum ProjectTemplateError: LocalizedError {
    case invalidName
    case destinationExists(String)
    case noLatexSource
    case invalidTemplate
    case unsafeTemplateLocation

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Enter a valid name without path separators."
        case let .destinationExists(name):
            return "A folder named \(name) already exists in this location."
        case .noLatexSource:
            return "The selected folder does not contain a LaTeX source file."
        case .invalidTemplate:
            return "The template is incomplete or could not be read."
        case .unsafeTemplateLocation:
            return "The selected folder is not a safe location for this template operation."
        }
    }
}

private struct UserTemplateManifest: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let summary: String
    let createdAt: Date
    let entryFile: String
    let previewStyle: TemplatePreviewStyle
}

final class ProjectTemplateStore {
    static let personalTemplateFolderName = "Yours"

    let userTemplatesDirectory: URL

    init(userTemplatesDirectory: URL = ProjectTemplateStore.defaultUserTemplatesDirectory()) {
        self.userTemplatesDirectory = userTemplatesDirectory.standardizedFileURL
    }

    static func defaultUserTemplatesDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("LighTeX", isDirectory: true)
            .appendingPathComponent("Templates", isDirectory: true)
            .appendingPathComponent(personalTemplateFolderName, isDirectory: true)
    }

    func loadUserTemplates() -> [ProjectTemplate] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: userTemplatesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return directories.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
                  let manifest = try? decoder.decode(UserTemplateManifest.self, from: data),
                  manifest.schemaVersion == 1,
                  FileManager.default.fileExists(
                    atPath: directory
                        .appendingPathComponent("files", isDirectory: true)
                        .appendingPathComponent(manifest.entryFile)
                        .path
                  ) else {
                return nil
            }
            return ProjectTemplate(
                id: manifest.id,
                name: manifest.name,
                summary: manifest.summary.isEmpty ? "A personal project template." : manifest.summary,
                origin: .user,
                runtimeRequirement: "Project dependent",
                entryFile: manifest.entryFile,
                previewStyle: manifest.previewStyle,
                createdAt: manifest.createdAt,
                userDirectory: directory,
                blueprint: nil
            )
        }
        .sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }

    func saveUserTemplate(
        from sourceURL: URL,
        name: String,
        summary: String
    ) throws -> ProjectTemplate {
        let cleanName = try Self.validatedName(name)
        let source = sourceURL.standardizedFileURL
        guard (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw ProjectTemplateError.invalidTemplate
        }
        let sourcePath = Self.canonicalPath(source)
        let libraryPath = Self.canonicalPath(userTemplatesDirectory)
        guard sourcePath != libraryPath,
              !libraryPath.hasPrefix(sourcePath + "/"),
              !sourcePath.hasPrefix(libraryPath + "/") else {
            throw ProjectTemplateError.unsafeTemplateLocation
        }

        try FileManager.default.createDirectory(
            at: userTemplatesDirectory,
            withIntermediateDirectories: true
        )
        let id = UUID().uuidString.lowercased()
        let finalDirectory = userTemplatesDirectory.appendingPathComponent(id, isDirectory: true)
        let stagingDirectory = userTemplatesDirectory.appendingPathComponent(".\(id).staging", isDirectory: true)
        let filesDirectory = stagingDirectory.appendingPathComponent("files", isDirectory: true)
        try? FileManager.default.removeItem(at: stagingDirectory)

        do {
            try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
            try copyProjectContents(from: source, to: filesDirectory)
            guard let entryFile = try detectEntryFile(in: filesDirectory) else {
                throw ProjectTemplateError.noLatexSource
            }
            let previewStyle = try detectPreviewStyle(
                in: filesDirectory.appendingPathComponent(entryFile)
            )
            let manifest = UserTemplateManifest(
                schemaVersion: 1,
                id: id,
                name: cleanName,
                summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: Date(),
                entryFile: entryFile,
                previewStyle: previewStyle
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(manifest).write(
                to: stagingDirectory.appendingPathComponent("manifest.json"),
                options: .atomic
            )
            try FileManager.default.moveItem(at: stagingDirectory, to: finalDirectory)
        } catch {
            try? FileManager.default.removeItem(at: stagingDirectory)
            throw error
        }

        guard let template = loadUserTemplates().first(where: { $0.id == id }) else {
            throw ProjectTemplateError.invalidTemplate
        }
        return template
    }

    func instantiate(
        template: ProjectTemplate,
        projectName: String,
        author: String,
        location: URL
    ) throws -> URL {
        let cleanName = try Self.validatedName(projectName)
        let destination = location
            .standardizedFileURL
            .appendingPathComponent(cleanName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ProjectTemplateError.destinationExists(cleanName)
        }

        let staging = location
            .standardizedFileURL
            .appendingPathComponent(".\(cleanName).lightex-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            switch template.origin {
            case .builtIn:
                guard let blueprint = template.blueprint else {
                    throw ProjectTemplateError.invalidTemplate
                }
                for directory in blueprint.directories {
                    try FileManager.default.createDirectory(
                        at: staging.appendingPathComponent(directory, isDirectory: true),
                        withIntermediateDirectories: true
                    )
                }
                for (relativePath, contents) in blueprint.files {
                    let fileURL = staging.appendingPathComponent(relativePath)
                    try FileManager.default.createDirectory(
                        at: fileURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            case .user:
                guard let sourceDirectory = template.userDirectory?
                    .appendingPathComponent("files", isDirectory: true),
                      FileManager.default.fileExists(atPath: sourceDirectory.path) else {
                    throw ProjectTemplateError.invalidTemplate
                }
                let sourcePath = Self.canonicalPath(sourceDirectory)
                let stagingPath = Self.canonicalPath(staging)
                guard !stagingPath.hasPrefix(sourcePath + "/") else {
                    throw ProjectTemplateError.unsafeTemplateLocation
                }
                try copyProjectContents(from: sourceDirectory, to: staging, applyingExclusions: false)
            }

            try renderPlaceholders(
                in: staging,
                projectName: cleanName,
                author: author.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard FileManager.default.fileExists(
                atPath: staging.appendingPathComponent(template.entryFile).path
            ) else {
                throw ProjectTemplateError.invalidTemplate
            }
            try FileManager.default.moveItem(at: staging, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    func deleteUserTemplate(_ template: ProjectTemplate) throws {
        guard template.isUserTemplate, let directory = template.userDirectory else {
            throw ProjectTemplateError.invalidTemplate
        }
        let parentPath = URL(fileURLWithPath: directory.path)
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .path
        let libraryPath = userTemplatesDirectory.resolvingSymlinksInPath().path
        guard parentPath == libraryPath else {
            throw ProjectTemplateError.unsafeTemplateLocation
        }
        try FileManager.default.removeItem(at: directory)
    }

    private func copyProjectContents(
        from source: URL,
        to destination: URL,
        applyingExclusions: Bool = true
    ) throws {
        let sourceChildren = try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        let texBasenames = Set(sourceChildren.compactMap { url in
            url.pathExtension.lowercased() == "tex"
                ? url.deletingPathExtension().lastPathComponent.lowercased()
                : nil
        })

        for sourceItem in sourceChildren {
            let values = try sourceItem.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            if applyingExclusions,
               shouldExclude(sourceItem, isDirectory: values.isDirectory == true, texBasenames: texBasenames) {
                continue
            }

            let destinationItem = destination.appendingPathComponent(
                sourceItem.lastPathComponent,
                isDirectory: values.isDirectory == true
            )
            if values.isDirectory == true {
                try FileManager.default.createDirectory(at: destinationItem, withIntermediateDirectories: true)
                try copyProjectContents(
                    from: sourceItem,
                    to: destinationItem,
                    applyingExclusions: applyingExclusions
                )
            } else {
                try FileManager.default.copyItem(at: sourceItem, to: destinationItem)
            }
        }
    }

    private func shouldExclude(_ url: URL, isDirectory: Bool, texBasenames: Set<String>) -> Bool {
        let name = url.lastPathComponent
        let lowerName = name.lowercased()
        if isDirectory {
            return [".git", ".build", "build", "dist", ".lightex"].contains(lowerName)
        }
        if lowerName == ".ds_store" || lowerName.hasSuffix(".synctex.gz") {
            return true
        }
        let excludedExtensions: Set<String> = [
            "aux", "log", "out", "toc", "fls", "fdb_latexmk", "bbl", "blg",
            "nav", "snm", "vrb", "lof", "lot"
        ]
        if excludedExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }
        return url.pathExtension.lowercased() == "pdf"
            && texBasenames.contains(url.deletingPathExtension().lastPathComponent.lowercased())
    }

    private func detectEntryFile(in root: URL) throws -> String? {
        let texFiles = try relativeFiles(in: root).filter {
            URL(fileURLWithPath: $0).pathExtension.lowercased() == "tex"
        }
        if texFiles.contains("main.tex") { return "main.tex" }
        for relativePath in texFiles.sorted(by: { $0.count < $1.count }) {
            let contents = try? String(
                contentsOf: root.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            if contents?.contains("\\documentclass") == true {
                return relativePath
            }
        }
        return texFiles.sorted().first
    }

    private func detectPreviewStyle(in entryFile: URL) throws -> TemplatePreviewStyle {
        let contents = try String(contentsOf: entryFile, encoding: .utf8).lowercased()
        if contents.contains("{beamer}") { return .presentation }
        if contents.contains("{book}") || contents.contains("\\chapter") { return .textbook }
        if contents.contains("\\newtheorem") || contents.contains("\\begin{theorem}") {
            return .mathematics
        }
        return .article
    }

    private func relativeFiles(in root: URL) throws -> [String] {
        let rootComponents = root.standardizedFileURL.pathComponents
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            let relativeComponents = url.standardizedFileURL.pathComponents
                .dropFirst(rootComponents.count)
            guard !relativeComponents.isEmpty else { return nil }
            return relativeComponents.joined(separator: "/")
        }
    }

    private func renderPlaceholders(
        in root: URL,
        projectName: String,
        author: String
    ) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        let date = formatter.string(from: Date())
        let textExtensions: Set<String> = [
            "tex", "bib", "cls", "sty", "md", "txt", "json", "yaml", "yml"
        ]

        for relativePath in try relativeFiles(in: root) {
            let fileURL = root.appendingPathComponent(relativePath)
            guard textExtensions.contains(fileURL.pathExtension.lowercased()),
                  var contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            let isLatex = ["tex", "bib", "cls", "sty"].contains(fileURL.pathExtension.lowercased())
            contents = contents
                .replacingOccurrences(
                    of: "${PROJECT_NAME}",
                    with: isLatex ? Self.latexEscaped(projectName) : projectName
                )
                .replacingOccurrences(
                    of: "${AUTHOR}",
                    with: isLatex ? Self.latexEscaped(author) : author
                )
                .replacingOccurrences(of: "${DATE}", with: date)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains(":") else {
            throw ProjectTemplateError.invalidName
        }
        return trimmed
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func latexEscaped(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            switch character {
            case "\\": result += "\\textbackslash{}"
            case "{": result += "\\{"
            case "}": result += "\\}"
            case "#": result += "\\#"
            case "$": result += "\\$"
            case "%": result += "\\%"
            case "&": result += "\\&"
            case "_": result += "\\_"
            case "^": result += "\\textasciicircum{}"
            case "~": result += "\\textasciitilde{}"
            default: result.append(character)
            }
        }
    }
}

extension ProjectTemplate {
    static let emptyProject = ProjectTemplate(
        id: "lightex.empty-project",
        name: "Empty Project",
        summary: "A minimal, compilable LaTeX document.",
        origin: .builtIn,
        runtimeRequirement: "Minimal",
        entryFile: "main.tex",
        previewStyle: .article,
        createdAt: nil,
        userDirectory: nil,
        blueprint: TemplateBlueprint(
            files: [
                "main.tex": #"""
                \documentclass[11pt]{article}

                \title{${PROJECT_NAME}}
                \author{}
                \date{}

                \begin{document}

                \maketitle

                \section{Introduction}

                Start writing here.

                \end{document}
                """#
            ],
            directories: []
        )
    )

    static let builtInTemplates: [ProjectTemplate] = [
        ProjectTemplate(
            id: "lightex.simple-article",
            name: "Simple Article",
            summary: "A clean article with a title, abstract, and sections.",
            origin: .builtIn,
            runtimeRequirement: "Minimal",
            entryFile: "main.tex",
            previewStyle: .article,
            createdAt: nil,
            userDirectory: nil,
            blueprint: TemplateBlueprint(
                files: [
                    "main.tex": #"""
                    \documentclass[11pt]{article}

                    \title{${PROJECT_NAME}}
                    \author{${AUTHOR}}
                    \date{${DATE}}

                    \begin{document}

                    \maketitle

                    \begin{abstract}
                    Write a concise summary of the article here.
                    \end{abstract}

                    \section{Introduction}

                    Start writing here.

                    \section{Conclusion}

                    Summarize the main result.

                    \end{document}
                    """#
                ],
                directories: []
            )
        ),
        ProjectTemplate(
            id: "lightex.math-notes",
            name: "Math Notes",
            summary: "Definitions, theorems, proofs, examples, and equations.",
            origin: .builtIn,
            runtimeRequirement: "Standard",
            entryFile: "main.tex",
            previewStyle: .mathematics,
            createdAt: nil,
            userDirectory: nil,
            blueprint: TemplateBlueprint(
                files: [
                    "main.tex": #"""
                    \documentclass[11pt]{article}

                    \usepackage[margin=1in]{geometry}
                    \usepackage{amsmath,amssymb,amsthm}
                    \usepackage{xcolor}

                    \definecolor{LighTexBlue}{HTML}{2563EB}
                    \newtheorem{theorem}{Theorem}[section]
                    \newtheorem{definition}[theorem]{Definition}
                    \newtheorem{example}[theorem]{Example}

                    \title{${PROJECT_NAME}}
                    \author{${AUTHOR}}
                    \date{${DATE}}

                    \begin{document}

                    \maketitle
                    \tableofcontents

                    \section{Foundations}

                    \begin{definition}
                    A vector space is a set equipped with vector addition and scalar multiplication.
                    \end{definition}

                    \begin{theorem}
                    The zero vector in a vector space is unique.
                    \end{theorem}

                    \begin{proof}
                    Suppose both $0$ and $0'$ are zero vectors. Then $0 = 0 + 0' = 0'$.
                    \end{proof}

                    \begin{example}
                    The set $\mathbb{R}^n$ is a vector space over $\mathbb{R}$.
                    \end{example}

                    \end{document}
                    """#
                ],
                directories: ["figures"]
            )
        ),
        ProjectTemplate(
            id: "lightex.textbook",
            name: "Textbook",
            summary: "A chapter-based book with a cover, contents, and references.",
            origin: .builtIn,
            runtimeRequirement: "Standard",
            entryFile: "main.tex",
            previewStyle: .textbook,
            createdAt: nil,
            userDirectory: nil,
            blueprint: TemplateBlueprint(
                files: [
                    "main.tex": #"""
                    \documentclass[11pt,oneside,openany]{book}

                    \usepackage[margin=1in]{geometry}
                    \usepackage{amsmath,amssymb,amsthm}
                    \usepackage{xcolor}
                    \usepackage[hidelinks]{hyperref}

                    \definecolor{LighTexBlue}{HTML}{2563EB}
                    \newtheorem{theorem}{Theorem}[chapter]
                    \newtheorem{definition}[theorem]{Definition}

                    \begin{document}

                    \frontmatter
                    \hypersetup{pageanchor=false}

                    \begin{titlepage}
                      \thispagestyle{empty}
                      \vspace*{0.16\textheight}
                      {\color{LighTexBlue}\rule{1.2in}{4pt}\par}
                      \vspace{1cm}
                      {\Huge\bfseries ${PROJECT_NAME}\par}
                      \vspace{0.45cm}
                      {\Large A concise visual textbook\par}
                      \vfill
                      {\large ${AUTHOR}\par}
                      \vspace{0.2cm}
                      {\small ${DATE}\par}
                    \end{titlepage}

                    \hypersetup{pageanchor=true}
                    \tableofcontents

                    \mainmatter

                    \chapter{Foundations}

                    \section{A first idea}

                    Introduce the subject and its central questions here.

                    \begin{definition}
                    State an important definition.
                    \end{definition}

                    \chapter{The Main Theory}

                    Develop the main results of the book.

                    \end{document}
                    """#,
                    "references.bib": "% Add bibliography entries here.\n"
                ],
                directories: ["figures", "scripts"]
            )
        ),
        ProjectTemplate(
            id: "lightex.presentation",
            name: "Presentation",
            summary: "A minimal 16:9 Beamer deck with a calm blue accent.",
            origin: .builtIn,
            runtimeRequirement: "Standard",
            entryFile: "main.tex",
            previewStyle: .presentation,
            createdAt: nil,
            userDirectory: nil,
            blueprint: TemplateBlueprint(
                files: [
                    "main.tex": #"""
                    \documentclass[aspectratio=169]{beamer}

                    \definecolor{LighTexBlue}{HTML}{2563EB}
                    \setbeamercolor{structure}{fg=LighTexBlue}
                    \setbeamertemplate{navigation symbols}{}

                    \title{${PROJECT_NAME}}
                    \author{${AUTHOR}}
                    \date{${DATE}}

                    \begin{document}

                    \begin{frame}
                      \titlepage
                    \end{frame}

                    \begin{frame}{The central idea}
                      \begin{itemize}
                        \item Begin with the problem.
                        \item Explain the key insight.
                        \item End with the result.
                      \end{itemize}
                    \end{frame}

                    \begin{frame}{A useful equation}
                      \[
                        e^{i\pi} + 1 = 0
                      \]
                    \end{frame}

                    \begin{frame}{Thank you}
                      Questions?
                    \end{frame}

                    \end{document}
                    """#
                ],
                directories: ["assets"]
            )
        )
    ]
}
