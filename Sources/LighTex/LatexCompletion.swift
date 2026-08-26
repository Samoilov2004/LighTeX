import Foundation

enum CompletionKind: String, Sendable {
    case command
    case environment
    case package
    case label
    case citation
    case filePath
    case documentClass
}

struct CompletionItem: Identifiable, Equatable, Sendable {
    let label: String
    let kind: CompletionKind
    let detail: String?

    var id: String { "\(kind.rawValue):\(label)" }
}

struct CompletionFileSymbols: Equatable, Sendable {
    let fileURL: URL
    var commands: Set<String> = []
    var labels: Set<String> = []
    var citations: Set<String> = []
    var packages: Set<String> = []
}

struct ProjectCompletionIndex: Equatable, Sendable {
    var commands: Set<String> = []
    var labels: Set<String> = []
    var citations: Set<String> = []
    var packages: Set<String> = []
    var classes: Set<String> = []
    var inputPaths: Set<String> = []
    var graphicsPaths: Set<String> = []

    static let empty = ProjectCompletionIndex()
}

enum LatexCompletionContextKind: Equatable, Sendable {
    case command
    case environment
    case package
    case reference
    case citation
    case inputPath
    case graphicsPath
    case documentClass
}

struct LatexCompletionContext: Equatable, Sendable {
    let kind: LatexCompletionContextKind
    let partialRange: NSRange
    let query: String
}

enum LatexCompletionService {
    static let standardCommands: Set<String> = [
        "author", "begin", "caption", "chapter", "cite", "documentclass", "emph",
        "end", "eqref", "footnote", "frac", "include", "includegraphics", "input",
        "item", "label", "maketitle", "newcommand", "newpage", "paragraph", "part",
        "ref", "renewcommand", "section", "sqrt", "subparagraph", "subsection",
        "subsubsection", "tableofcontents", "textbf", "textit", "texttt", "title",
        "usepackage", "url", "vec", "mathbf", "mathbb", "mathcal", "mathrm",
        "left", "right", "sum", "prod", "int", "lim", "overline", "underline",
        "centering", "hfill", "vspace", "hspace", "linebreak", "pagebreak",
        "pageref", "autoref", "bibliography", "bibliographystyle"
    ]

    static let standardPackages: Set<String> = [
        "amsmath", "amssymb", "amsthm", "array", "babel", "biblatex", "booktabs",
        "caption", "cleveref", "csquotes", "enumitem", "fontspec", "geometry",
        "graphicx", "hyperref", "inputenc", "listings", "mathtools", "microtype",
        "minted", "physics", "siunitx", "subcaption", "tcolorbox", "tikz", "xcolor"
    ]

    static let standardClasses: Set<String> = [
        "article", "book", "report", "letter", "beamer", "memoir", "standalone"
    ]

    static func parseSymbols(in text: String, fileURL: URL) -> CompletionFileSymbols {
        var symbols = CompletionFileSymbols(fileURL: fileURL)
        symbols.labels.formUnion(captures(#"\\label\{([^}]+)\}"#, in: text))
        symbols.commands.formUnion(captures(
            #"\\(?:newcommand|renewcommand|providecommand)\s*\{\\([A-Za-z@]+)"#,
            in: text
        ))
        for value in captures(#"\\usepackage(?:\[[^]]*\])?\{([^}]+)\}"#, in: text) {
            symbols.packages.formUnion(value.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            })
        }
        if fileURL.pathExtension.lowercased() == "bib" {
            symbols.citations.formUnion(captures(
                #"@[A-Za-z]+\s*\{\s*([^,\s]+)"#,
                in: text
            ))
        }
        return symbols
    }

    static func makeIndex(
        projectURL: URL,
        symbols: [URL: CompletionFileSymbols]
    ) -> ProjectCompletionIndex {
        var index = ProjectCompletionIndex.empty
        for value in symbols.values {
            index.commands.formUnion(value.commands)
            index.labels.formUnion(value.labels)
            index.citations.formUnion(value.citations)
            index.packages.formUnion(value.packages)
        }
        for fileURL in ProjectScanner.files(in: projectURL) {
            let relative = ProjectScanner.relativePath(for: fileURL, inside: projectURL)
            switch fileURL.pathExtension.lowercased() {
            case "tex":
                index.inputPaths.insert(String(relative.dropLast(4)))
            case "png", "jpg", "jpeg", "pdf", "eps", "svg":
                index.graphicsPaths.insert(relative)
            case "sty":
                index.packages.insert(fileURL.deletingPathExtension().lastPathComponent)
            case "cls":
                index.classes.insert(fileURL.deletingPathExtension().lastPathComponent)
            default:
                break
            }
        }
        return index
    }

    static func context(in text: String, selection: NSRange) -> LatexCompletionContext? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        guard selection.location <= source.length else { return nil }
        let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let prefixRange = NSRange(
            location: lineRange.location,
            length: selection.location - lineRange.location
        )
        let prefix = source.substring(with: prefixRange)

        let patterns: [(LatexCompletionContextKind, String)] = [
            (.environment, #"\\begin\{([A-Za-z*]*)$"#),
            (.package, #"\\usepackage(?:\[[^]]*\])?\{([^},]*)$"#),
            (.documentClass, #"\\documentclass(?:\[[^]]*\])?\{([^}]*)$"#),
            (.reference, #"\\(?:ref|pageref|eqref|autoref|cref|Cref)\{([^},]*)$"#),
            (.citation, #"\\(?:cite|parencite|textcite|autocite)\w*\{([^},]*)$"#),
            (.graphicsPath, #"\\includegraphics(?:\[[^]]*\])?\{([^}]*)$"#),
            (.inputPath, #"\\(?:input|include)\{([^}]*)$"#),
            (.command, #"\\([A-Za-z@]*)$"#)
        ]
        for (kind, pattern) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                    in: prefix,
                    range: NSRange(location: 0, length: (prefix as NSString).length)
                  ),
                  match.numberOfRanges == 2 else {
                continue
            }
            let localRange = match.range(at: 1)
            let range = NSRange(
                location: lineRange.location + localRange.location,
                length: localRange.length
            )
            return LatexCompletionContext(
                kind: kind,
                partialRange: range,
                query: source.substring(with: range)
            )
        }
        return nil
    }

    static func completions(
        for context: LatexCompletionContext,
        index: ProjectCompletionIndex
    ) -> [CompletionItem] {
        let values: Set<String>
        let kind: CompletionKind
        switch context.kind {
        case .command:
            values = standardCommands.union(index.commands)
            kind = .command
        case .environment:
            values = Set(latexEnvironmentNames)
            kind = .environment
        case .package:
            values = standardPackages.union(index.packages)
            kind = .package
        case .reference:
            values = index.labels
            kind = .label
        case .citation:
            values = index.citations
            kind = .citation
        case .inputPath:
            values = index.inputPaths
            kind = .filePath
        case .graphicsPath:
            values = index.graphicsPaths
            kind = .filePath
        case .documentClass:
            values = standardClasses.union(index.classes)
            kind = .documentClass
        }
        let query = context.query.lowercased()
        return values
            .filter { query.isEmpty || $0.lowercased().hasPrefix(query) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(80)
            .map { CompletionItem(label: $0, kind: kind, detail: nil) }
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}
