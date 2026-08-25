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
            CreateProjectSheet()
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
        ToolbarItemGroup(placement: .navigation) {
            if model.hasProject {
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
                // Template projects are intentionally reserved for a later release.
            } label: {
                Label("New from Template", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(true)
            .help("Coming soon")

            Text("Templates are coming soon.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.leading, 3)
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
                        model.clearRecentProjects()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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

private struct CreateProjectSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var projectName = ""
    @State private var location = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first ?? FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Empty Project")
                .font(.system(size: 17, weight: .semibold))

            Text("Creates a clean project with a minimal main.tex document.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Form {
                TextField("Project Name", text: $projectName)

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
                    if model.createProject(name: projectName, location: location) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 470, height: 250)
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

    var body: some View {
        VSplitView {
            projectFiles
                .frame(minHeight: 210)

            documentOutline
                .frame(minHeight: 120, idealHeight: 220)
        }
        .background(LighTexTheme.sidebarBackground)
    }

    @ViewBuilder
    private var projectFiles: some View {
        if model.projectTree.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "doc")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("No supported files")
                    .font(.system(size: 12, weight: .medium))
                Text("Add a .tex file and refresh the project.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else {
            List(selection: $model.navigatorSelection) {
                OutlineGroup(model.projectTree, children: \.children) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.iconName)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(item.name)
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if item.url == model.entryFileURL {
                            Text("MAIN")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(item.url)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !item.isDirectory {
                            model.activateNavigatorItem(item.url)
                        }
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
        }
    }

    private var documentOutline: some View {
        VStack(spacing: 0) {
            HStack {
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
            .frame(height: 30)

            Divider()

            if model.outlineItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No sections yet")
                        .font(.system(size: 12, weight: .medium))
                    Text("Chapters and sections will appear here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
            } else {
                List(model.outlineItems) { item in
                    Button {
                        model.openOutlineItem(item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .frame(width: 12)
                            Text(item.title)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                        }
                        .padding(.leading, CGFloat(item.level) * 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(item.fileURL.lastPathComponent), line \(item.line)")
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(LighTexTheme.sidebarBackground)
    }
}

private struct EditorWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            EditorTabBar()

            if let document = model.selectedDocument {
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
                    jumpLine: document.jumpLine,
                    jumpToken: document.jumpToken,
                    onCursorChange: model.updateCursor
                )
                .id(document.id)
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

private struct EditorTabBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(model.openDocuments) { document in
                        EditorTab(
                            document: document,
                            isActive: document.id == model.selectedDocumentID
                        )
                    }
                }
            }

            if model.openDocuments.count > 1 {
                Menu {
                    ForEach(model.openDocuments) { document in
                        Button {
                            model.selectDocument(document.url)
                        } label: {
                            if document.id == model.selectedDocumentID {
                                Label(document.displayName, systemImage: "checkmark")
                            } else {
                                Text(document.displayName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .help("Show open files")
                .accessibilityLabel("Show open files")
            }
        }
        .background(LighTexTheme.secondaryBackground)
        .frame(height: 34)
    }
}

private struct EditorTab: View {
    @EnvironmentObject private var model: AppModel
    let document: EditorDocument
    let isActive: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            Button {
                model.selectDocument(document.url)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: document.url.pathExtension.lowercased() == "bib" ? "books.vertical" : "doc.plaintext")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(document.displayName)
                        .font(.system(size: 12, weight: isActive ? .medium : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if document.isDirty {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel("Unsaved changes")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(isActive ? Color.white : (isHovering ? LighTexTheme.hover : .clear))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(LighTexTheme.divider)
                .frame(width: 1)
        }
        .onHover { isHovering = $0 }
    }
}

private struct PDFWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var controller = PDFPreviewController()

    var body: some View {
        VStack(spacing: 0) {
            pdfToolbar
            Divider()

            if let url = model.previewPDFURL {
                PDFPreview(
                    url: url,
                    revision: model.pdfRevision,
                    controller: controller
                )
            } else if model.buildState == .failure {
                EmptyWorkspaceState(
                    icon: "xmark.circle",
                    title: "Build failed",
                    detail: model.problems.first?.message ?? "Open Problems to inspect the compiler output.",
                    actionTitle: "Show Problems",
                    action: {
                        model.problemsPanelTab = .problems
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
    }

    private var pdfToolbar: some View {
        HStack(spacing: 5) {
            Text("PDF")
                .font(.system(size: 12, weight: .semibold))
            Spacer()

            Button(action: controller.previousPage) {
                Image(systemName: "chevron.up")
            }
            .help("Previous page")
            .accessibilityLabel("Previous page")
            .disabled(model.previewPDFURL == nil)

            Text(model.previewPDFURL == nil ? "—" : controller.pageLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 54)

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
        model.problems.isEmpty ? "" : " · \(model.problems.count)"
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

            if model.problems.isEmpty {
                EmptyWorkspaceState(
                    icon: "checkmark.circle",
                    title: "No problems",
                    detail: model.buildState == .success
                        ? "The last build completed successfully."
                        : "Compiler errors and warnings will appear here."
                )
            } else {
                List(model.problems) { problem in
                    Button {
                        model.openProblem(problem)
                    } label: {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: problem.severity.symbol)
                                .foregroundStyle(problem.severity.color)
                                .font(.system(size: 13))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(problem.fileDisplayName)
                                        .font(.system(size: 12, weight: .medium))
                                    if let line = problem.line {
                                        Text(":\(line)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(problem.message)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(problem.fileURL == nil)
                }
                .listStyle(.plain)
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
