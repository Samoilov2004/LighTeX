import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum InsertShelfCategory: String, CaseIterable, Identifiable {
    case symbols = "Symbols"
    case equation = "Equation"
    case figure = "Figure"
    case table = "Table"
    case more = "More"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .symbols: "character"
        case .equation: "function"
        case .figure: "photo"
        case .table: "tablecells"
        case .more: "curlybraces"
        }
    }
}

struct LatexSymbolDefinition: Identifiable, Equatable, Sendable {
    enum Group: String, CaseIterable, Identifiable, Sendable {
        case greek = "Greek"
        case operators = "Operators"
        case relations = "Relations"
        case arrows = "Arrows"
        case sets = "Sets"

        var id: String { rawValue }
    }

    let title: String
    let preview: String
    let command: String
    let group: Group
    let requiredPackage: String?

    var id: String { command }

    var insertionRequest: LatexInsertionRequest {
        LatexInsertionRequest(
            template: command + LatexInsertionRequest.cursorMarker,
            mode: .math,
            actionName: "Insert \(title)"
        )
    }
}

enum LatexSymbolCatalog {
    static let all: [LatexSymbolDefinition] = [
        symbol("Alpha", "α", "\\alpha", .greek),
        symbol("Beta", "β", "\\beta", .greek),
        symbol("Gamma", "γ", "\\gamma", .greek),
        symbol("Delta", "δ", "\\delta", .greek),
        symbol("Epsilon", "ε", "\\epsilon", .greek),
        symbol("Theta", "θ", "\\theta", .greek),
        symbol("Lambda", "λ", "\\lambda", .greek),
        symbol("Mu", "μ", "\\mu", .greek),
        symbol("Pi", "π", "\\pi", .greek),
        symbol("Rho", "ρ", "\\rho", .greek),
        symbol("Sigma", "σ", "\\sigma", .greek),
        symbol("Phi", "φ", "\\phi", .greek),
        symbol("Omega", "ω", "\\omega", .greek),
        symbol("Capital Gamma", "Γ", "\\Gamma", .greek),
        symbol("Capital Delta", "Δ", "\\Delta", .greek),
        symbol("Capital Sigma", "Σ", "\\Sigma", .greek),
        symbol("Capital Omega", "Ω", "\\Omega", .greek),

        symbol("Sum", "∑", "\\sum", .operators),
        symbol("Product", "∏", "\\prod", .operators),
        symbol("Integral", "∫", "\\int", .operators),
        symbol("Double integral", "∬", "\\iint", .operators, package: "amsmath"),
        symbol("Partial derivative", "∂", "\\partial", .operators),
        symbol("Nabla", "∇", "\\nabla", .operators),
        symbol("Infinity", "∞", "\\infty", .operators),
        symbol("Plus or minus", "±", "\\pm", .operators),
        symbol("Times", "×", "\\times", .operators),
        symbol("Dot product", "⋅", "\\cdot", .operators),
        symbol("Square root", "√", "\\sqrt{\(LatexInsertionRequest.selectionMarker)\(LatexInsertionRequest.cursorMarker)}", .operators),
        symbol("Fraction", "a⁄b", "\\frac{\(LatexInsertionRequest.selectionMarker)}{\(LatexInsertionRequest.cursorMarker)}", .operators),

        symbol("Equals", "=", "=", .relations),
        symbol("Not equal", "≠", "\\neq", .relations),
        symbol("Less than or equal", "≤", "\\leq", .relations),
        symbol("Greater than or equal", "≥", "\\geq", .relations),
        symbol("Approximately", "≈", "\\approx", .relations),
        symbol("Equivalent", "≡", "\\equiv", .relations),
        symbol("Proportional", "∝", "\\propto", .relations),
        symbol("Element of", "∈", "\\in", .relations),
        symbol("Not an element of", "∉", "\\notin", .relations),
        symbol("Subset", "⊂", "\\subset", .relations),
        symbol("Subset or equal", "⊆", "\\subseteq", .relations),

        symbol("Right arrow", "→", "\\rightarrow", .arrows),
        symbol("Left arrow", "←", "\\leftarrow", .arrows),
        symbol("Left-right arrow", "↔", "\\leftrightarrow", .arrows),
        symbol("Implies", "⇒", "\\Rightarrow", .arrows),
        symbol("Implied by", "⇐", "\\Leftarrow", .arrows),
        symbol("If and only if", "⇔", "\\Leftrightarrow", .arrows),
        symbol("Maps to", "↦", "\\mapsto", .arrows),
        symbol("Vector", "x⃗", "\\vec{\(LatexInsertionRequest.selectionMarker)\(LatexInsertionRequest.cursorMarker)}", .arrows),

        symbol("Real numbers", "ℝ", "\\mathbb{R}", .sets, package: "amsfonts"),
        symbol("Natural numbers", "ℕ", "\\mathbb{N}", .sets, package: "amsfonts"),
        symbol("Integers", "ℤ", "\\mathbb{Z}", .sets, package: "amsfonts"),
        symbol("Rational numbers", "ℚ", "\\mathbb{Q}", .sets, package: "amsfonts"),
        symbol("Complex numbers", "ℂ", "\\mathbb{C}", .sets, package: "amsfonts"),
        symbol("Empty set", "∅", "\\emptyset", .sets),
        symbol("Union", "∪", "\\cup", .sets),
        symbol("Intersection", "∩", "\\cap", .sets),
        symbol("For all", "∀", "\\forall", .sets),
        symbol("There exists", "∃", "\\exists", .sets)
    ]

    private static func symbol(
        _ title: String,
        _ preview: String,
        _ command: String,
        _ group: LatexSymbolDefinition.Group,
        package: String? = nil
    ) -> LatexSymbolDefinition {
        LatexSymbolDefinition(
            title: title,
            preview: preview,
            command: command,
            group: group,
            requiredPackage: package
        )
    }
}

enum InsertShelfSizing {
    static let defaultHeight: CGFloat = 168
    static let minimumHeight: CGFloat = 112
    static let maximumHeight: CGFloat = 260
    static let closeThreshold: CGFloat = 68
    static let adjustmentStep: CGFloat = 24

    static func height(from start: CGFloat, translation: CGFloat) -> CGFloat {
        min(maximumHeight, max(0, start + translation))
    }

    static func shouldClose(currentHeight: CGFloat, predictedHeight: CGFloat) -> Bool {
        min(currentHeight, predictedHeight) < closeThreshold
    }
}

struct InsertShelfContainer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var category: InsertShelfCategory = .symbols
    @State private var shelfHeight = InsertShelfSizing.defaultHeight
    @State private var dragStartHeight: CGFloat?
    let onInsert: (LatexInsertionRequest) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tongue
            if model.showsInsertShelf {
                InsertShelf(category: $category, onInsert: onInsert)
                    .frame(height: shelfHeight)
                    .clipped()
                    .transition(.move(edge: .top).combined(with: .opacity))
                resizeHandle
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: model.showsInsertShelf
        )
    }

    private var tongue: some View {
        Button {
            if model.showsInsertShelf {
                model.showsInsertShelf = false
            } else {
                shelfHeight = InsertShelfSizing.defaultHeight
                model.showsInsertShelf = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Insert")
                    .font(.system(size: 10.5, weight: .medium))
                Image(systemName: model.showsInsertShelf ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .frame(height: 19)
            .background(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 6
                )
                .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 6
                )
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(model.showsInsertShelf ? "Close Insert Shelf" : "Open Insert Shelf (Command-Shift-I)")
        .accessibilityLabel(model.showsInsertShelf ? "Close Insert Shelf" : "Open Insert Shelf")
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .top)
        .background(Color.white)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .frame(height: 9)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.55))
                    .frame(height: 1)
            }
            .overlay {
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 30, height: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartHeight == nil { dragStartHeight = shelfHeight }
                        shelfHeight = InsertShelfSizing.height(
                            from: dragStartHeight ?? shelfHeight,
                            translation: value.translation.height
                        )
                    }
                    .onEnded(finishResize)
            )
            .accessibilityLabel("Resize Insert Shelf")
            .accessibilityHint("Drag upward to close the shelf")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    shelfHeight = min(
                        InsertShelfSizing.maximumHeight,
                        shelfHeight + InsertShelfSizing.adjustmentStep
                    )
                case .decrement:
                    if shelfHeight <= InsertShelfSizing.minimumHeight {
                        closeLikeBlind()
                    } else {
                        shelfHeight = max(
                            InsertShelfSizing.minimumHeight,
                            shelfHeight - InsertShelfSizing.adjustmentStep
                        )
                    }
                @unknown default: break
                }
            }
            .help("Drag upward to close")
    }

    private func finishResize(_ value: DragGesture.Value) {
        let start = dragStartHeight ?? shelfHeight
        let predictedHeight = InsertShelfSizing.height(
            from: start,
            translation: value.predictedEndTranslation.height
        )
        dragStartHeight = nil
        if InsertShelfSizing.shouldClose(
            currentHeight: shelfHeight,
            predictedHeight: predictedHeight
        ) {
            closeLikeBlind()
        } else if shelfHeight < InsertShelfSizing.minimumHeight {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                shelfHeight = InsertShelfSizing.minimumHeight
            }
        }
    }

    private func closeLikeBlind() {
        guard model.showsInsertShelf else { return }
        if reduceMotion {
            model.showsInsertShelf = false
            shelfHeight = InsertShelfSizing.defaultHeight
            return
        }
        withAnimation(.easeOut(duration: 0.14)) {
            shelfHeight = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            guard shelfHeight < 1 else { return }
            model.showsInsertShelf = false
            shelfHeight = InsertShelfSizing.defaultHeight
        }
    }
}

private struct InsertShelf: View {
    @Binding var category: InsertShelfCategory
    let onInsert: (LatexInsertionRequest) -> Void
    @State private var showsFigureSheet = false
    @State private var showsTableSheet = false

    var body: some View {
        VStack(spacing: 0) {
            categoryBar
            Divider()
            Group {
                switch category {
                case .symbols:
                    SymbolPalette(onInsert: onInsert)
                case .equation:
                    EquationPalette(onInsert: onInsert)
                case .figure:
                    launchPanel(
                        icon: "photo.on.rectangle",
                        title: "Insert a figure",
                        detail: "Choose a project image or import one from your Mac, then create the LaTeX figure block.",
                        actionTitle: "Open Figure Builder",
                        action: { showsFigureSheet = true }
                    )
                case .table:
                    launchPanel(
                        icon: "tablecells",
                        title: "Insert a table",
                        detail: "Choose rows, columns, borders, caption, and label without writing the tabular boilerplate.",
                        actionTitle: "Open Table Builder",
                        action: { showsTableSheet = true }
                    )
                case .more:
                    StructurePalette(onInsert: onInsert)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showsFigureSheet) {
            FigureInsertionSheet { request in
                onInsert(request)
                showsFigureSheet = false
            }
        }
        .sheet(isPresented: $showsTableSheet) {
            TableInsertionSheet { request in
                onInsert(request)
                showsTableSheet = false
            }
        }
    }

    private var categoryBar: some View {
        ViewThatFits(in: .horizontal) {
            categoryButtons(compact: false)
                .fixedSize(horizontal: true, vertical: false)
            categoryButtons(compact: true)
        }
        .padding(.horizontal, 7)
        .frame(height: 30)
    }

    private func categoryButtons(compact: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(InsertShelfCategory.allCases) { item in
                Button {
                    category = item
                } label: {
                    Group {
                        if compact {
                            Image(systemName: item.systemImage)
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(item.rawValue, systemImage: item.systemImage)
                        }
                    }
                    .font(.system(size: 10, weight: category == item ? .semibold : .regular))
                    .padding(.horizontal, compact ? 5 : 7)
                    .frame(maxWidth: compact ? .infinity : nil, minHeight: 23)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(category == item ? Color.accentColor.opacity(0.13) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .help(item.rawValue)
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(category == item ? .isSelected : [])
            }
            if !compact { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func launchPanel(
        icon: String,
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 21))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
    }
}

private struct SymbolPalette: View {
    let onInsert: (LatexInsertionRequest) -> Void
    @State private var searchText = ""
    @State private var group: LatexSymbolDefinition.Group?

    private var symbols: [LatexSymbolDefinition] {
        LatexSymbolCatalog.all.filter { symbol in
            (group == nil || symbol.group == group)
                && (searchText.isEmpty
                    || symbol.title.localizedCaseInsensitiveContains(searchText)
                    || symbol.command.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                TextField("Find a symbol", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Picker("Symbol group", selection: $group) {
                    Text("All").tag(LatexSymbolDefinition.Group?.none)
                    ForEach(LatexSymbolDefinition.Group.allCases) { group in
                        Text(group.rawValue).tag(Optional(group))
                    }
                }
                .labelsHidden()
                .frame(width: 112)
            }
            .padding(.horizontal, 8)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 42, maximum: 54), spacing: 4)],
                    spacing: 4
                ) {
                    ForEach(symbols) { symbol in
                        Button {
                            onInsert(symbol.insertionRequest)
                        } label: {
                            VStack(spacing: 1) {
                                Text(symbol.preview)
                                    .font(.system(size: 16, design: .serif))
                                if symbol.requiredPackage != nil {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 3, height: 3)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 33)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(symbol.requiredPackage.map {
                            "\(symbol.command) · requires \\usepackage{\($0)}"
                        } ?? symbol.command)
                        .accessibilityLabel("Insert \(symbol.title), \(symbol.command)")
                    }
                }
                .padding(.horizontal, 7)
                .padding(.bottom, 5)
            }
        }
        .padding(.top, 5)
    }
}

private struct EquationPalette: View {
    let onInsert: (LatexInsertionRequest) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132, maximum: 210), spacing: 8)],
                spacing: 8
            ) {
                equationButton("Inline Math", preview: "$x + y$", request: LatexInsertCatalog.inlineMath)
                equationButton("Display Math", preview: "$$  x + y  $$", request: LatexInsertCatalog.displayMath)
                equationButton("Equation", preview: "equation", request: LatexInsertCatalog.environment("equation"))
                equationButton("Align", preview: "x &= y", request: LatexInsertCatalog.environment("align", body: " &= "))
                equationButton("Cases", preview: "f(x) = { …", request: LatexInsertionRequest(
                    template: [
                        "$$",
                        "\\begin{cases}",
                        "  \(LatexInsertionRequest.selectionMarker)\(LatexInsertionRequest.cursorMarker) & \\text{if } \\\\",
                        "   & \\text{otherwise}",
                        "\\end{cases}",
                        "$$"
                    ].joined(separator: "\n"),
                    actionName: "Insert Cases"
                ))
                equationButton("Matrix", preview: "[ a  b ]", request: LatexInsertionRequest(
                    template: [
                        "$$",
                        "\\begin{bmatrix}",
                        "  \(LatexInsertionRequest.selectionMarker)\(LatexInsertionRequest.cursorMarker) & 0 \\\\",
                        "  0 & 1",
                        "\\end{bmatrix}",
                        "$$"
                    ].joined(separator: "\n"),
                    actionName: "Insert Matrix"
                ))
            }
            .padding(8)
        }
    }

    private func equationButton(
        _ title: String,
        preview: String,
        request: LatexInsertionRequest
    ) -> some View {
        Button { onInsert(request) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(preview)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .padding(.horizontal, 9)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Insert \(title)")
    }
}

private struct StructurePalette: View {
    let onInsert: (LatexInsertionRequest) -> Void

    private let items: [(String, String, LatexInsertionRequest)] = [
        ("Itemized List", "list.bullet", LatexInsertCatalog.environment("itemize", body: "\\item ")),
        ("Numbered List", "list.number", LatexInsertCatalog.environment("enumerate", body: "\\item ")),
        ("Section", "textformat.size.larger", LatexInsertionRequest(
            template: "\\section{\(LatexInsertionRequest.selectionMarker)\(LatexInsertionRequest.cursorMarker)}",
            actionName: "Insert Section"
        )),
        ("Theorem", "text.book.closed", LatexInsertCatalog.environment("theorem")),
        ("Proof", "checkmark.seal", LatexInsertCatalog.environment("proof")),
        ("Quotation", "quote.opening", LatexInsertCatalog.environment("quote")),
        ("Code Block", "chevron.left.forwardslash.chevron.right", LatexInsertCatalog.environment("verbatim")),
        ("Citation", "books.vertical", LatexInsertionRequest(
            template: "\\cite{\(LatexInsertionRequest.selectionMarker)\(LatexInsertionRequest.cursorMarker)}",
            actionName: "Insert Citation"
        )),
        ("Reference", "arrow.turn.down.right", LatexInsertionRequest(
            template: "\\ref{\(LatexInsertionRequest.selectionMarker)\(LatexInsertionRequest.cursorMarker)}",
            actionName: "Insert Reference"
        ))
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 125, maximum: 180), spacing: 7)],
                spacing: 7
            ) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button { onInsert(item.2) } label: {
                        Label(item.0, systemImage: item.1)
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
                            .padding(.horizontal, 9)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }
}

private struct FigureInsertionSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL: URL?
    @State private var caption = ""
    @State private var label = ""
    @State private var width = 0.8
    let onInsert: (LatexInsertionRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert Figure")
                .font(.system(size: 17, weight: .semibold))
            Form {
                LabeledContent("Image") {
                    HStack {
                        Text(sourceURL?.lastPathComponent ?? "No image selected")
                            .foregroundStyle(sourceURL == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Menu("Project Files") {
                            if model.projectImageFiles.isEmpty {
                                Text("No images in project")
                            }
                            ForEach(model.projectImageFiles, id: \.self) { url in
                                Button(model.projectURL.map {
                                    ProjectScanner.relativePath(for: url, inside: $0)
                                } ?? url.lastPathComponent) {
                                    choose(url)
                                }
                            }
                        }
                        Button("Choose…") { chooseExternalImage() }
                    }
                }
                TextField("Caption", text: $caption)
                TextField("Label", text: $label, prompt: Text("fig:example"))
                HStack {
                    Text("Width")
                    Slider(value: $width, in: 0.1...1, step: 0.05)
                    Text("\(Int((width * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
            .formStyle(.grouped)

            Label("The generated block uses \\includegraphics and requires \\usepackage{graphicx}.", systemImage: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert Figure") { insertFigure() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(sourceURL == nil)
            }
        }
        .padding(20)
        .frame(width: 580, height: 390)
        .preferredColorScheme(.light)
    }

    private func choose(_ url: URL) {
        sourceURL = url
        if label.isEmpty {
            label = "fig:" + slug(url.deletingPathExtension().lastPathComponent)
        }
    }

    private func chooseExternalImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose Figure Image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .png, .jpeg, .pdf, .svg,
            UTType(filenameExtension: "eps") ?? .image
        ]
        if panel.runModal() == .OK, let url = panel.url { choose(url) }
    }

    private func insertFigure() {
        guard let sourceURL,
              let relativePath = model.prepareFigureImage(sourceURL) else { return }
        // TeX always expects a dot as the decimal separator, regardless of the
        // user's macOS locale (for example, Russian normally formats this as 0,8).
        let widthText = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            width
        )
        var lines = [
            "\\begin{figure}[htbp]",
            "  \\centering",
            "  \\includegraphics[width=\(widthText)\\linewidth]{\(relativePath)}"
        ]
        if !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("  \\caption{\(caption)}")
        }
        if !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("  \\label{\(label)}")
        }
        lines.append("  \(LatexInsertionRequest.cursorMarker)")
        lines.append("\\end{figure}")
        onInsert(LatexInsertionRequest(
            template: lines.joined(separator: "\n"),
            actionName: "Insert Figure"
        ))
    }

    private func slug(_ value: String) -> String {
        value.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
    }
}

private struct TableInsertionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rows = 3
    @State private var columns = 3
    @State private var hasHeader = true
    @State private var hasBorders = false
    @State private var caption = ""
    @State private var label = ""
    let onInsert: (LatexInsertionRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert Table")
                .font(.system(size: 17, weight: .semibold))
            Form {
                Stepper("Rows: \(rows)", value: $rows, in: 1...20)
                Stepper("Columns: \(columns)", value: $columns, in: 1...10)
                Toggle("First row is a header", isOn: $hasHeader)
                Toggle("Draw cell borders", isOn: $hasBorders)
                TextField("Caption", text: $caption)
                TextField("Label", text: $label, prompt: Text("tab:example"))
            }
            .formStyle(.grouped)

            tablePreview

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert Table") { insertTable() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540, height: 470)
        .preferredColorScheme(.light)
    }

    private var tablePreview: some View {
        Text("\(rows) × \(columns) · " + (hasBorders ? "borders" : "no borders"))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func insertTable() {
        let column = hasBorders ? "|c" : "c"
        let specification = hasBorders
            ? String(repeating: column, count: columns) + "|"
            : String(repeating: column, count: columns)
        var lines = ["\\begin{table}[htbp]", "  \\centering"]
        if !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("  \\caption{\(caption)}")
        }
        if !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("  \\label{\(label)}")
        }
        lines.append("  \\begin{tabular}{\(specification)}")
        if hasBorders { lines.append("    \\hline") }
        for row in 0..<rows {
            let cells = (0..<columns).map { column in
                row == 0 && column == 0
                    ? LatexInsertionRequest.cursorMarker + (hasHeader ? "Header" : "")
                    : (hasHeader && row == 0 ? "Header" : "")
            }
            lines.append("    " + cells.joined(separator: " & ") + " \\\\")
            if hasBorders || (hasHeader && row == 0) { lines.append("    \\hline") }
        }
        lines.append("  \\end{tabular}")
        lines.append("\\end{table}")
        onInsert(LatexInsertionRequest(
            template: lines.joined(separator: "\n"),
            actionName: "Insert Table"
        ))
    }
}
