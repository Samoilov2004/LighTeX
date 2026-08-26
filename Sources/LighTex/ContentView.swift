import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var runtimeManager: RuntimeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .trailing) {
            Group {
                if !runtimeManager.isSetupComplete {
                    RuntimeSetupView()
                } else if model.hasProject {
                    WorkspaceView()
                } else if model.showsTemplates {
                    TemplatesView()
                } else {
                    WelcomeView()
                }
            }

            if model.showsSettingsPanel, runtimeManager.isSetupComplete {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.showsSettingsPanel = false
                    }
                    .accessibilityHidden(true)

                SettingsView {
                    model.showsSettingsPanel = false
                }
                .frame(width: 420)
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .shadow(color: .black.opacity(0.12), radius: 14, x: -3, y: 0)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.showsSettingsPanel)
        .onExitCommand {
            if model.showsSettingsPanel {
                model.showsSettingsPanel = false
            }
        }
        .preferredColorScheme(.light)
        .background(LighTexTheme.windowBackground)
        .background(WindowChromeConfigurator())
        .toolbar {
            unifiedToolbar
        }
        .sheet(isPresented: $model.showsCreateProjectSheet) {
            CreateProjectSheet(template: nil)
        }
        .sheet(item: $model.templateForNewProject) { template in
            CreateProjectSheet(template: template)
        }
        .sheet(item: $model.templateSourceDraft) { draft in
            CreateTemplateSheet(draft: draft)
        }
        .alert(
            "LighTex",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { presented in
                    if !presented { model.alertMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.alertMessage = nil
            }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var unifiedToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }

        ToolbarItemGroup(placement: .navigation) {
            if model.showsTemplates, !model.hasProject {
                Button {
                    model.closeTemplateLibrary()
                } label: {
                    Label("Projects", systemImage: "chevron.backward")
                }
                .labelStyle(.titleAndIcon)
                .help("Back to Projects")
                .accessibilityLabel("Back to Projects")
            } else if model.hasProject {
                Button {
                    model.closeProject()
                } label: {
                    Label("Projects", systemImage: "chevron.backward")
                }
                .labelStyle(.titleAndIcon)
                .help("Back to Projects")
                .accessibilityLabel("Back to Projects")

                Button {
                    model.showsSidebar.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(model.showsSidebar ? "Hide Project Navigator" : "Show Project Navigator")
                .accessibilityLabel(model.showsSidebar ? "Hide Project Navigator" : "Show Project Navigator")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if model.hasProject {
                Button {
                    model.showsProblemsPanel.toggle()
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .help("Show or hide Problems and Log")
                .accessibilityLabel("Problems and Log")

                Button {
                    model.showsPDF.toggle()
                } label: {
                    Image(systemName: "doc.richtext")
                }
                .help(model.showsPDF ? "Hide PDF Preview" : "Show PDF Preview")
                .accessibilityLabel(model.showsPDF ? "Hide PDF Preview" : "Show PDF Preview")

                Button {
                    model.setAutomaticBuilds(!model.settings.automaticBuilds)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.settings.automaticBuilds ? "checkmark.circle.fill" : "circle")
                        Text("Auto Compile")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(model.settings.automaticBuilds
                    ? "Auto Compile is on: waits \(Int(model.settings.automaticBuildDelay)) seconds after the last edit"
                    : "Auto Compile is off: use Recompile to update the PDF")
                .accessibilityLabel(model.settings.automaticBuilds
                    ? "Disable Auto Compile"
                    : "Enable Auto Compile")

                Button {
                    model.buildNow()
                } label: {
                    HStack(spacing: 6) {
                        if model.isBuilding {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(model.isBuilding ? "Compiling…" : "Recompile")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.canBuild)
                .help("Recompile PDF now (Command-B)")
                .accessibilityLabel(model.isBuilding ? "Compiling PDF" : "Recompile PDF")
            } else if runtimeManager.isSetupComplete {
                Button {
                    model.showsSettingsPanel.toggle()
                } label: {
                    Image(systemName: model.showsSettingsPanel ? "gearshape.fill" : "gearshape")
                }
                .help(model.showsSettingsPanel ? "Close Settings" : "Open Settings")
                .accessibilityLabel(model.showsSettingsPanel ? "Close Settings" : "Open Settings")
            }
        }
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView {
        ChromeView()
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.applyWindowStyle()
    }

    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyWindowStyle()
        }

        func applyWindowStyle() {
            guard let window else { return }
            window.toolbarStyle = .unified
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.backgroundColor = .windowBackgroundColor
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmsClearingRecentProjects = false

    var body: some View {
        ZStack {
            Color.white

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    welcomeHeader
                    HStack(alignment: .top, spacing: 44) {
                        actions
                            .frame(width: 220)
                        recentProjects
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 36)
                }
                .frame(maxWidth: 820)
                .padding(.horizontal, 40)
                .padding(.vertical, 50)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var welcomeHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("LighTex")
                    .font(.system(size: 28, weight: .semibold))
                Text("A lightweight local LaTeX editor")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("START")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 1)

            Button {
                model.showsCreateProjectSheet = true
            } label: {
                Label("New Empty Project", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                model.chooseProject()
            } label: {
                Label("Open Project…", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                model.showTemplateLibrary()
            } label: {
                Label("New from Template", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var recentProjects: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Projects")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !model.recentProjects.isEmpty {
                    Button("Clear") {
                        confirmsClearingRecentProjects = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear Recent Projects")
                }
            }
            .padding(.bottom, 8)

            Divider()

            if model.recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No recent projects")
                        .font(.system(size: 13, weight: .medium))
                    Text("Projects you open will appear here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 22)
            } else {
                ForEach(model.recentProjects) { project in
                    RecentProjectRow(project: project)
                    Divider()
                }
            }
        }
        .alert(
            "Clear Recent Projects?",
            isPresented: $confirmsClearingRecentProjects
        ) {
            Button("Clear History", role: .destructive) {
                model.clearRecentProjects()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all projects from LighTex's recent-projects list. Your project folders and files will remain on your Mac.")
        }
    }
}

private struct RecentProjectRow: View {
    @EnvironmentObject private var model: AppModel
    let project: RecentProject
    @State private var isHovering = false

    var body: some View {
        Button {
            model.openRecentProject(project)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "folder")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(project.abbreviatedPath)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                Text(project.lastOpened, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? LighTexTheme.hover : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open") {
                model.openRecentProject(project)
            }
            Divider()
            Button("Remove from Recent Projects") {
                model.removeRecentProject(project)
            }
        }
        .help(project.path)
    }
}

private struct TemplatesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var templatePendingDeletion: ProjectTemplate?

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 230), spacing: 22, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Templates")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Start with a LighTex design or reuse one of your own projects.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 34)

                templateSectionHeader("Yours") {
                    if !model.userTemplates.isEmpty {
                        Button {
                            model.chooseTemplateSourceFolder()
                        } label: {
                            Label("Create Template", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityHint("Choose a project folder to save as a reusable template")
                    }
                }

                if model.userTemplates.isEmpty {
                    PersonalTemplatesEmptyState {
                        model.chooseTemplateSourceFolder()
                    }
                    .padding(.top, 10)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(model.userTemplates) { template in
                            TemplateCard(
                                template: template,
                                onUse: { model.beginCreatingProject(from: template) },
                                onReveal: { model.revealPersonalTemplate(template) },
                                onDelete: { templatePendingDeletion = template }
                            )
                        }
                    }
                    .padding(.top, 14)
                }

                templateSectionHeader("LighTex Templates")
                    .padding(.top, 38)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(ProjectTemplate.builtInTemplates) { template in
                        TemplateCard(
                            template: template,
                            onUse: { model.beginCreatingProject(from: template) }
                        )
                    }
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: 1_040, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.white)
        .alert(
            "Delete Template?",
            isPresented: Binding(
                get: { templatePendingDeletion != nil },
                set: { if !$0 { templatePendingDeletion = nil } }
            )
        ) {
            Button("Delete Template", role: .destructive) {
                if let templatePendingDeletion {
                    model.deletePersonalTemplate(templatePendingDeletion)
                }
                templatePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                templatePendingDeletion = nil
            }
        } message: {
            Text("This removes only the reusable template. The original project and projects previously created from it will remain on your Mac.")
        }
    }

    @ViewBuilder
    private func templateSectionHeader<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            trailing()
        }
    }

    private func templateSectionHeader(_ title: String) -> some View {
        templateSectionHeader(title) { EmptyView() }
    }
}

private struct PersonalTemplatesEmptyState: View {
    let create: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No personal templates yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Save a project as a template and reuse it later.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Create Template", action: create)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
    }
}

private struct TemplateCard: View {
    let template: ProjectTemplate
    let onUse: () -> Void
    var onReveal: (() -> Void)?
    var onDelete: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        Button(action: onUse) {
            VStack(alignment: .leading, spacing: 10) {
                TemplatePreviewSurface(template: template)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(
                                isHovering
                                    ? Color.accentColor.opacity(0.75)
                                    : Color(nsColor: .separatorColor).opacity(0.65),
                                lineWidth: isHovering ? 1.5 : 1
                            )
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(template.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(template.runtimeRequirement)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Use \(template.name) template")
        .accessibilityHint(template.summary)
        .contextMenu {
            Button("Use Template", action: onUse)
            if let onReveal {
                Divider()
                Button("Reveal in Finder", action: onReveal)
            }
            if let onDelete {
                Divider()
                Button("Delete Template", role: .destructive, action: onDelete)
            }
        }
    }
}

private struct TemplatePreviewSurface: View {
    let template: ProjectTemplate

    var body: some View {
        Group {
            if let previewURL = template.previewURL,
               let image = NSImage(contentsOf: previewURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(7)
                    .background(Color.white)
            } else {
                TemplatePagePreview(style: template.previewStyle)
            }
        }
        .frame(height: 216)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .shadow(color: .black.opacity(0.055), radius: 5, y: 2)
        .accessibilityHidden(true)
    }
}

private struct TemplatePagePreview: View {
    let style: TemplatePreviewStyle

    var body: some View {
        ZStack {
            Color.white
            switch style {
            case .article:
                articlePreview
            case .mathematics:
                mathematicsPreview
            case .textbook:
                textbookPreview
            case .presentation:
                presentationPreview
            }
        }
        .frame(height: 216)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .shadow(color: .black.opacity(0.055), radius: 5, y: 2)
        .accessibilityHidden(true)
    }

    private var articlePreview: some View {
        VStack(spacing: 8) {
            Text("ARTICLE TITLE")
                .font(.system(size: 11, weight: .bold, design: .serif))
            Text("Author Name")
                .font(.system(size: 6.5, design: .serif))
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 3)
            previewHeading("Abstract")
            previewLines([0.92, 0.84, 0.76])
            previewHeading("1  Introduction")
            previewLines([0.95, 0.88, 0.91, 0.68])
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 25)
    }

    private var mathematicsPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MATHEMATICAL NOTES")
                .font(.system(size: 10.5, weight: .bold, design: .serif))
            previewHeading("1  Foundations")
            previewLines([0.94, 0.79])
            HStack(spacing: 4) {
                Text("THEOREM 1.1")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                previewLine(width: 0.46)
            }
            Text("a² + b² = c²")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            previewHeading("Proof")
            previewLines([0.9, 0.83, 0.63])
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
    }

    private var textbookPreview: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.075, green: 0.11, blue: 0.16)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 4)
                .padding(.leading, 24)
                .padding(.vertical, 26)
            VStack(alignment: .leading, spacing: 5) {
                Text("A CONCISE TEXTBOOK")
                    .font(.system(size: 6.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer().frame(height: 19)
                Text("CORE")
                Text("MATHEMATICS")
                Text("Ideas, structure, and patterns")
                    .font(.system(size: 7, design: .serif))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 3)
                Spacer()
                Text("AUTHOR NAME")
                    .font(.system(size: 6.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .font(.system(size: 17, weight: .bold, design: .serif))
            .foregroundStyle(.white)
            .padding(.leading, 39)
            .padding(.trailing, 16)
            .padding(.vertical, 28)
        }
    }

    private var presentationPreview: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            VStack(alignment: .leading, spacing: 9) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                Spacer()
                Text("THE CENTRAL IDEA")
                    .font(.system(size: 12, weight: .bold))
                Text("A clear presentation starts with one strong question.")
                    .font(.system(size: 7.5))
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                    previewLine(width: 0.62)
                }
                HStack(spacing: 5) {
                    Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                    previewLine(width: 0.48)
                }
                Spacer()
            }
            .padding(18)
            .background(Color.white)
            .aspectRatio(16 / 9, contentMode: .fit)
            .padding(14)
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
    }

    private func previewHeading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: .bold, design: .serif))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewLines(_ widths: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                previewLine(width: width)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewLine(width: CGFloat) -> some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Color.primary.opacity(0.14))
                .frame(width: geometry.size.width * width, height: 2.5)
        }
        .frame(height: 2.5)
    }
}

private struct CreateTemplateSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let draft: TemplateSourceDraft
    @State private var name: String
    @State private var summary = ""
    @State private var review: TemplateCopyReview?
    @State private var showsIncludedFiles = false
    @State private var showsExcludedFiles = true

    init(draft: TemplateSourceDraft) {
        self.draft = draft
        _name = State(initialValue: draft.suggestedName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Personal Template")
                .font(.system(size: 17, weight: .semibold))
            Text("LighTex copies the project into Yours. The original folder will not be changed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Form {
                TextField("Template Name", text: $name)
                TextField("Description", text: $summary)
                LabeledContent("Source") {
                    Text(draft.sourceURL.path(percentEncoded: false))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(draft.sourceURL.path(percentEncoded: false))
                }
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 8) {
                Text("Review what the reusable template will contain")
                    .font(.system(size: 12, weight: .semibold))
                if let review {
                    DisclosureGroup(
                        "Included — \(review.included.count) files",
                        isExpanded: $showsIncludedFiles
                    ) {
                        reviewFileList(review.included)
                    }
                    DisclosureGroup(
                        "Excluded — \(review.excluded.count) items",
                        isExpanded: $showsExcludedFiles
                    ) {
                        reviewFileList(review.excluded)
                    }
                } else {
                    ProgressView("Inspecting project…")
                        .controlSize(.small)
                }
                Text("Secrets, private keys, Git metadata, build files, caches, and generated PDFs are always excluded.")
                Text("Optional placeholders: ${PROJECT_NAME}, ${AUTHOR}, and ${DATE}.")
                    .fontDesign(.monospaced)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    model.templateSourceDraft = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Create Template") {
                    if model.savePersonalTemplate(name: name, summary: summary) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || review == nil
                )
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .preferredColorScheme(.light)
        .task {
            review = model.templateCopyReview(for: draft.sourceURL)
        }
    }

    @ViewBuilder
    private func reviewFileList(_ entries: [TemplateReviewEntry]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(entries) { entry in
                    HStack(spacing: 6) {
                        Image(systemName: entry.reason == nil ? "doc" : "nosign")
                            .foregroundStyle(.secondary)
                        Text(entry.relativePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let reason = entry.reason {
                            Spacer()
                            Text(reason)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 10.5))
                }
            }
        }
        .frame(maxHeight: 82)
        .padding(.top, 4)
    }
}

private struct CreateProjectSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let template: ProjectTemplate?
    @State private var projectName = ""
    @State private var author = NSFullUserName()
    @State private var location = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first ?? FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(template.map { "New from \($0.name)" } ?? "New Empty Project")
                .font(.system(size: 17, weight: .semibold))

            Text(template?.summary ?? "Creates a clean project with a minimal main.tex document.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Form {
                TextField("Project Name", text: $projectName)

                if template != nil {
                    TextField("Author", text: $author)
                }

                LabeledContent("Location") {
                    HStack(spacing: 8) {
                        Text(abbreviatedLocation)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") {
                            if let selected = model.chooseProjectLocation(current: location) {
                                location = selected
                            }
                        }
                    }
                }

            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    let created: Bool
                    if let template {
                        created = model.createProject(
                            from: template,
                            name: projectName,
                            author: author,
                            location: location
                        )
                    } else {
                        created = model.createProject(name: projectName, location: location)
                    }
                    if created {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 470, height: template == nil ? 250 : 290)
        .preferredColorScheme(.light)
    }

    private var abbreviatedLocation: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = location.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

private struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                if model.showsSidebar {
                    ProjectNavigator()
                        .frame(minWidth: 185, idealWidth: 230, maxWidth: 330)
                }

                EditorWorkspace()
                    .frame(minWidth: 360)

                if model.showsPDF {
                    PDFWorkspace()
                        .frame(minWidth: 320, idealWidth: 470)
                }
            }

            if model.showsProblemsPanel {
                Divider()
                ProblemsPanel()
                    .frame(minHeight: 130, idealHeight: 190, maxHeight: 330)
            }

            Divider()
            WorkspaceStatusBar()
        }
        .background(Color.white)
    }
}

private struct ProjectNavigator: View {
    @EnvironmentObject private var model: AppModel
    @State private var creationKind: ProjectItemCreationKind?
    @State private var itemPendingRename: ProjectItem?
    @State private var itemPendingTrash: ProjectItem?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Project Navigator", selection: $model.sidebarMode) {
                ForEach(ProjectSidebarMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .frame(height: 40)

            Divider()

            switch model.sidebarMode {
            case .files:
                projectFiles
            case .search:
                ProjectSearchNavigator()
            case .outline:
                documentOutline
            }
        }
        .background(LighTexTheme.sidebarBackground)
        .sheet(item: $creationKind) { kind in
            ProjectItemCreationSheet(kind: kind) { name in
                switch kind {
                case .file:
                    model.createProjectFile(named: name)
                case .folder:
                    model.createProjectFolder(named: name)
                }
            }
        }
        .sheet(item: $itemPendingRename) { item in
            RenameProjectItemSheet(item: item) { name in
                model.renameProjectItem(item.url, to: name)
            }
        }
        .confirmationDialog(
            "Move “\(itemPendingTrash?.name ?? "item")” to the Trash?",
            isPresented: Binding(
                get: { itemPendingTrash != nil },
                set: { if !$0 { itemPendingTrash = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let item = itemPendingTrash {
                    model.moveProjectItemToTrash(item.url)
                }
                itemPendingTrash = nil
            }
            Button("Cancel", role: .cancel) { itemPendingTrash = nil }
        } message: {
            Text("The item can be recovered later from the macOS Trash.")
        }
    }

    private var projectFiles: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                Text("FILES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                ProjectNavigatorActionButton(
                    title: "Create File",
                    systemImage: "doc.badge.plus"
                ) {
                    creationKind = .file
                }
                ProjectNavigatorActionButton(
                    title: "Create Folder",
                    systemImage: "folder.badge.plus"
                ) {
                    creationKind = .folder
                }
                ProjectNavigatorActionButton(
                    title: "Upload File",
                    systemImage: "square.and.arrow.up"
                ) {
                    model.importProjectFiles()
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 34)

            Divider()

            if model.projectTree.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 21))
                        .foregroundStyle(.tertiary)
                    Text("No files yet")
                        .font(.system(size: 12, weight: .medium))
                    Text("Create a file or add one from your Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                List(selection: $model.navigatorSelection) {
                    OutlineGroup(model.projectTree, children: \.children) { item in
                        ProjectFileTreeRow(
                            item: item,
                            isMainDocument: item.url == model.entryFileURL
                        )
                        .tag(item.url)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !item.isDirectory {
                                model.activateNavigatorItem(item.url)
                            }
                        }
                        .dropDestination(for: URL.self) { urls, _ in
                            guard item.isDirectory else { return false }
                            return model.dropProjectItems(urls, into: item.url)
                        }
                        .contextMenu {
                            if !item.isDirectory {
                                Button("Open") {
                                    model.activateNavigatorItem(item.url)
                                }
                                if item.url.pathExtension.lowercased() == "tex" {
                                    Button("Use as Main Document") {
                                        model.setEntryFile(item.url)
                                    }
                                }
                                Divider()
                            }
                            Button("Rename…") {
                                itemPendingRename = item
                            }
                            Button("Duplicate") {
                                model.duplicateProjectItem(item.url)
                            }
                            Button("Move to Trash…", role: .destructive) {
                                itemPendingTrash = item
                            }
                            Divider()
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onChange(of: model.navigatorSelection) { _, selection in
                    if let selection {
                        model.activateNavigatorItem(selection)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let projectURL = model.projectURL else { return false }
                    return model.dropProjectItems(urls, into: projectURL)
                }
            }
        }
    }

    private var documentOutline: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("OUTLINE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.refreshProject()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Refresh files and outline")
                .accessibilityLabel("Refresh files and outline")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)

            Divider()

            if model.outlineItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                    Text("No sections yet")
                        .font(.system(size: 12, weight: .medium))
                    Text("Chapters and sections will appear here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                List(model.outlineItems) { item in
                    Button {
                        model.openOutlineItem(item)
                    } label: {
                        OutlineNavigatorRow(
                            item: item,
                            isSelected: item.id == model.selectedOutlineItemID
                        )
                    }
                    .buttonStyle(.plain)
                    .help("\(item.fileURL.lastPathComponent), line \(item.line)")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityAddTraits(
                        item.id == model.selectedOutlineItemID ? .isSelected : []
                    )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(LighTexTheme.sidebarBackground)
    }
}

private struct ProjectSearchNavigator: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFieldFocused: Bool
    @State private var confirmsReplaceAll = false

    private var queryText: Binding<String> {
        Binding(
            get: { model.projectSearchQuery.text },
            set: { value in
                var query = model.projectSearchQuery
                query.text = value
                model.projectSearchQuery = query
            }
        )
    }

    private func optionBinding(_ keyPath: WritableKeyPath<ProjectSearchQuery, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.projectSearchQuery[keyPath: keyPath] },
            set: { value in
                var query = model.projectSearchQuery
                query[keyPath: keyPath] = value
                model.projectSearchQuery = query
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Search project", text: queryText)
                        .textFieldStyle(.plain)
                        .focused($searchFieldFocused)
                        .onSubmit { model.runProjectSearchNow() }
                    if model.isProjectSearchRunning {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Searching project")
                    } else if !model.projectSearchQuery.text.isEmpty {
                        Button {
                            queryText.wrappedValue = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Clear project search")
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.7))
                }

                HStack(spacing: 10) {
                    Toggle("Case", isOn: optionBinding(\.caseSensitive))
                    Toggle("Word", isOn: optionBinding(\.wholeWord))
                    Toggle("Regex", isOn: optionBinding(\.usesRegularExpression))
                    Spacer(minLength: 0)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 10.5))

                HStack(spacing: 6) {
                    TextField("Replace with", text: $model.projectSearchReplacement)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                    Button("Replace All") {
                        confirmsReplaceAll = true
                    }
                    .controlSize(.small)
                    .disabled(model.projectSearchResults.isEmpty || model.isProjectSearchRunning)
                }

                if model.lastReplaceTransaction != nil {
                    Button("Undo Last Replace") {
                        model.undoLastProjectReplace()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(9)

            Divider()

            searchResults
        }
        .onAppear { searchFieldFocused = true }
        .alert("Replace all matches?", isPresented: $confirmsReplaceAll) {
            Button("Replace All") { model.replaceAllProjectSearchResults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will update \(Set(model.projectSearchResults.map(\.fileURL)).count) files. You can undo this replacement until the next Replace All operation.")
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if let error = model.projectSearchError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.system(size: 11.5))
                    .multilineTextAlignment(.center)
                Button("Try Again") { model.runProjectSearchNow() }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.projectSearchQuery.isEmpty {
            EmptyWorkspaceState(
                icon: "magnifyingglass",
                title: "Search the project",
                detail: "Find text across all editable project files."
            )
        } else if model.projectSearchResults.isEmpty, !model.isProjectSearchRunning {
            EmptyWorkspaceState(
                icon: "magnifyingglass",
                title: "No matches",
                detail: "Try another phrase or change the search options."
            )
        } else {
            let grouped = Dictionary(grouping: model.projectSearchResults, by: \.fileURL)
            let files = grouped.keys.sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(files, id: \.self) { fileURL in
                        Text(fileURL.lastPathComponent)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(grouped[fileURL] ?? []) { result in
                            Button {
                                model.openSearchResult(result)
                            } label: {
                                HStack(alignment: .top, spacing: 7) {
                                    Text("\(result.line)")
                                        .font(.system(size: 10).monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 28, alignment: .trailing)
                                    Text(result.preview)
                                        .font(.system(size: 11.5).monospaced())
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Line \(result.line), column \(result.column)")
                        }
                    }
                }
            }
            .accessibilityLabel("Project search results")
        }
    }
}

private struct RenameProjectItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ProjectItem
    let onRename: (String) -> Bool
    @State private var name: String
    @FocusState private var focused: Bool

    init(item: ProjectItem, onRename: @escaping (String) -> Bool) {
        self.item = item
        self.onRename = onRename
        _name = State(initialValue: item.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename \(item.isDirectory ? "Folder" : "File")")
                .font(.system(size: 17, weight: .semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    if onRename(name) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == item.name)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { focused = true }
    }
}

private enum ProjectItemCreationKind: String, Identifiable {
    case file
    case folder

    var id: String { rawValue }
    var title: String { self == .file ? "Create File" : "Create Folder" }
    var prompt: String { self == .file ? "File Name" : "Folder Name" }
    var defaultName: String { self == .file ? "untitled.tex" : "New Folder" }
    var icon: String { self == .file ? "doc.badge.plus" : "folder.badge.plus" }
}

private struct ProjectItemCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: ProjectItemCreationKind
    let onCreate: (String) -> Bool
    @State private var name: String
    @FocusState private var nameIsFocused: Bool

    init(kind: ProjectItemCreationKind, onCreate: @escaping (String) -> Bool) {
        self.kind = kind
        self.onCreate = onCreate
        _name = State(initialValue: kind.defaultName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: kind.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(kind.title)
                    .font(.system(size: 17, weight: .semibold))
            }

            TextField(kind.prompt, text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameIsFocused)
                .accessibilityLabel(kind.prompt)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    if onCreate(name) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            nameIsFocused = true
        }
    }
}

private struct ProjectNavigatorActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct ProjectFileTreeRow: View {
    let item: ProjectItem
    let isMainDocument: Bool

    @ViewBuilder
    var body: some View {
        row
            .onDrag {
                NSItemProvider(object: item.url as NSURL)
            } preview: {
                HStack(spacing: 6) {
                    Image(systemName: item.iconName)
                        .foregroundStyle(.secondary)
                    Text(item.name)
                        .lineLimit(1)
                }
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .help(item.isDirectory
                ? "Drag to move \(item.name)"
                : "Drag to open or move \(item.name)")
    }

    private var row: some View {
        HStack(spacing: 6) {
            Image(systemName: item.iconName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(item.name)
                .font(.system(size: 12.5))
                .lineLimit(1)
            Spacer(minLength: 4)
            if isMainDocument {
                Text("MAIN")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct OutlineNavigatorRow: View {
    let item: DocumentOutlineItem
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            if item.level == 0 {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 2, height: 15)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(item.level == 1 ? 0.55 : 0.32))
                    .frame(width: 4, height: 4)
            }

            Text(item.title)
                .font(.system(
                    size: item.level == 0 ? 12.5 : 12,
                    weight: item.level == 0 ? .medium : .regular
                ))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)
        }
        .padding(.leading, 8 + CGFloat(item.level) * 13)
        .padding(.trailing, 8)
        .frame(minHeight: 29)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovering ? LighTexTheme.hover : .clear)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.accentColor.opacity(0.13))
                    }
                }
                .padding(.horizontal, 4)
        )
        .onHover { isHovering = $0 }
    }
}

private struct EditorWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            EditorTabBar()
                .zIndex(1)

            if let document = model.selectedDocument {
                VStack(spacing: 0) {
                    if document.externalChangeState != .none {
                        ExternalChangeBanner(document: document)
                        Divider()
                    }

                    SourceEditor(
                        text: Binding(
                            get: { model.selectedDocument?.text ?? "" },
                            set: { model.updateSelectedText($0) }
                        ),
                        fontSize: settings.editorFontSize,
                        tabWidth: settings.tabWidth,
                        showsLineNumbers: settings.showLineNumbers,
                        wordWrap: settings.wordWrap,
                        autoCloseBrackets: settings.autoCloseBrackets,
                        completionIndex: model.projectCompletionIndex,
                        jumpLine: document.jumpLine,
                        jumpToken: document.jumpToken,
                        onCursorChange: model.updateCursor,
                        onWordDoubleClick: { line, column in
                            model.jumpPDF(toSource: document.url, line: line, column: column)
                        }
                    )
                    .id(document.id)
                    .clipped()
                }
            } else {
                EmptyWorkspaceState(
                    icon: "doc.text",
                    title: "Select a file to start editing",
                    detail: "Choose a text file from the Project Navigator."
                )
            }
        }
        .background(Color.white)
    }
}

private struct ExternalChangeBanner: View {
    @EnvironmentObject private var model: AppModel
    let document: EditorDocument

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: document.externalChangeState == .modified
                ? "arrow.triangle.2.circlepath"
                : "doc.badge.exclamationmark")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(document.externalChangeState == .modified
                    ? "This file changed outside LighTex"
                    : "This file was removed from disk")
                    .font(.system(size: 12, weight: .semibold))
                Text(document.externalChangeState == .modified
                    ? "Choose which version to keep before saving or compiling."
                    : "Save the open text somewhere else or close the tab.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if document.externalChangeState == .modified {
                Button("Reload") { model.reloadExternalVersion(of: document.url) }
                Button("Save Copy…") { model.saveConflictedCopy(of: document.url) }
                Button("Keep Mine") { model.keepLocalVersion(of: document.url) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Close") { model.closeDeletedDocument(document.url) }
                Button("Save As…") { model.saveDeletedDocumentAs(document.url) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(document.externalChangeState == .modified
            ? "External file conflict"
            : "File removed from disk")
    }
}

struct EditorTabDropIndicator: Equatable {
    let targetDocumentID: URL
    let placement: DocumentMovePlacement
}

private struct EditorTabsContentWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct EditorTabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [URL: CGRect] = [:]

    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

func editorTabDropIndicator(
    locationX: CGFloat,
    orderedDocumentIDs: [URL],
    frames: [URL: CGRect]
) -> EditorTabDropIndicator? {
    let visible = orderedDocumentIDs.compactMap { id in
        frames[id].map { (id, $0) }
    }
    guard let first = visible.first, let last = visible.last else { return nil }

    if locationX < first.1.midX {
        return EditorTabDropIndicator(targetDocumentID: first.0, placement: .before)
    }
    for (id, frame) in visible.dropFirst() where locationX < frame.midX {
        return EditorTabDropIndicator(targetDocumentID: id, placement: .before)
    }
    return EditorTabDropIndicator(targetDocumentID: last.0, placement: .after)
}

private struct EditorTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel
    @State private var draggedDocumentID: URL?
    @State private var dropIndicator: EditorTabDropIndicator?
    @State private var isFileDropTarget = false
    @State private var tabsContentWidth: CGFloat = 0
    @State private var tabFrames: [URL: CGRect] = [:]
    @State private var draggedDocument: EditorDocument?
    @State private var draggedTabWidth: CGFloat = 0
    @State private var dragLocationX: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            let visibleDocuments = model.openDocuments.filter { $0.id != draggedDocumentID }
                            HStack(spacing: 0) {
                                ForEach(Array(visibleDocuments.enumerated()), id: \.element.id) { index, document in
                                    let isActive = document.id == model.selectedDocumentID
                                    let nextIsActive = visibleDocuments.indices.contains(index + 1)
                                        && visibleDocuments[index + 1].id == model.selectedDocumentID
                                    EditorTab(
                                        document: document,
                                        isActive: isActive,
                                        showsTrailingSeparator: !isActive
                                            && !nextIsActive
                                            && index < visibleDocuments.count - 1,
                                        dropIndicator: $dropIndicator
                                    )
                                    .id(document.id)
                                }
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: EditorTabsContentWidthPreferenceKey.self,
                                        value: proxy.size.width
                                    )
                                }
                            }

                            ProjectFileDropReceiver(
                                onDrop: openFirstDroppedProjectFile,
                                onTargeted: { isFileDropTarget = $0 }
                            )
                                .frame(
                                    width: max(44, geometry.size.width - tabsContentWidth),
                                    height: 34
                                )
                                .background(
                                    isFileDropTarget
                                        ? Color.accentColor.opacity(0.07)
                                        : LighTexTheme.secondaryBackground
                                )
                        }
                        .frame(
                            width: max(geometry.size.width, tabsContentWidth + 44),
                            height: 34,
                            alignment: .leading
                        )
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.12),
                            value: model.openDocuments.map(\.id)
                        )
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.12),
                            value: draggedDocumentID
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, tabsContentWidth > geometry.size.width ? 30 : 0)
                    .onChange(of: model.selectedDocumentID) { _, selected in
                        guard let selected else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                            scrollProxy.scrollTo(selected, anchor: .center)
                        }
                    }
                }

                if tabsContentWidth > geometry.size.width {
                    Menu {
                        ForEach(model.openDocuments) { document in
                            Button {
                                model.selectDocument(document.url)
                            } label: {
                                HStack {
                                    if document.id == model.selectedDocumentID {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(document.displayName + (document.isDirty ? " •" : ""))
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 28, height: 34)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .background(LighTexTheme.secondaryBackground)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help("Show all open files")
                    .accessibilityLabel("Show all open files")
                }

                if let draggedDocument {
                    EditorTabDragPreview(document: draggedDocument)
                        .frame(
                            width: max(80, draggedTabWidth),
                            height: 34
                        )
                        .position(
                            x: min(max(dragLocationX, draggedTabWidth / 2), geometry.size.width - draggedTabWidth / 2),
                            y: 17
                        )
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "EditorTabBar")
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("EditorTabBar"))
                    .onChanged(handleTabDrag)
                    .onEnded { value in
                        updateTabPlacement(at: value.location.x)
                        finishTabDrag()
                    }
            )
        }
        .frame(height: 34)
        .onPreferenceChange(EditorTabsContentWidthPreferenceKey.self) { width in
            tabsContentWidth = max(0, width)
        }
        .onPreferenceChange(EditorTabFramePreferenceKey.self) { frames in
            tabFrames = frames
        }
        .background(
            isFileDropTarget
                ? Color.accentColor.opacity(0.07)
                : LighTexTheme.secondaryBackground
        )
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            return openFirstDroppedProjectFile(urls)
        } isTargeted: { isTargeted in
            isFileDropTarget = isTargeted
        }
        .accessibilityLabel("Open editor tabs")
        .task(id: draggedDocumentID) {
            guard draggedDocumentID != nil else { return }

            while !Task.isCancelled, NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(nanoseconds: 40_000_000)
            }

            if !Task.isCancelled {
                finishTabDrag()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            finishTabDrag()
        }
        .onDisappear {
            finishTabDrag()
        }
    }

    private func handleTabDrag(_ value: DragGesture.Value) {
        if draggedDocumentID == nil {
            guard let source = model.openDocuments.first(where: { document in
                guard let frame = tabFrames[document.id] else { return false }
                return frame.contains(value.startLocation)
                    && value.startLocation.x < frame.maxX - 28
            }), let sourceFrame = tabFrames[source.id] else {
                return
            }
            draggedDocumentID = source.id
            draggedDocument = source
            draggedTabWidth = sourceFrame.width
        }
        dragLocationX = value.location.x
        updateTabPlacement(at: value.location.x)
    }

    private func updateTabPlacement(at locationX: CGFloat) {
        guard let draggedDocumentID else { return }
        let visibleIDs = model.openDocuments.map(\.id).filter { $0 != draggedDocumentID }
        guard let indicator = editorTabDropIndicator(
            locationX: locationX,
            orderedDocumentIDs: visibleIDs,
            frames: tabFrames
        ), indicator != dropIndicator else {
            return
        }
        dropIndicator = indicator
        model.moveDocument(
            draggedDocumentID,
            relativeTo: indicator.targetDocumentID,
            placement: indicator.placement
        )
    }

    private func finishTabDrag() {
        draggedDocumentID = nil
        draggedDocument = nil
        draggedTabWidth = 0
        dropIndicator = nil
    }

    private func openFirstDroppedProjectFile(_ urls: [URL]) -> Bool {
        guard let url = urls.first(where: \.isFileURL) else { return false }
        return model.openDroppedProjectItem(atPath: url.path)
    }
}

private struct EditorTab: View {
    @EnvironmentObject private var model: AppModel
    let document: EditorDocument
    let isActive: Bool
    let showsTrailingSeparator: Bool
    @Binding var dropIndicator: EditorTabDropIndicator?
    @State private var isHovering = false
    @FocusState private var isSelectionFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: document.url.pathExtension.lowercased() == "bib" ? "books.vertical" : "doc.plaintext")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(document.displayName)
                    .font(.system(size: 12, weight: isActive ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if document.isDirty {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 7)
            .frame(height: 34)
            .contentShape(Rectangle())
            .onTapGesture {
                model.selectDocument(document.url)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(document.isDirty
                ? "\(document.displayName), unsaved changes"
                : document.displayName)
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction {
                model.selectDocument(document.url)
            }
            .help("Select or drag \(document.displayName)")

            Button {
                model.closeDocument(document.url)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isActive || isHovering ? 1 : 0)
            .help("Close \(document.displayName)")
            .accessibilityLabel("Close \(document.displayName)")
            .padding(.trailing, 6)
        }
        .frame(height: 34)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tabSurfaceColor)
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
        }
        .overlay(alignment: .trailing) {
            if showsTrailingSeparator {
                Rectangle()
                    .fill(LighTexTheme.divider)
                    .frame(width: 1, height: 18)
            }
        }
        .overlay {
            if isActive || isSelectionFocused {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(isSelectionFocused ? 0.82 : 0.58),
                        lineWidth: 1
                    )
                    .padding(.horizontal, 2)
                    .padding(.vertical, 3)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: insertionAlignment) {
            if dropIndicator?.targetDocumentID == document.id {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 24)
                    .padding(.horizontal, 1)
                    .allowsHitTesting(false)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: EditorTabFramePreferenceKey.self,
                        value: [
                            document.id: proxy.frame(in: .named("EditorTabBar"))
                        ]
                    )
            }
        }
        .focusable()
        .focused($isSelectionFocused)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .contextMenu {
            if let index = model.openDocuments.firstIndex(where: { $0.id == document.id }) {
                Button("Move Tab Left") {
                    guard index > 0 else { return }
                    model.moveDocument(
                        document.id,
                        relativeTo: model.openDocuments[index - 1].id,
                        placement: .before
                    )
                }
                .disabled(index == 0)

                Button("Move Tab Right") {
                    guard index + 1 < model.openDocuments.count else { return }
                    model.moveDocument(
                        document.id,
                        relativeTo: model.openDocuments[index + 1].id,
                        placement: .after
                    )
                }
                .disabled(index + 1 == model.openDocuments.count)

                Divider()
            }

            Button("Close Tab") {
                model.closeDocument(document.url)
            }
        }
    }

    private var tabSurfaceColor: Color {
        if isActive {
            return Color.white
        }
        return isHovering ? LighTexTheme.hover : Color.clear
    }

    private var insertionAlignment: Alignment {
        guard let dropIndicator,
              dropIndicator.targetDocumentID == document.id else {
            return .leading
        }
        return dropIndicator.placement == .before ? .leading : .trailing
    }
}

private struct EditorTabDragPreview: View {
    let document: EditorDocument

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: document.url.pathExtension.lowercased() == "bib" ? "books.vertical" : "doc.plaintext")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(document.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if document.isDirty {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }

            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.58), lineWidth: 1)
        }
        .accessibilityLabel("Moving \(document.displayName)")
    }
}

func droppedFilePath(from item: NSSecureCoding?) -> String? {
    if let url = item as? URL {
        return url.path
    }
    if let url = item as? NSURL {
        return url.path
    }
    if let data = item as? Data,
       let value = String(data: data, encoding: .utf8),
       let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
       url.isFileURL {
        return url.path
    }
    if let value = item as? String {
        if let url = URL(string: value), url.isFileURL {
            return url.path
        }
        return value
    }
    return nil
}

private struct ProjectFileDropReceiver: NSViewRepresentable {
    let onDrop: ([URL]) -> Bool
    let onTargeted: (Bool) -> Void

    func makeNSView(context: Context) -> ProjectFileDropReceivingView {
        let view = ProjectFileDropReceivingView()
        view.onDrop = onDrop
        view.onTargeted = onTargeted
        return view
    }

    func updateNSView(_ nsView: ProjectFileDropReceivingView, context: Context) {
        nsView.onDrop = onDrop
        nsView.onTargeted = onTargeted
    }
}

@MainActor
private final class ProjectFileDropReceivingView: NSView {
    var onDrop: (([URL]) -> Bool)?
    var onTargeted: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedFileURLs(from: sender) != nil else { return [] }
        onTargeted?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedFileURLs(from: sender) == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargeted?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onTargeted?(false) }
        guard let urls = draggedFileURLs(from: sender) else { return false }
        return onDrop?(urls) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onTargeted?(false)
    }

    private func draggedFileURLs(from sender: NSDraggingInfo) -> [URL]? {
        let urls = projectFileURLs(from: sender.draggingPasteboard)
        return urls.isEmpty ? nil : urls
    }
}

func projectFileURLs(from pasteboard: NSPasteboard) -> [URL] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
    ]
    let objects = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: options
    ) as? [NSURL] ?? []
    return objects.map { $0 as URL }.filter(\.isFileURL)
}

private struct PDFWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var controller = PDFPreviewController()
    @State private var showsSearch = false
    @State private var pdfSearchText = ""
    @State private var pageText = "1"
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            pdfToolbar
            if showsSearch {
                pdfSearchToolbar
            }
            Divider()

            if let url = model.previewPDFURL {
                PDFPreview(
                    url: url,
                    revision: model.pdfRevision,
                    controller: controller,
                    onDoubleClick: model.jumpSource
                )
            } else if model.buildState == .failure {
                EmptyWorkspaceState(
                    icon: "xmark.circle",
                    title: "Build failed",
                    detail: model.problems.first?.message ?? "Open Problems to inspect the compiler output.",
                    actionTitle: model.showsProblemsPanel ? "View Compiler Log" : "Show Problems",
                    action: {
                        model.problemsPanelTab = model.showsProblemsPanel ? .log : .problems
                        model.showsProblemsPanel = true
                    }
                )
            } else {
                if model.canBuild {
                    EmptyWorkspaceState(
                        icon: "doc.richtext",
                        title: "Build the project to preview the PDF",
                        detail: "The compiled document will appear here.",
                        actionTitle: "Build",
                        action: { model.buildNow() }
                    )
                } else {
                    EmptyWorkspaceState(
                        icon: "doc.richtext",
                        title: "No PDF available",
                        detail: "Add a LaTeX entry file before building."
                    )
                }
            }
        }
        .background(LighTexTheme.pdfBackground)
        .onChange(of: model.pdfJumpToken) { _, _ in
            controller.goTo(model.pdfJumpTarget)
        }
        .onChange(of: controller.currentPage) { _, page in
            if page > 0 { pageText = "\(page)" }
        }
        .onExitCommand {
            if showsSearch {
                showsSearch = false
                pdfSearchText = ""
                controller.search("")
            }
        }
    }

    private var pdfToolbar: some View {
        HStack(spacing: 5) {
            Text("PDF")
                .font(.system(size: 12, weight: .semibold))
            Spacer()

            Button {
                showsSearch.toggle()
                if showsSearch {
                    searchFieldFocused = true
                } else {
                    pdfSearchText = ""
                    controller.search("")
                }
            } label: {
                Image(systemName: showsSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
            }
            .help(showsSearch ? "Close PDF search" : "Search PDF")
            .accessibilityLabel(showsSearch ? "Close PDF search" : "Search PDF")
            .disabled(model.previewPDFURL == nil)

            Button(action: controller.previousPage) {
                Image(systemName: "chevron.up")
            }
            .help("Previous page")
            .accessibilityLabel("Previous page")
            .disabled(model.previewPDFURL == nil)

            HStack(spacing: 3) {
                TextField("Page", text: $pageText)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 24)
                    .onSubmit {
                        if let page = Int(pageText) {
                            controller.goToPage(page)
                        }
                        pageText = "\(max(1, controller.currentPage))"
                    }
                    .accessibilityLabel("PDF page number")
                Text("of \(controller.pageCount)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .frame(minWidth: 58)
            .opacity(model.previewPDFURL == nil ? 0.45 : 1)

            Button(action: controller.nextPage) {
                Image(systemName: "chevron.down")
            }
            .help("Next page")
            .accessibilityLabel("Next page")
            .disabled(model.previewPDFURL == nil)

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 3)

            Button(action: controller.zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")
            .accessibilityLabel("Zoom out")
            .disabled(model.previewPDFURL == nil)

            Text(model.previewPDFURL == nil ? "—" : "\(controller.zoomPercent)%")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 42)

            Button(action: controller.zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
            .accessibilityLabel("Zoom in")
            .disabled(model.previewPDFURL == nil)

            Menu {
                Button("Fit Page", action: controller.fitPage)
                Button("Fit Width", action: controller.fitWidth)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .menuStyle(.borderlessButton)
            .help("PDF scale")
            .accessibilityLabel("PDF scale")
            .disabled(model.previewPDFURL == nil)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(LighTexTheme.secondaryBackground)
    }

    private var pdfSearchToolbar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Find in PDF", text: $pdfSearchText)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .onChange(of: pdfSearchText) { _, query in
                    controller.search(query)
                }
                .onSubmit { controller.nextSearchMatch() }
                .accessibilityLabel("Find in PDF")
            Text(controller.searchMatchCount == 0
                ? "No matches"
                : "\(controller.currentSearchMatch) of \(controller.searchMatchCount)")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 66, alignment: .trailing)
            Button(action: controller.previousSearchMatch) {
                Image(systemName: "chevron.up")
            }
            .disabled(controller.searchMatchCount == 0)
            .help("Previous PDF match")
            .accessibilityLabel("Previous PDF match")
            Button(action: controller.nextSearchMatch) {
                Image(systemName: "chevron.down")
            }
            .disabled(controller.searchMatchCount == 0)
            .help("Next PDF match")
            .accessibilityLabel("Next PDF match")
            Button {
                showsSearch = false
                pdfSearchText = ""
                controller.search("")
            } label: {
                Image(systemName: "xmark")
            }
            .help("Close PDF search")
            .accessibilityLabel("Close PDF search")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(LighTexTheme.secondaryBackground)
    }
}

private struct ProblemsPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var runtimeManager: RuntimeManager
    @State private var confirmsPackageInstall = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Panel", selection: $model.problemsPanelTab) {
                    Text("Problems\(problemCountSuffix)").tag(ProblemsPanelTab.problems)
                    Text("Log").tag(ProblemsPanelTab.log)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)

                Spacer()

                Button {
                    model.showsProblemsPanel = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close panel")
                .accessibilityLabel("Close Problems and Log")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(LighTexTheme.secondaryBackground)

            Divider()

            switch model.problemsPanelTab {
            case .problems:
                problemsList
            case .log:
                buildLog
            }
        }
        .background(Color.white)
        .confirmationDialog(
            "Install TeX Live package?",
            isPresented: $confirmsPackageInstall,
            titleVisibility: .visible
        ) {
            Button("Install Package") {
                model.installMissingPackage()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("LighTex will use the managed runtime's tlmgr to install the package that provides \(model.missingPackageFile ?? "the missing style file").")
        }
    }

    private var problemCountSuffix: String {
        model.diagnosticGroups.isEmpty ? "" : " · \(model.diagnosticGroups.count)"
    }

    @ViewBuilder
    private var problemsList: some View {
        VStack(spacing: 0) {
            if let missingPackageFile = model.missingPackageFile,
               model.settings.texProvider == .managed {
                HStack(spacing: 10) {
                    Label("Missing \(missingPackageFile)", systemImage: "shippingbox")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if runtimeManager.isInstallingPackage {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Install Missing Package") {
                            confirmsPackageInstall = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 38)
                .background(LighTexTheme.secondaryBackground)
                Divider()
            }

            if model.diagnosticGroups.isEmpty {
                EmptyWorkspaceState(
                    icon: "checkmark.circle",
                    title: "No problems",
                    detail: model.buildState == .success
                        ? "The last build completed successfully."
                        : "Compiler errors and warnings will appear here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.diagnosticGroups) { group in
                            DiagnosticGroupRow(group: group)
                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                }
            }
        }
    }

    private var buildLog: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(model.buildLog.isEmpty ? "Compiler output will appear here." : model.buildLog)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .background(Color.white)
    }
}

private struct DiagnosticGroupRow: View {
    @EnvironmentObject private var model: AppModel
    let group: BuildDiagnosticGroup
    @State private var showsRelated = false

    var body: some View {
        VStack(spacing: 0) {
            if group.primary.fileURL != nil {
                Button {
                    model.openProblem(group.primary)
                } label: {
                    problemRow(group.primary, isPrimary: true)
                }
                .buttonStyle(.plain)
            } else {
                problemRow(group.primary, isPrimary: true)
                    .accessibilityElement(children: .combine)
            }

            if !group.related.isEmpty {
                Button {
                    showsRelated.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showsRelated ? 90 : 0))
                        Text("\(group.related.count) related compiler message\(group.related.count == 1 ? "" : "s")")
                        Spacer()
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
                    .padding(.trailing, 10)
                    .frame(height: 25)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsRelated ? "Hide related compiler messages" : "Show related compiler messages")

                if showsRelated {
                    ForEach(group.related) { problem in
                        if problem.fileURL != nil {
                            Button { model.openProblem(problem) } label: {
                                problemRow(problem, isPrimary: false)
                            }
                            .buttonStyle(.plain)
                        } else {
                            problemRow(problem, isPrimary: false)
                        }
                    }
                }
            }
        }
    }

    private func problemRow(_ problem: BuildProblem, isPrimary: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: problem.severity.symbol)
                .foregroundStyle(problem.severity.color)
                .font(.system(size: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(problem.fileDisplayName)
                        .font(.system(size: 12, weight: isPrimary ? .semibold : .medium))
                    if let line = problem.line {
                        Text(":\(line)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(problem.message)
                    .font(.system(size: 12))
                    .foregroundStyle(isPrimary ? .primary : .secondary)
                    .lineLimit(isPrimary ? 3 : 2)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isPrimary ? 8 : 6)
        .contentShape(Rectangle())
        .background(isPrimary ? Color.clear : LighTexTheme.secondaryBackground.opacity(0.55))
        .accessibilityLabel("\(problem.severity.rawValue), \(problem.fileDisplayName), \(problem.message)")
    }
}

private struct WorkspaceStatusBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            if model.isBuilding {
                ProgressView()
                    .controlSize(.mini)
            } else if model.isAutoCompilePending {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: model.buildState.symbol)
                    .foregroundStyle(model.buildState.color)
            }
            if model.isAutoCompilePending {
                Text("Waiting to compile…")
                    .foregroundStyle(.secondary)
            } else {
                Button(model.buildState.label) {
                    model.showsProblemsPanel = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.buildState == .failure ? .red : .secondary)
            }

            Text(settings.latexEngine.label)
                .foregroundStyle(.tertiary)

            Spacer()

            if model.selectedDocument != nil {
                Text("Ln \(model.cursorLine), Col \(model.cursorColumn)")
                    .monospacedDigit()
            }
            Text("UTF-8")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(LighTexTheme.secondaryBackground)
    }
}

private struct EmptyWorkspaceState: View {
    let icon: String
    let title: String
    let detail: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 330)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 3)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum LighTexTheme {
    static let windowBackground = Color.white
    static let sidebarBackground = Color(nsColor: .controlBackgroundColor)
    static let secondaryBackground = Color(nsColor: .windowBackgroundColor)
    static let pdfBackground = Color(nsColor: .underPageBackgroundColor)
    static let hover = Color.black.opacity(0.045)
    static let divider = Color(nsColor: .separatorColor).opacity(0.65)
}
