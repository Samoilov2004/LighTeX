import Foundation

enum LatexOutlineParser {
    private static let headingPattern = #"^\s*\\(part|chapter|section|subsection|subsubsection)\*?\s*(?:\[[^\]]*\]\s*)?\{"#

    static func parse(_ source: String, fileURL: URL) -> [DocumentOutlineItem] {
        guard let regex = try? NSRegularExpression(pattern: headingPattern) else { return [] }

        return source.components(separatedBy: .newlines).enumerated().compactMap { index, rawLine in
            let line = removingComment(from: rawLine)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let commandRange = Range(match.range(at: 1), in: line),
                  let rawTitle = balancedTitle(
                    in: line as NSString,
                    openingBrace: NSMaxRange(match.range) - 1
                  ) else {
                return nil
            }

            let command = String(line[commandRange])
            return DocumentOutlineItem(
                fileURL: fileURL,
                line: index + 1,
                title: displayTitle(rawTitle),
                level: level(for: command)
            )
        }
    }

    private static func balancedTitle(in line: NSString, openingBrace: Int) -> String? {
        guard openingBrace >= 0,
              openingBrace < line.length,
              line.character(at: openingBrace) == 123 else {
            return nil
        }
        var depth = 0
        for location in (openingBrace + 1)..<line.length {
            switch line.character(at: location) {
            case 123:
                depth += 1
            case 125:
                if depth == 0 {
                    return line.substring(with: NSRange(
                        location: openingBrace + 1,
                        length: location - openingBrace - 1
                    ))
                }
                depth -= 1
            default:
                continue
            }
        }
        return nil
    }

    private static func level(for command: String) -> Int {
        switch command {
        case "part", "chapter": 0
        case "section": 1
        case "subsection": 2
        default: 3
        }
    }

    private static func removingComment(from line: String) -> String {
        var slashCount = 0
        for index in line.indices {
            let character = line[index]
            if character == "\\" {
                slashCount += 1
                continue
            }
            if character == "%", slashCount.isMultiple(of: 2) {
                return String(line[..<index])
            }
            slashCount = 0
        }
        return line
    }

    private static func displayTitle(_ rawTitle: String) -> String {
        var title = rawTitle
        if let commandRegex = try? NSRegularExpression(
            pattern: #"\\[A-Za-z@]+\*?(?:\[[^\]]*\])?"#
        ) {
            let range = NSRange(title.startIndex..<title.endIndex, in: title)
            title = commandRegex.stringByReplacingMatches(
                in: title,
                range: range,
                withTemplate: ""
            )
        }
        return title
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
