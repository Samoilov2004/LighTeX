import AppKit
import SwiftUI

struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let tabWidth: Int
    let showsLineNumbers: Bool
    let wordWrap: Bool
    let autoCloseBrackets: Bool
    let jumpLine: Int?
    let jumpToken: Int
    let onCursorChange: (Int, Int) -> Void
    let onWordDoubleClick: (Int, Int) -> Void

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        var isApplyingUpdate = false
        var lastJumpToken = -1
        var lastFontSize = -1.0
        var lastTabWidth = -1
        var lastShowsLineNumbers: Bool?
        var lastWordWrap: Bool?
        var lastAutoCloseBrackets: Bool?
        var lastCursorLine = -1
        var lastCursorColumn = -1
        weak var scrollView: NSScrollView?
        weak var rulerView: LineNumberRulerView?

        init(parent: SourceEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate,
                  let textView = notification.object as? CodeTextView else {
                return
            }
            parent.text = textView.string
            applySyntaxHighlighting(to: textView)
            updateSelectionState(textView)
            rulerView?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? CodeTextView else { return }
            updateSelectionState(textView)
            rulerView?.needsDisplay = true
        }

        @objc func visibleBoundsChanged(_ notification: Notification) {
            rulerView?.needsDisplay = true
        }

        func applySyntaxHighlighting(to textView: CodeTextView) {
            guard let textStorage = textView.textStorage else { return }
            isApplyingUpdate = true
            SyntaxHighlighter.apply(
                to: textStorage,
                font: textView.editorFont,
                lineHeightMultiple: 1.46,
                tabWidth: textView.editorTabWidth
            )
            isApplyingUpdate = false
        }

        func updateSelectionState(_ textView: CodeTextView) {
            let location = min(textView.selectedRange().location, (textView.string as NSString).length)
            let nsText = textView.string as NSString
            let prefixRange = NSRange(location: 0, length: location)
            let prefix = nsText.substring(with: prefixRange)
            let line = prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            let lastNewline = prefix.lastIndex(of: "\n")
            let column = lastNewline.map { prefix.distance(from: $0, to: prefix.endIndex) } ?? (location + 1)
            let safeColumn = max(1, column)
            if line != lastCursorLine || safeColumn != lastCursorColumn {
                lastCursorLine = line
                lastCursorColumn = safeColumn
                parent.onCursorChange(line, safeColumn)
            }
            applyBracketHighlights(to: textView)
        }

        func applyBracketHighlights(to textView: CodeTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

            for range in matchingBracketRanges(in: textView.string, cursor: textView.selectedRange().location) {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.selectedContentBackgroundColor.withAlphaComponent(0.20),
                    forCharacterRange: range
                )
            }
        }

        func wordDoubleClicked(line: Int, column: Int) {
            parent.onWordDoubleClick(line, column)
        }

        func jumpIfNeeded(in textView: CodeTextView) {
            guard lastJumpToken != parent.jumpToken,
                  let line = parent.jumpLine,
                  line > 0 else {
                return
            }
            lastJumpToken = parent.jumpToken

            let nsText = textView.string as NSString
            var currentLine = 1
            var location = 0
            while currentLine < line, location < nsText.length {
                let range = nsText.lineRange(for: NSRange(location: location, length: 0))
                location = NSMaxRange(range)
                currentLine += 1
            }
            let safeLocation = min(location, nsText.length)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
            textView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
            textView.window?.makeFirstResponder(textView)
            updateSelectionState(textView)
        }

        private func matchingBracketRanges(in text: String, cursor: Int) -> [NSRange] {
            let nsText = text as NSString
            guard nsText.length > 0 else { return [] }
            let candidates = [max(0, cursor - 1), min(cursor, nsText.length - 1)]
            let openings: [unichar: unichar] = [123: 125, 91: 93, 40: 41]
            let closings: [unichar: unichar] = [125: 123, 93: 91, 41: 40]

            for index in candidates where index < nsText.length {
                let character = nsText.character(at: index)
                if let closing = openings[character] {
                    var depth = 0
                    for position in (index + 1)..<nsText.length {
                        let current = nsText.character(at: position)
                        if current == character { depth += 1 }
                        if current == closing {
                            if depth == 0 {
                                return [NSRange(location: index, length: 1), NSRange(location: position, length: 1)]
                            }
                            depth -= 1
                        }
                    }
                } else if let opening = closings[character], index > 0 {
                    var depth = 0
                    for position in stride(from: index - 1, through: 0, by: -1) {
                        let current = nsText.character(at: position)
                        if current == character { depth += 1 }
                        if current == opening {
                            if depth == 0 {
                                return [NSRange(location: position, length: 1), NSRange(location: index, length: 1)]
                            }
                            depth -= 1
                        }
                    }
                }
            }
            return []
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CodeTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? CodeTextView else {
            preconditionFailure("AppKit did not create the expected CodeTextView")
        }

        textView.appearance = NSAppearance(named: .aqua)
        textView.delegate = context.coordinator
        textView.onWordDoubleClick = { [weak coordinator = context.coordinator] line, column in
            coordinator?.wordDoubleClicked(line: line, column: column)
        }
        configure(textView)
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.opensAtDocumentStart = true

        scrollView.appearance = NSAppearance(named: .aqua)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !wordWrap
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        ruler.appearance = NSAppearance(named: .aqua)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showsLineNumbers

        context.coordinator.scrollView = scrollView
        context.coordinator.rulerView = ruler
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.visibleBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        context.coordinator.applySyntaxHighlighting(to: textView)
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastTabWidth = tabWidth
        context.coordinator.lastShowsLineNumbers = showsLineNumbers
        context.coordinator.lastWordWrap = wordWrap
        context.coordinator.lastAutoCloseBrackets = autoCloseBrackets
        context.coordinator.updateSelectionState(textView)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        context.coordinator.parent = self

        let typographyChanged = context.coordinator.lastFontSize != fontSize
            || context.coordinator.lastTabWidth != tabWidth
        let configurationChanged = typographyChanged
            || context.coordinator.lastShowsLineNumbers != showsLineNumbers
            || context.coordinator.lastWordWrap != wordWrap
            || context.coordinator.lastAutoCloseBrackets != autoCloseBrackets

        if configurationChanged {
            configure(textView)
            scrollView.rulersVisible = showsLineNumbers
            scrollView.hasHorizontalScroller = !wordWrap
            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastTabWidth = tabWidth
            context.coordinator.lastShowsLineNumbers = showsLineNumbers
            context.coordinator.lastWordWrap = wordWrap
            context.coordinator.lastAutoCloseBrackets = autoCloseBrackets
        }

        if textView.string != text {
            context.coordinator.isApplyingUpdate = true
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(
                location: min(selection.location, length),
                length: min(selection.length, max(0, length - min(selection.location, length)))
            ))
            context.coordinator.applySyntaxHighlighting(to: textView)
            context.coordinator.isApplyingUpdate = false
        }

        if typographyChanged {
            context.coordinator.applySyntaxHighlighting(to: textView)
        }

        context.coordinator.jumpIfNeeded(in: textView)
        context.coordinator.rulerView?.needsDisplay = true
    }

    private func configure(_ textView: CodeTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isIncrementalSearchingEnabled = true
        textView.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        textView.backgroundColor = .white
        textView.insertionPointColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        textView.textContainerInset = NSSize(width: 9, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.editorFont = NSFont(name: "SFMono-Regular", size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = textView.editorFont
        textView.editorTabWidth = max(1, tabWidth)
        textView.closesBracketsAutomatically = autoCloseBrackets
        textView.isVerticallyResizable = true

        if wordWrap {
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(
                width: 0,
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }
}

final class CodeTextView: NSTextView {
    var editorTabWidth = 4
    var closesBracketsAutomatically = true
    var editorFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
    var opensAtDocumentStart = false
    var onWordDoubleClick: ((Int, Int) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, opensAtDocumentStart else { return }
        perform(#selector(scrollToDocumentStart), with: nil, afterDelay: 0)
    }

    @objc private func scrollToDocumentStart() {
        guard window != nil, opensAtDocumentStart else { return }
        opensAtDocumentStart = false
        setSelectedRange(NSRange(location: 0, length: 0))
        moveToBeginningOfDocument(nil)
        scrollRangeToVisible(NSRange(location: 0, length: 0))
        if let scrollView = enclosingScrollView {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    override func insertTab(_ sender: Any?) {
        insertText(String(repeating: " ", count: editorTabWidth), replacementRange: selectedRange())
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }

        let selection = selectedRange()
        let text = string as NSString
        guard selection.length > 0,
              NSMaxRange(selection) <= text.length,
              !text.substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let location = min(selection.location, text.length)
        let prefix = text.substring(to: location)
        let line = prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let column: Int
        if let newline = prefix.lastIndex(of: "\n") {
            column = prefix.distance(from: newline, to: prefix.endIndex)
        } else {
            column = location + 1
        }
        onWordDoubleClick?(line, max(1, column))
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard closesBracketsAutomatically,
              modifiers.isEmpty,
              let characters = event.characters,
              characters.count == 1 else {
            super.keyDown(with: event)
            return
        }

        let pairs: [Character: Character] = ["{": "}", "[": "]", "(": ")"]
        let closings: Set<Character> = ["}", "]", ")"]
        guard let character = characters.first else {
            super.keyDown(with: event)
            return
        }

        if let closing = pairs[character] {
            let selection = selectedRange()
            let selectedText = (string as NSString).substring(with: selection)
            let replacement = "\(character)\(selectedText)\(closing)"
            insertText(replacement, replacementRange: selection)
            setSelectedRange(NSRange(
                location: selection.location + 1,
                length: selection.length
            ))
            return
        }

        if closings.contains(character) {
            let selection = selectedRange()
            let nsText = string as NSString
            if selection.length == 0,
               selection.location < nsText.length,
               nsText.substring(with: NSRange(location: selection.location, length: 1)) == String(character) {
                setSelectedRange(NSRange(location: selection.location + 1, length: 0))
                return
            }
        }

        super.keyDown(with: event)
    }
}

private enum SyntaxHighlighter {
    static func apply(
        to storage: NSTextStorage,
        font: NSFont,
        lineHeightMultiple: CGFloat,
        tabWidth: Int
    ) {
        let fullRange = NSRange(location: 0, length: storage.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeightMultiple
        paragraph.tabStops = []
        paragraph.defaultTabInterval = font.maximumAdvancement.width * CGFloat(max(1, tabWidth))

        storage.beginEditing()
        storage.setAttributes([
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
            .paragraphStyle: paragraph
        ], range: fullRange)

        apply(#"%.*$"#, color: .secondaryLabelColor, options: [.anchorsMatchLines], to: storage)
        apply(#"\\[A-Za-z@]+\*?"#, color: NSColor.systemBlue.withAlphaComponent(0.88), to: storage)
        apply(#"\$[^$\n]+\$"#, color: NSColor.systemPurple.withAlphaComponent(0.76), to: storage)
        apply(#"\b(?:begin|end|documentclass|usepackage)\b"#, color: NSColor.systemBlue.withAlphaComponent(0.88), to: storage)
        apply(#"[{}\[\]()]"#, color: .secondaryLabelColor, to: storage)
        storage.endEditing()
    }

    private static func apply(
        _ pattern: String,
        color: NSColor,
        options: NSRegularExpression.Options = [],
        to storage: NSTextStorage
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let text = storage.string
        let range = NSRange(location: 0, length: (text as NSString).length)
        for match in regex.matches(in: text, range: range) {
            storage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let graphicsContext = NSGraphicsContext.current else { return }
        graphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        defer { graphicsContext.restoreGraphicsState() }

        NSColor(calibratedWhite: 0.975, alpha: 1).setFill()
        bounds.intersection(rect).fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        let visibleRect = textView.visibleRect
        var visibleContainerRect = visibleRect
        visibleContainerRect.origin.x -= textView.textContainerInset.width
        visibleContainerRect.origin.y -= textView.textContainerInset.height
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleContainerRect,
            in: textContainer
        )
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        let string = textView.string as NSString
        guard string.length > 0 else {
            drawLineNumber(1, y: textView.textContainerInset.height - visibleRect.minY)
            return
        }

        let safeStart = min(characterRange.location, string.length)
        let prefix = string.substring(to: safeStart)
        var lineNumber = prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        var location = safeStart
        let limit = min(NSMaxRange(characterRange), string.length)

        while location <= limit {
            let lineRange = string.lineRange(for: NSRange(location: min(location, string.length), length: 0))
            let lineGlyphRange = layoutManager.glyphRange(
                forCharacterRange: lineRange,
                actualCharacterRange: nil
            )
            var lineRect = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)
            lineRect.origin.y += textView.textContainerInset.height
            let y = lineRect.minY - visibleRect.minY
            drawLineNumber(lineNumber, y: y)

            let next = NSMaxRange(lineRange)
            if next <= location || next >= string.length { break }
            location = next
            lineNumber += 1
        }
    }

    private func drawLineNumber(_ number: Int, y: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let text = "\(number)" as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: ruleThickness - size.width - 8, y: y),
            withAttributes: attributes
        )
    }
}
