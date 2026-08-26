import Foundation

enum ProjectSidebarMode: String, CaseIterable, Identifiable, Sendable {
    case files = "Files"
    case search = "Search"
    case outline = "Outline"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .files: "folder"
        case .search: "magnifyingglass"
        case .outline: "list.bullet.indent"
        }
    }
}

struct ProjectSearchQuery: Equatable, Sendable {
    var text = ""
    var caseSensitive = false
    var wholeWord = false
    var usesRegularExpression = false

    var isEmpty: Bool { text.isEmpty }
}

struct ProjectSearchResult: Identifiable, Equatable, Sendable {
    let fileURL: URL
    let line: Int
    let column: Int
    let preview: String
    let matchLocation: Int
    let matchLength: Int

    var id: String { "\(fileURL.path)#\(matchLocation)#\(matchLength)" }
}

struct ReplaceFileChange: Equatable, Sendable {
    let fileURL: URL
    let originalText: String
    let replacementText: String
}

struct ReplaceTransaction: Equatable, Sendable {
    let query: ProjectSearchQuery
    let replacement: String
    let changes: [ReplaceFileChange]
}

enum ProjectSearchError: LocalizedError {
    case invalidRegularExpression(String)
    case fileChanged(String)

    var errorDescription: String? {
        switch self {
        case let .invalidRegularExpression(message):
            "The regular expression is invalid: \(message)"
        case let .fileChanged(name):
            "\(name) changed after the search. Run the search again before replacing."
        }
    }
}

enum ProjectSearchService {
    static let maximumResults = 2_000

    static func search(
        projectURL: URL,
        query: ProjectSearchQuery,
        openSources: [URL: String]
    ) throws -> [ProjectSearchResult] {
        guard !query.isEmpty else { return [] }
        let expression = try makeExpression(query)
        var results: [ProjectSearchResult] = []

        for fileURL in ProjectScanner.editableTextFiles(in: projectURL) {
            guard results.count < maximumResults else { break }
            let source = openSources[fileURL]
                ?? (try? String(contentsOf: fileURL, encoding: .utf8))
                ?? ""
            let string = source as NSString
            let matches = expression.matches(
                in: source,
                range: NSRange(location: 0, length: string.length)
            )
            for match in matches.prefix(maximumResults - results.count) {
                let lineRange = string.lineRange(for: NSRange(location: match.range.location, length: 0))
                let rawPreview = string.substring(with: lineRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(ProjectSearchResult(
                    fileURL: fileURL,
                    line: sourceLineNumber(atUTF16Location: match.range.location, in: string),
                    column: match.range.location - lineRange.location + 1,
                    preview: rawPreview.isEmpty ? "Empty line" : rawPreview,
                    matchLocation: match.range.location,
                    matchLength: match.range.length
                ))
            }
        }
        return results
    }

    static func replacementTransaction(
        projectURL: URL,
        query: ProjectSearchQuery,
        replacement: String,
        openSources: [URL: String]
    ) throws -> ReplaceTransaction {
        guard !query.isEmpty else {
            return ReplaceTransaction(query: query, replacement: replacement, changes: [])
        }
        let expression = try makeExpression(query)
        let replacementTemplate = query.usesRegularExpression
            ? replacement
            : NSRegularExpression.escapedTemplate(for: replacement)
        var changes: [ReplaceFileChange] = []

        for fileURL in ProjectScanner.editableTextFiles(in: projectURL) {
            let source = openSources[fileURL]
                ?? (try? String(contentsOf: fileURL, encoding: .utf8))
                ?? ""
            let range = NSRange(location: 0, length: (source as NSString).length)
            guard expression.firstMatch(in: source, range: range) != nil else { continue }
            let replaced = expression.stringByReplacingMatches(
                in: source,
                range: range,
                withTemplate: replacementTemplate
            )
            if replaced != source {
                changes.append(ReplaceFileChange(
                    fileURL: fileURL,
                    originalText: source,
                    replacementText: replaced
                ))
            }
        }
        return ReplaceTransaction(query: query, replacement: replacement, changes: changes)
    }

    private static func makeExpression(_ query: ProjectSearchQuery) throws -> NSRegularExpression {
        var pattern = query.usesRegularExpression
            ? query.text
            : NSRegularExpression.escapedPattern(for: query.text)
        if query.wholeWord {
            pattern = "(?<![A-Za-z0-9_])(?:\(pattern))(?![A-Za-z0-9_])"
        }
        let options: NSRegularExpression.Options = query.caseSensitive ? [] : [.caseInsensitive]
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw ProjectSearchError.invalidRegularExpression(error.localizedDescription)
        }
    }
}
