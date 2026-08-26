import Foundation

enum LatexInsertionMode: Equatable, Sendable {
    case plain
    case math
}

struct LatexInsertionRequest: Identifiable, Equatable, Sendable {
    static let selectionMarker = "‹#selection#›"
    static let cursorMarker = "‹#cursor#›"

    let id: UUID
    let template: String
    let mode: LatexInsertionMode
    let actionName: String

    init(
        template: String,
        mode: LatexInsertionMode = .plain,
        actionName: String = "Insert LaTeX"
    ) {
        id = UUID()
        self.template = template
        self.mode = mode
        self.actionName = actionName
    }
}

struct LatexInsertionResult: Equatable, Sendable {
    let replacementRange: NSRange
    let replacement: String
    let cursorLocation: Int
}

enum LatexInsertionService {
    private static let mathEnvironmentPattern = try! NSRegularExpression(
        pattern: #"\\(begin|end)\{(equation\*?|align\*?|alignat\*?|gather\*?|multline\*?|flalign\*?|displaymath|math|cases|[bBpPvV]?matrix)\}"#
    )

    static func result(
        in text: String,
        selection: NSRange,
        request: LatexInsertionRequest
    ) -> LatexInsertionResult? {
        let source = text as NSString
        guard selection.location != NSNotFound,
              selection.location <= source.length,
              NSMaxRange(selection) <= source.length else { return nil }

        let selectedText = source.substring(with: selection)
        var replacement = request.template.replacingOccurrences(
            of: LatexInsertionRequest.selectionMarker,
            with: selectedText
        )
        var cursorOffset: Int
        if let cursorRange = replacement.range(of: LatexInsertionRequest.cursorMarker) {
            cursorOffset = replacement.utf16.distance(
                from: replacement.utf16.startIndex,
                to: cursorRange.lowerBound.samePosition(in: replacement.utf16)!
            )
            replacement.removeSubrange(cursorRange)
        } else {
            cursorOffset = (replacement as NSString).length
        }

        if request.mode == .math,
           !isInsideMath(in: text, atUTF16Location: selection.location) {
            replacement = "$\(replacement)$"
            cursorOffset += 1
        }

        let indentation = lineIndentation(in: source, at: selection.location)
        if replacement.contains("\n"), !indentation.isEmpty {
            let pieces = replacement.components(separatedBy: "\n")
            var rebuilt = pieces[0]
            var adjustedCursor = cursorOffset
            var originalOffset = (pieces[0] as NSString).length
            for piece in pieces.dropFirst() {
                rebuilt += "\n" + indentation + piece
                originalOffset += 1
                if cursorOffset >= originalOffset {
                    adjustedCursor += (indentation as NSString).length
                }
                originalOffset += (piece as NSString).length
            }
            replacement = rebuilt
            cursorOffset = adjustedCursor
        }

        return LatexInsertionResult(
            replacementRange: selection,
            replacement: replacement,
            cursorLocation: selection.location + cursorOffset
        )
    }

    static func isInsideMath(in text: String, atUTF16Location location: Int) -> Bool {
        let source = text as NSString
        let limit = min(max(0, location), source.length)
        var index = 0
        var inlineMath = false
        var displayMath = false
        var legacyInlineMath = false
        var legacyDisplayMath = false
        var inComment = false

        while index < limit {
            let character = source.character(at: index)
            if character == 10 || character == 13 {
                inComment = false
                index += 1
                continue
            }
            if inComment {
                index += 1
                continue
            }
            if character == 37, isUnescaped(in: source, at: index) {
                inComment = true
                index += 1
                continue
            }
            if character == 92, isUnescaped(in: source, at: index), index + 1 < limit {
                switch source.character(at: index + 1) {
                case 40:
                    legacyInlineMath = true
                    index += 2
                    continue
                case 41:
                    legacyInlineMath = false
                    index += 2
                    continue
                case 91:
                    legacyDisplayMath = true
                    index += 2
                    continue
                case 93:
                    legacyDisplayMath = false
                    index += 2
                    continue
                default:
                    break
                }
            }
            guard character == 36, isUnescaped(in: source, at: index) else {
                index += 1
                continue
            }
            if index + 1 < limit, source.character(at: index + 1) == 36 {
                displayMath.toggle()
                index += 2
            } else {
                inlineMath.toggle()
                index += 1
            }
        }
        return inlineMath
            || displayMath
            || legacyInlineMath
            || legacyDisplayMath
            || isInsideMathEnvironment(in: source, before: limit)
    }

    private static func isInsideMathEnvironment(in source: NSString, before limit: Int) -> Bool {
        let range = NSRange(location: 0, length: limit)
        var depth = 0
        for match in mathEnvironmentPattern.matches(in: source as String, range: range) {
            guard !isInComment(in: source, at: match.range.location),
                  match.numberOfRanges >= 2 else { continue }
            let action = source.substring(with: match.range(at: 1))
            if action == "begin" {
                depth += 1
            } else {
                depth = max(0, depth - 1)
            }
        }
        return depth > 0
    }

    private static func isInComment(in source: NSString, at location: Int) -> Bool {
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        guard location > lineRange.location else { return false }
        var index = lineRange.location
        while index < location {
            if source.character(at: index) == 37, isUnescaped(in: source, at: index) {
                return true
            }
            index += 1
        }
        return false
    }

    private static func isUnescaped(in source: NSString, at location: Int) -> Bool {
        var slashCount = 0
        var previous = location - 1
        while previous >= 0, source.character(at: previous) == 92 {
            slashCount += 1
            previous -= 1
        }
        return slashCount.isMultiple(of: 2)
    }

    private static func lineIndentation(in text: NSString, at location: Int) -> String {
        let safeLocation = min(max(0, location), text.length)
        let lineRange = text.lineRange(for: NSRange(location: safeLocation, length: 0))
        let prefixLength = max(0, safeLocation - lineRange.location)
        let prefix = text.substring(with: NSRange(location: lineRange.location, length: prefixLength))
        return String(prefix.prefix { $0 == " " || $0 == "\t" })
    }
}

enum LatexInsertCatalog {
    static var inlineMath: LatexInsertionRequest {
        LatexInsertionRequest(
            template: "$\(LatexInsertionRequest.selectionMarker)\(LatexInsertionRequest.cursorMarker)$",
            actionName: "Insert Inline Math"
        )
    }

    static var displayMath: LatexInsertionRequest {
        LatexInsertionRequest(
            template: "$$\n  \(LatexInsertionRequest.selectionMarker)\(LatexInsertionRequest.cursorMarker)\n$$",
            actionName: "Insert Display Math"
        )
    }

    static func environment(_ name: String, body: String = "") -> LatexInsertionRequest {
        LatexInsertionRequest(
            template: "\\begin{\(name)}\n  \(LatexInsertionRequest.selectionMarker)\(body)\(LatexInsertionRequest.cursorMarker)\n\\end{\(name)}",
            actionName: "Insert \(name)"
        )
    }
}
