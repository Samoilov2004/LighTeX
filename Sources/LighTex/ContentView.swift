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
    @State private var creationKind: ProjectItemCreationKind?

    var body: some View {
        VSplitView {
            projectFiles
                .frame(minHeight: 210)

            documentOutline
                .frame(minHeight: 120, idealHeight: 220)
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
                        OutlineNavigatorRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .help("\(item.fileURL.lastPathComponent), line \(item.line)")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(LighTexTheme.sidebarBackground)
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
        if item.isDirectory {
            row
        } else {
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
                .help("Drag to the tab bar to open \(item.name)")
        }
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
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            if item.level == 0 {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.accentColor.opacity(0.72))
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
                    onCursorChange: model.updateCursor,
                    onWordDoubleClick: { line, column in
                        model.jumpPDF(toSource: document.url, line: line, column: column)
                    }
                )
                .id(document.id)
                .clipped()
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
