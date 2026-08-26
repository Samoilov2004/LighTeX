import AppKit
import Combine
import Foundation

enum DocumentMovePlacement: Sendable, Equatable {
    case before
    case after
}

private struct WatchedDocumentSnapshot: Sendable {
    let url: URL
    let revision: DocumentRevision
}

private enum ExternalDocumentObservation: Sendable {
    case loaded(originalURL: URL, currentURL: URL, revision: DocumentRevision, text: String)
    case missing(URL)
}

private struct ExternalRefreshResult: Sendable {
    let tree: [ProjectItem]
    let texFiles: [URL]
    let observations: [ExternalDocumentObservation]
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var projectURL: URL?
    @Published private(set) var projectTree: [ProjectItem] = []
    @Published private(set) var outlineItems: [DocumentOutlineItem] = []
    @Published private(set) var selectedOutlineItemID: String?
    @Published private(set) var projectCompletionIndex: ProjectCompletionIndex = .empty
    @Published private(set) var entryFileURL: URL?
    @Published private(set) var openDocuments: [EditorDocument] = []
    @Published var selectedDocumentID: URL?
    @Published var navigatorSelection: URL?
    @Published var sidebarMode: ProjectSidebarMode {
        didSet { defaults.set(sidebarMode.rawValue, forKey: "ui.projectSidebarMode") }
    }
    @Published var projectSearchQuery = ProjectSearchQuery() {
        didSet { scheduleProjectSearch() }
    }
    @Published var projectSearchReplacement = ""
    @Published private(set) var projectSearchResults: [ProjectSearchResult] = []
    @Published private(set) var projectSearchError: String?
    @Published private(set) var isProjectSearchRunning = false
    @Published private(set) var lastReplaceTransaction: ReplaceTransaction?

    @Published private(set) var previewPDFURL: URL?
    @Published private(set) var pdfRevision = 0
    @Published private(set) var pdfJumpTarget: PDFJumpTarget?
    @Published private(set) var pdfJumpToken = 0
    @Published private(set) var buildState: BuildState = .idle
    @Published private(set) var buildLog = ""
    @Published private(set) var problems: [BuildProblem] = []
    @Published private(set) var diagnosticGroups: [BuildDiagnosticGroup] = []
    @Published private(set) var lastBuildDate: Date?
    @Published private(set) var isAutoCompilePending = false
    @Published private(set) var missingPackageFile: String?

    @Published var showsSidebar = true {
        didSet { UserDefaults.standard.set(showsSidebar, forKey: "ui.showsSidebar") }
    }
    @Published var showsPDF = true {
        didSet { UserDefaults.standard.set(showsPDF, forKey: "ui.showsPDF") }
    }
    @Published var showsProblemsPanel = false
    @Published var problemsPanelTab: ProblemsPanelTab = .problems
    @Published var showsCreateProjectSheet = false
    @Published var showsTemplates = false
    @Published var templateForNewProject: ProjectTemplate?
    @Published var templateSourceDraft: TemplateSourceDraft?
    @Published var showsSettingsPanel = false
    @Published var alertMessage: String?
    @Published private(set) var recentProjects: [RecentProject] = []
    @Published private(set) var userTemplates: [ProjectTemplate] = []
    @Published private(set) var appUpdateState: AppUpdateState = .idle
    @Published private(set) var cursorLine = 1
    @Published private(set) var cursorColumn = 1

    let settings: AppSettings
    let runtimeManager: RuntimeManager
    let templateStore: ProjectTemplateStore
    let dirtyDocumentCoordinator: DirtyDocumentCoordinator

    private var pendingSaveTask: Task<Void, Never>?
    private var pendingBuildTask: Task<Void, Never>?
    private var pendingOutlineTask: Task<Void, Never>?
    private var pendingSearchTask: Task<Void, Never>?
    private var pendingCompletionTask: Task<Void, Never>?
    private var outlineCache: [URL: [DocumentOutlineItem]] = [:]
    private var completionSymbols: [URL: CompletionFileSymbols] = [:]
    private var buildQueuedWhileBuilding = false
    private var runtimeCancellable: AnyCancellable?
    private var projectFileMonitor: ProjectFileMonitor?
    private var externalRefreshTask: Task<Void, Never>?
    private var pendingExternalText: [URL: String] = [:]
    private var pendingExternalRevision: [URL: DocumentRevision] = [:]
    private var runtimeWasReady = false
    private let defaults: UserDefaults
    private let recentProjectsKey = "recentProjects.v1"
    private let lastProjectPathKey = "lastProjectPath"

    var isBuilding: Bool { buildState == .building }
    var hasProject: Bool { projectURL != nil }
    var canBuild: Bool {
        projectURL != nil
            && entryFileURL != nil
            && !isBuilding
            && runtimeManager.supports(engine: settings.latexEngine, tool: settings.buildTool)
    }
    var projectName: String { projectURL?.lastPathComponent ?? "LighTex" }

    var selectedDocument: EditorDocument? {
        guard let selectedDocumentID else { return nil }
        return openDocuments.first { $0.id == selectedDocumentID }
    }

    var selectedRelativePath: String {
        guard let url = selectedDocumentID, let projectURL else { return "No file selected" }
        return ProjectScanner.relativePath(for: url, inside: projectURL)
    }

    var entryRelativePath: String {
        guard let entryFileURL, let projectURL else { return "No entry file" }
        return ProjectScanner.relativePath(for: entryFileURL, inside: projectURL)
    }

    init(
        settings: AppSettings,
        runtimeManager: RuntimeManager,
        defaults: UserDefaults = .standard,
        templateStore: ProjectTemplateStore? = nil,
        dirtyDocumentCoordinator: DirtyDocumentCoordinator? = nil
    ) {
        self.settings = settings
        self.runtimeManager = runtimeManager
        self.defaults = defaults
        self.templateStore = templateStore ?? ProjectTemplateStore()
        self.dirtyDocumentCoordinator = dirtyDocumentCoordinator ?? DirtyDocumentCoordinator()
        sidebarMode = defaults.string(forKey: "ui.projectSidebarMode")
            .flatMap(ProjectSidebarMode.init(rawValue:)) ?? .files
        showsSidebar = defaults.object(forKey: "ui.showsSidebar") as? Bool ?? true
        showsPDF = defaults.object(forKey: "ui.showsPDF") as? Bool ?? true
        recentProjects = loadRecentProjects()
        userTemplates = self.templateStore.loadUserTemplates()
        runtimeCancellable = runtimeManager.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
                let ready = self.runtimeManager.isSetupComplete
                if ready, !self.runtimeWasReady,
                   self.settings.automaticBuilds,
                   self.entryFileURL != nil {
                    self.buildNow()
                }
                self.runtimeWasReady = ready
            }
        }

        if let argument = CommandLine.arguments.dropFirst().first {
            let url = URL(fileURLWithPath: argument, isDirectory: true)
            if isExistingDirectory(url) {
                openProject(url)
                return
            }
        }

        if settings.openLastProject,
           let path = defaults.string(forKey: lastProjectPathKey) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if isExistingDirectory(url) {
                openProject(url)
            }
        }
    }

    convenience init(
        settings: AppSettings,
        defaults: UserDefaults = .standard,
        templateStore: ProjectTemplateStore? = nil,
        dirtyDocumentCoordinator: DirtyDocumentCoordinator? = nil
    ) {
        self.init(
            settings: settings,
            runtimeManager: RuntimeManager(settings: settings, startsAutomatically: false),
            defaults: defaults,
            templateStore: templateStore,
            dirtyDocumentCoordinator: dirtyDocumentCoordinator
        )
    }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = "Open Existing Project"
        panel.message = "Choose a local folder containing your LaTeX sources."
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            openProject(url)
        }
    }

    func chooseProjectLocation(current: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Project Location"
        panel.message = "The new project folder will be created inside this location."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = current ?? FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first
        return panel.runModal() == .OK ? panel.url : nil
    }

    func createProject(name: String, location: URL) -> Bool {
        createProject(
            from: .emptyProject,
            name: name,
            author: "",
            location: location
        )
    }

    func createProject(
        from template: ProjectTemplate,
        name: String,
        author: String,
        location: URL
    ) -> Bool {
        do {
            let project = try templateStore.instantiate(
                template: template,
                projectName: name,
                author: author,
                location: location
            )
            showsCreateProjectSheet = false
            templateForNewProject = nil
            showsTemplates = false
            openProject(project)
            return true
        } catch {
            alertMessage = "LighTex could not create the project: \(error.localizedDescription)"
            return false
        }
    }

    func showTemplateLibrary() {
        userTemplates = templateStore.loadUserTemplates()
        showsTemplates = true
    }

    func closeTemplateLibrary() {
        showsTemplates = false
    }

    func beginCreatingProject(from template: ProjectTemplate) {
        templateForNewProject = template
    }

    func chooseTemplateSourceFolder() {
        let panel = NSOpenPanel()
        panel.title = "Create Personal Template"
        panel.message = "Choose a project folder to copy into your personal template library."
        panel.prompt = "Choose Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            templateSourceDraft = TemplateSourceDraft(
                sourceURL: url.standardizedFileURL,
                suggestedName: url.lastPathComponent
            )
        }
    }

    func beginSavingCurrentProjectAsTemplate() {
        guard let projectURL else { return }
        saveAllDocuments()
        templateSourceDraft = TemplateSourceDraft(
            sourceURL: projectURL,
            suggestedName: projectURL.lastPathComponent
        )
    }

    func savePersonalTemplate(name: String, summary: String) -> Bool {
        guard let draft = templateSourceDraft else { return false }
        do {
            let template = try templateStore.saveUserTemplate(
                from: draft.sourceURL,
                name: name,
                summary: summary
            )
            userTemplates = templateStore.loadUserTemplates()
            templateSourceDraft = nil
            alertMessage = "Template “\(template.name)” was saved to Yours."
            if let configuration = try? runtimeManager.buildConfiguration(
                engine: settings.latexEngine,
                tool: settings.buildTool
            ) {
                Task { [weak self] in
                    await TemplatePreviewService.generate(
                        for: template,
                        configuration: configuration
                    )
                    guard let self else { return }
                    self.userTemplates = self.templateStore.loadUserTemplates()
                }
            }
            return true
        } catch {
            alertMessage = "LighTex could not create the template: \(error.localizedDescription)"
            return false
        }
    }

    func templateCopyReview(for sourceURL: URL) -> TemplateCopyReview? {
        try? templateStore.reviewProjectContents(from: sourceURL)
    }

    func checkForAppUpdates() {
        guard appUpdateState != .checking else { return }
        appUpdateState = .checking
        let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
        Task { [weak self] in
            let result = await AppUpdateService.check(currentVersion: currentVersion)
            self?.appUpdateState = result
        }
    }

    func openAvailableAppUpdate() {
        guard case let .available(_, releaseURL) = appUpdateState else { return }
        NSWorkspace.shared.open(releaseURL)
    }

    func deletePersonalTemplate(_ template: ProjectTemplate) {
        do {
            try templateStore.deleteUserTemplate(template)
            userTemplates = templateStore.loadUserTemplates()
        } catch {
            alertMessage = "LighTex could not delete the template: \(error.localizedDescription)"
        }
    }

    func revealPersonalTemplate(_ template: ProjectTemplate) {
        guard let directory = template.userDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func openRecentProject(_ project: RecentProject) {
        guard isExistingDirectory(project.url) else {
            removeRecentProject(project)
            alertMessage = "That project folder is no longer available. It was removed from Recent Projects."
            return
        }
        openProject(project.url)
    }

    func removeRecentProject(_ project: RecentProject) {
        recentProjects.removeAll { $0.path == project.path }
        persistRecentProjects()
    }

    func clearRecentProjects() {
        recentProjects.removeAll()
        persistRecentProjects()
    }

    @discardableResult
    func openProject(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        if let currentProject = projectURL,
           currentProject != standardizedURL,
           !approveClose(kind: .switchProject(standardizedURL)) {
            return false
        }
        stopMonitoringProject()
        pendingSaveTask?.cancel()
        pendingBuildTask?.cancel()
        pendingOutlineTask?.cancel()
        pendingSearchTask?.cancel()
        pendingCompletionTask?.cancel()
        buildQueuedWhileBuilding = false

        showsTemplates = false
        projectURL = standardizedURL
        projectTree = ProjectScanner.projectTree(in: standardizedURL)
        let texFiles = ProjectScanner.texFiles(in: standardizedURL)
        entryFileURL = restoredEntryFile(in: standardizedURL, candidates: texFiles)
        openDocuments = []
        outlineCache = [:]
        selectedOutlineItemID = nil
        projectSearchResults = []
        projectSearchError = nil
        lastReplaceTransaction = nil
        completionSymbols = [:]
        projectCompletionIndex = .empty
        selectedDocumentID = nil
        navigatorSelection = nil
        buildLog = ""
        problems = []
        diagnosticGroups = []
        missingPackageFile = nil
        buildState = .idle
        isAutoCompilePending = false
        showsProblemsPanel = false

        if let entryFileURL {
            let existingPDF = entryFileURL.deletingPathExtension().appendingPathExtension("pdf")
            let cachedPDF = try? LatexBuildService.cacheDirectory(
                projectURL: standardizedURL,
                entryFileURL: entryFileURL
            )
            .appendingPathComponent(entryFileURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("pdf")
            if let cachedPDF, FileManager.default.fileExists(atPath: cachedPDF.path) {
                previewPDFURL = cachedPDF
                pdfRevision += 1
            } else if FileManager.default.fileExists(atPath: existingPDF.path) {
                previewPDFURL = existingPDF
                pdfRevision += 1
            } else {
                previewPDFURL = nil
            }
        } else {
            previewPDFURL = nil
        }

        defaults.set(standardizedURL.path, forKey: lastProjectPathKey)
        updateRecentProjects(with: standardizedURL)
        restoreOpenDocuments()

        if openDocuments.isEmpty, let entryFileURL {
            openDocument(entryFileURL)
        }

        refreshOutline()
        refreshCompletionIndex()
        startMonitoringProject(standardizedURL)

        if settings.automaticBuilds,
           entryFileURL != nil,
           runtimeManager.isSetupComplete {
            buildNow()
        }
        return true
    }

    func closeProject() {
        guard approveClose(kind: .project) else { return }
        performCloseProject()
    }

    private func performCloseProject() {
        persistOpenDocuments()
        stopMonitoringProject()
        pendingSaveTask?.cancel()
        pendingBuildTask?.cancel()
        pendingOutlineTask?.cancel()
        pendingSearchTask?.cancel()
        pendingCompletionTask?.cancel()
        buildQueuedWhileBuilding = false
        projectURL = nil
        showsTemplates = false
        projectTree = []
        outlineItems = []
        outlineCache = [:]
        selectedOutlineItemID = nil
        projectSearchResults = []
        projectSearchError = nil
        lastReplaceTransaction = nil
        completionSymbols = [:]
        projectCompletionIndex = .empty
        entryFileURL = nil
        openDocuments = []
        selectedDocumentID = nil
        navigatorSelection = nil
        previewPDFURL = nil
        pdfJumpTarget = nil
        buildState = .idle
        isAutoCompilePending = false
        buildLog = ""
        problems = []
        diagnosticGroups = []
        missingPackageFile = nil
        showsProblemsPanel = false
        defaults.removeObject(forKey: lastProjectPathKey)
    }

    func refreshProject() {
        guard let projectURL else { return }
        projectTree = ProjectScanner.projectTree(in: projectURL)
        let texFiles = ProjectScanner.texFiles(in: projectURL)
        if entryFileURL == nil || !FileManager.default.fileExists(atPath: entryFileURL?.path ?? "") {
            entryFileURL = ProjectScanner.preferredEntryPoint(from: texFiles)
        }
        refreshOutline()
        refreshCompletionIndex()
    }

    func activateNavigatorItem(_ url: URL) {
        guard let item = findProjectItem(url: url, in: projectTree), !item.isDirectory else { return }
        if item.isEditableText {
            openDocument(url)
        } else if url.pathExtension.lowercased() == "pdf" {
            previewPDFURL = url
            pdfRevision += 1
            showsPDF = true
        }
    }

    func openDocument(_ url: URL, line: Int? = nil) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            alertMessage = "The file \(url.lastPathComponent) no longer exists."
            refreshProject()
            return
        }

        if let index = openDocuments.firstIndex(where: { $0.url == url }) {
            selectedDocumentID = url
            navigatorSelection = url
            if let line {
                openDocuments[index].jumpLine = line
                openDocuments[index].jumpToken += 1
            }
            return
        }

        do {
            let loaded = try DocumentRevision.read(from: url)
            openDocuments.append(EditorDocument(
                url: url,
                text: loaded.text,
                isDirty: false,
                jumpLine: line,
                jumpToken: line == nil ? 0 : 1,
                revision: loaded.revision
            ))
            selectedDocumentID = url
            navigatorSelection = url
            persistOpenDocuments()
        } catch {
            alertMessage = "LighTex could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func selectDocument(_ url: URL) {
        guard openDocuments.contains(where: { $0.url == url }) else { return }
        selectedDocumentID = url
        navigatorSelection = url
        persistOpenDocuments()
    }

    func closeDocument(_ url: URL) {
        guard approveClose(kind: .document(url)) else { return }
        performCloseDocument(url)
    }

    private func performCloseDocument(_ url: URL) {
        guard let index = openDocuments.firstIndex(where: { $0.url == url }) else { return }
        let wasSelected = selectedDocumentID == url
        openDocuments.remove(at: index)

        if wasSelected {
            if openDocuments.indices.contains(index) {
                selectedDocumentID = openDocuments[index].url
            } else {
                selectedDocumentID = openDocuments.last?.url
            }
            navigatorSelection = selectedDocumentID
        }
        pendingExternalText[url] = nil
        pendingExternalRevision[url] = nil
        persistOpenDocuments()
    }

    func moveDocument(
        _ sourceURL: URL,
        relativeTo targetURL: URL,
        placement: DocumentMovePlacement
    ) {
        guard sourceURL != targetURL,
              let sourceIndex = openDocuments.firstIndex(where: { $0.url == sourceURL }),
              openDocuments.contains(where: { $0.url == targetURL }) else {
            return
        }

        let document = openDocuments.remove(at: sourceIndex)
        guard let targetIndex = openDocuments.firstIndex(where: { $0.url == targetURL }) else {
            openDocuments.insert(document, at: min(sourceIndex, openDocuments.count))
            return
        }
        let insertionIndex = placement == .before ? targetIndex : targetIndex + 1
        openDocuments.insert(document, at: min(insertionIndex, openDocuments.count))
        persistOpenDocuments()
    }

    @discardableResult
    func openDroppedProjectItem(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let item = findProjectItem(url: url, in: projectTree), !item.isDirectory else {
            return false
        }
        activateNavigatorItem(url)
        return selectedDocumentID == url
    }

    func createProjectFile(named name: String) -> Bool {
        guard let name = Self.validProjectItemName(name),
              let directory = selectedProjectDirectory else {
            alertMessage = "Enter a valid file name without path separators."
            return false
        }

        let fileURL = directory.appendingPathComponent(name, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            alertMessage = "An item named \(name) already exists in this folder."
            return false
        }

        guard FileManager.default.createFile(atPath: fileURL.path, contents: Data()) else {
            alertMessage = "LighTex could not create \(name)."
            return false
        }

        refreshProject()
        if let item = findProjectItem(url: fileURL, in: projectTree), item.isEditableText {
            openDocument(fileURL)
        }
        return true
    }

    func createProjectFolder(named name: String) -> Bool {
        guard let name = Self.validProjectItemName(name),
              let directory = selectedProjectDirectory else {
            alertMessage = "Enter a valid folder name without path separators."
            return false
        }

        let folderURL = directory.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folderURL.path) else {
            alertMessage = "An item named \(name) already exists in this folder."
            return false
        }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            refreshProject()
            navigatorSelection = folderURL
            return true
        } catch {
            alertMessage = "LighTex could not create \(name): \(error.localizedDescription)"
            return false
        }
    }

    func importProjectFiles() {
        guard let directory = selectedProjectDirectory else { return }
        let panel = NSOpenPanel()
        panel.title = "Add Files to Project"
        panel.message = "Files are copied into \(directory.lastPathComponent)."
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }
        var imported: [URL] = []
        var skipped: [String] = []

        for sourceURL in panel.urls {
            let destinationURL = directory.appendingPathComponent(sourceURL.lastPathComponent)
            guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL,
                  !FileManager.default.fileExists(atPath: destinationURL.path) else {
                skipped.append(sourceURL.lastPathComponent)
                continue
            }
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                imported.append(destinationURL)
            } catch {
                skipped.append(sourceURL.lastPathComponent)
            }
        }

        refreshProject()
        if let firstEditable = imported.first(where: {
            findProjectItem(url: $0, in: projectTree)?.isEditableText == true
        }) {
            openDocument(firstEditable)
        }
        if !skipped.isEmpty {
            alertMessage = "These files were not added because they already exist or could not be copied: \(skipped.joined(separator: ", "))."
        }
    }

    func renameProjectItem(_ url: URL, to proposedName: String) -> Bool {
        guard let name = Self.validProjectItemName(proposedName),
              isInsideProject(url),
              url != projectURL else {
            alertMessage = "Enter a valid name without path separators."
            return false
        }
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: findProjectItem(url: url, in: projectTree)?.isDirectory == true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            alertMessage = "An item named \(name) already exists in this folder."
            return false
        }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            migrateOpenDocumentURLs(from: url, to: destination)
            if navigatorSelection == url { navigatorSelection = destination }
            refreshProject()
            runProjectSearchNow()
            return true
        } catch {
            alertMessage = "LighTex could not rename \(url.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    func duplicateProjectItem(_ url: URL) {
        guard isInsideProject(url), url != projectURL else { return }
        let destination = uniqueDuplicateURL(for: url)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            refreshProject()
            navigatorSelection = destination
        } catch {
            alertMessage = "LighTex could not duplicate \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func moveProjectItemToTrash(_ url: URL) {
        guard isInsideProject(url), url != projectURL else { return }
        let affectedDocuments = openDocuments.filter { documentURL($0.url, isInside: url) }
        guard approveDocuments(affectedDocuments.filter(\.isDirty), kind: .project) else { return }

        NSWorkspace.shared.recycle([url]) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.alertMessage = "LighTex could not move \(url.lastPathComponent) to the Trash: \(error.localizedDescription)"
                    return
                }
                for document in affectedDocuments {
                    self.performCloseDocument(document.url)
                }
                self.refreshProject()
                self.runProjectSearchNow()
            }
        }
    }

    @discardableResult
    func dropProjectItems(_ sourceURLs: [URL], into directoryURL: URL) -> Bool {
        guard isInsideProject(directoryURL),
              directoryURL == projectURL || findProjectItem(url: directoryURL, in: projectTree)?.isDirectory == true else {
            return false
        }
        var skipped: [String] = []
        var changed = false

        for rawSource in sourceURLs {
            let source = rawSource.standardizedFileURL
            let destination = directoryURL.appendingPathComponent(source.lastPathComponent)
            guard source != destination,
                  !FileManager.default.fileExists(atPath: destination.path),
                  !directoryURL.path.hasPrefix(source.path + "/") else {
                skipped.append(source.lastPathComponent)
                continue
            }
            do {
                if isInsideProject(source) {
                    try FileManager.default.moveItem(at: source, to: destination)
                    migrateOpenDocumentURLs(from: source, to: destination)
                } else {
                    try FileManager.default.copyItem(at: source, to: destination)
                }
                changed = true
            } catch {
                skipped.append(source.lastPathComponent)
            }
        }
        if changed {
            refreshProject()
            runProjectSearchNow()
        }
        if !skipped.isEmpty {
            alertMessage = "These items were not added because a destination already exists or the move failed: \(skipped.joined(separator: ", "))."
        }
        return changed
    }

    static func validProjectItemName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains(":") else {
            return nil
        }
        return trimmed
    }

    func updateSelectedText(_ text: String) {
        guard let selectedDocumentID,
              let index = openDocuments.firstIndex(where: { $0.url == selectedDocumentID }),
              openDocuments[index].text != text else {
            return
        }
        openDocuments[index].text = text
        openDocuments[index].isDirty = true
        scheduleOutlineRefresh(
            for: selectedDocumentID,
            text: text
        )
        scheduleCompletionRefresh(for: selectedDocumentID, text: text)
        if sidebarMode == .search, !projectSearchQuery.isEmpty {
            scheduleProjectSearch()
        }
        scheduleSave(for: selectedDocumentID)
        scheduleAutomaticBuild()
    }

    func saveSelectedDocument() {
        guard let selectedDocumentID else { return }
        _ = saveDocument(selectedDocumentID)
    }

    @discardableResult
    func saveAllDocuments() -> DocumentSaveResult {
        for url in openDocuments.map(\.url) {
            let result = saveDocument(url)
            if case .failed = result { return result }
        }
        return .saved
    }

    func setEntryFile(_ url: URL) {
        guard url.pathExtension.lowercased() == "tex" else { return }
        entryFileURL = url
        let existingPDF = url.deletingPathExtension().appendingPathExtension("pdf")
        previewPDFURL = FileManager.default.fileExists(atPath: existingPDF.path) ? existingPDF : nil
        if previewPDFURL != nil { pdfRevision += 1 }
        persistEntryFile()
    }

    func buildNow() {
        pendingBuildTask?.cancel()
        pendingBuildTask = nil
        isAutoCompilePending = false
        Task { await performBuild() }
    }

    func performBuild() async {
        guard !isBuilding else {
            buildQueuedWhileBuilding = true
            return
        }
        guard let projectURL else { return }
        guard let entryFileURL else {
            problems = [BuildProblem(
                severity: .error,
                fileURL: nil,
                fileDisplayName: "Project",
                line: nil,
                message: "No LaTeX entry file was found. Add main.tex or a document containing \\documentclass."
            )]
            diagnosticGroups = BuildProblemParser.groups(
                from: problems,
                missingPackageFile: nil
            )
            buildState = .failure
            problemsPanelTab = .problems
            showsProblemsPanel = true
            return
        }

        let saveResult = saveAllDocuments()
        guard saveResult.succeeded else {
            buildState = .failure
            return
        }
        let configuration: BuildConfiguration
        do {
            configuration = try runtimeManager.buildConfiguration(
                engine: settings.latexEngine,
                tool: settings.buildTool
            )
        } catch {
            buildLog = error.localizedDescription
            problems = [BuildProblem(
                severity: .error,
                fileURL: nil,
                fileDisplayName: "Compiler",
                line: nil,
                message: error.localizedDescription
            )]
            diagnosticGroups = BuildProblemParser.groups(
                from: problems,
                missingPackageFile: nil
            )
            buildState = .failure
            problemsPanelTab = .problems
            showsProblemsPanel = true
            return
        }
        buildState = .building
        buildLog = "Building \(entryRelativePath) with \(settings.latexEngine.label)…"
        problems = []
        diagnosticGroups = []
        missingPackageFile = nil

        let result = await LatexBuildService.build(
            projectURL: projectURL,
            entryFileURL: entryFileURL,
            configuration: configuration
        )

        guard self.projectURL == projectURL,
              self.entryFileURL == entryFileURL else {
            return
        }

        buildLog = result.log
        problems = result.problems
        missingPackageFile = result.missingPackageFile
        diagnosticGroups = BuildProblemParser.groups(
            from: result.problems,
            missingPackageFile: result.missingPackageFile
        )
        if result.succeeded {
            previewPDFURL = result.previewPDF
            pdfRevision += 1
            buildState = .success
            lastBuildDate = Date()
            if problems.contains(where: { $0.severity == .warning }) {
                problemsPanelTab = .problems
            }
        } else {
            buildState = .failure
            problemsPanelTab = problems.isEmpty ? .log : .problems
            if settings.showLogOnFailure {
                showsProblemsPanel = true
            }
        }

        if buildQueuedWhileBuilding, settings.automaticBuilds {
            buildQueuedWhileBuilding = false
            Task { await performBuild() }
        }
    }

    func installMissingPackage() {
        guard let missingPackageFile else { return }
        runtimeManager.installMissingPackage(for: missingPackageFile) { [weak self] succeeded in
            guard let self, succeeded else { return }
            self.missingPackageFile = nil
            self.buildNow()
        }
    }

    func setAutomaticBuilds(_ enabled: Bool) {
        settings.automaticBuilds = enabled
        if enabled {
            scheduleAutomaticBuild()
        } else {
            pendingBuildTask?.cancel()
            pendingBuildTask = nil
            buildQueuedWhileBuilding = false
            isAutoCompilePending = false
        }
    }

    func openOutlineItem(_ item: DocumentOutlineItem) {
        selectedOutlineItemID = item.id
        openDocument(item.fileURL, line: item.line)
        jumpPDF(toSource: item.fileURL, line: item.line, column: 1)
    }

    func jumpPDF(toSource sourceURL: URL, line: Int, column: Int) {
        guard let previewPDFURL, let projectURL else { return }
        let syncTeXURL = runtimeManager.syncTeXURL

        Task { [weak self] in
            let target = await SyncTeXService.target(
                forSource: sourceURL,
                line: line,
                column: column,
                previewPDFURL: previewPDFURL,
                projectURL: projectURL,
                executableURL: syncTeXURL
            )
            guard let self, self.projectURL == projectURL, let target else { return }
            self.pdfJumpTarget = target
            self.pdfJumpToken += 1
            self.showsPDF = true
        }
    }

    func jumpSource(fromPDFPage page: Int, x: Double, yFromTop: Double) {
        guard let previewPDFURL, let projectURL else { return }
        let syncTeXURL = runtimeManager.syncTeXURL
        Task { [weak self] in
            let target = await SyncTeXService.sourceTarget(
                forPDF: previewPDFURL,
                page: page,
                x: x,
                yFromTop: yFromTop,
                projectURL: projectURL,
                executableURL: syncTeXURL
            )
            guard let self, self.projectURL == projectURL, let target else { return }
            guard self.isInsideProject(target.fileURL),
                  FileManager.default.fileExists(atPath: target.fileURL.path) else {
                self.alertMessage = "SyncTeX pointed to a source file outside this project."
                return
            }
            self.openDocument(target.fileURL, line: target.line)
            self.updateCursor(line: target.line, column: target.column)
        }
    }

    func openProblem(_ problem: BuildProblem) {
        guard let fileURL = problem.fileURL else { return }
        openDocument(fileURL, line: problem.line)
    }

    func updateCursor(line: Int, column: Int) {
        if cursorLine != line {
            cursorLine = line
        }
        if cursorColumn != column {
            cursorColumn = column
        }
        updateCurrentOutlineSelection()
    }

    func showProjectSearch() {
        showsSidebar = true
        sidebarMode = .search
    }

    func runProjectSearchNow() {
        scheduleProjectSearch(immediately: true)
    }

    func openSearchResult(_ result: ProjectSearchResult) {
        openDocument(result.fileURL, line: result.line)
    }

    func replaceAllProjectSearchResults() {
        guard let projectURL, !projectSearchQuery.isEmpty else { return }
        let query = projectSearchQuery
        let replacement = projectSearchReplacement
        let openSources = Dictionary(uniqueKeysWithValues: openDocuments.map { ($0.url, $0.text) })
        isProjectSearchRunning = true
        projectSearchError = nil
        Task { [weak self] in
            do {
                let transaction = try await Task.detached(priority: .userInitiated) {
                    try ProjectSearchService.replacementTransaction(
                        projectURL: projectURL,
                        query: query,
                        replacement: replacement,
                        openSources: openSources
                    )
                }.value
                guard let self, self.projectURL == projectURL else { return }
                try self.applyReplaceTransaction(transaction, undoing: false)
                self.lastReplaceTransaction = transaction.changes.isEmpty ? nil : transaction
                self.isProjectSearchRunning = false
                self.refreshOutline()
                self.runProjectSearchNow()
            } catch {
                self?.isProjectSearchRunning = false
                self?.projectSearchError = error.localizedDescription
            }
        }
    }

    func undoLastProjectReplace() {
        guard let transaction = lastReplaceTransaction else { return }
        do {
            try applyReplaceTransaction(transaction, undoing: true)
            lastReplaceTransaction = nil
            refreshOutline()
            runProjectSearchNow()
        } catch {
            projectSearchError = error.localizedDescription
        }
    }

    func confirmApplicationTermination() -> Bool {
        approveClose(kind: .application)
    }

    func reloadExternalVersion(of url: URL) {
        guard let index = openDocuments.firstIndex(where: { $0.url == url }) else { return }
        if let text = pendingExternalText[url], let revision = pendingExternalRevision[url] {
            openDocuments[index].text = text
            openDocuments[index].revision = revision
            openDocuments[index].isDirty = false
            openDocuments[index].externalChangeState = .none
            pendingExternalText[url] = nil
            pendingExternalRevision[url] = nil
            refreshOutline()
            return
        }
        do {
            let loaded = try DocumentRevision.read(from: url)
            openDocuments[index].text = loaded.text
            openDocuments[index].revision = loaded.revision
            openDocuments[index].isDirty = false
            openDocuments[index].externalChangeState = .none
            refreshOutline()
        } catch {
            alertMessage = "LighTex could not reload \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func keepLocalVersion(of url: URL) {
        guard let index = openDocuments.firstIndex(where: { $0.url == url }) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace the version on disk?"
        alert.informativeText = "The external changes to \(url.lastPathComponent) will be overwritten by the text currently open in LighTex."
        alert.addButton(withTitle: "Keep Mine")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        openDocuments[index].externalChangeState = .none
        let result = saveDocument(url)
        if result.succeeded {
            pendingExternalText[url] = nil
            pendingExternalRevision[url] = nil
        } else {
            openDocuments[index].externalChangeState = .modified
        }
    }

    func saveConflictedCopy(of url: URL) {
        guard let index = openDocuments.firstIndex(where: { $0.url == url }) else { return }
        let panel = NSSavePanel()
        panel.title = "Save a Copy of \(url.lastPathComponent)"
        panel.directoryURL = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let suffix = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
        panel.nameFieldStringValue = "\(base) local copy\(suffix)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try openDocuments[index].text.write(to: destination, atomically: true, encoding: .utf8)
            reloadExternalVersion(of: url)
            refreshProject()
            if isInsideProject(destination) {
                openDocument(destination)
            }
        } catch {
            alertMessage = "LighTex could not save the copy: \(error.localizedDescription)"
        }
    }

    func saveDeletedDocumentAs(_ url: URL) {
        guard let index = openDocuments.firstIndex(where: { $0.url == url }) else { return }
        let panel = NSSavePanel()
        panel.title = "Save Missing Document As"
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = url.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try openDocuments[index].text.write(to: destination, atomically: true, encoding: .utf8)
            let loaded = try DocumentRevision.read(from: destination)
            replaceDocumentURL(at: index, with: destination)
            openDocuments[index].text = loaded.text
            openDocuments[index].revision = loaded.revision
            openDocuments[index].isDirty = false
            openDocuments[index].externalChangeState = .none
            refreshProject()
        } catch {
            alertMessage = "LighTex could not save the document: \(error.localizedDescription)"
        }
    }

    func closeDeletedDocument(_ url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Close without saving?"
        alert.informativeText = "The file no longer exists on disk. Any text still open in LighTex will be lost."
        alert.addButton(withTitle: "Close Without Saving")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        performCloseDocument(url)
    }

    func revealProjectInFinder() {
        guard let projectURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    func revealSelectedFileInFinder() {
        guard let selectedDocumentID else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedDocumentID])
    }

    func revealPDFInFinder() {
        guard let previewPDFURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([previewPDFURL])
    }

    @discardableResult
    private func saveDocument(_ url: URL) -> DocumentSaveResult {
        guard let index = openDocuments.firstIndex(where: { $0.url == url }),
              openDocuments[index].isDirty else {
            return .notNeeded
        }
        guard openDocuments[index].externalChangeState == .none else {
            let message = "Resolve the external change for \(url.lastPathComponent) before saving."
            alertMessage = message
            return .failed(message)
        }
        do {
            try openDocuments[index].text.write(to: url, atomically: true, encoding: .utf8)
            openDocuments[index].revision = try DocumentRevision.make(
                for: url,
                text: openDocuments[index].text
            )
            openDocuments[index].isDirty = false
            return .saved
        } catch {
            let message = "LighTex could not save \(url.lastPathComponent): \(error.localizedDescription)"
            alertMessage = message
            return .failed(message)
        }
    }

    private func approveClose(kind: CloseRequestKind) -> Bool {
        let documents: [EditorDocument]
        switch kind {
        case let .document(url):
            documents = openDocuments.filter { $0.url == url && $0.isDirty }
        case .project, .switchProject, .application:
            documents = openDocuments.filter(\.isDirty)
        }
        return approveDocuments(documents, kind: kind)
    }

    private func approveDocuments(
        _ documents: [EditorDocument],
        kind: CloseRequestKind
    ) -> Bool {
        guard !documents.isEmpty else { return true }
        let request = CloseRequest(
            kind: kind,
            documentNames: documents.map(\.displayName)
        )
        switch dirtyDocumentCoordinator.decision(for: request) {
        case .discard:
            return true
        case .cancel:
            return false
        case .save:
            for document in documents {
                if !saveDocument(document.url).succeeded { return false }
            }
            return true
        }
    }

    private func startMonitoringProject(_ url: URL) {
        let monitor = ProjectFileMonitor(rootURL: url) { [weak self] in
            self?.projectFilesDidChange()
        }
        projectFileMonitor = monitor
        monitor.start()
    }

    private func stopMonitoringProject() {
        projectFileMonitor?.stop()
        projectFileMonitor = nil
        externalRefreshTask?.cancel()
        externalRefreshTask = nil
        pendingExternalText.removeAll()
        pendingExternalRevision.removeAll()
    }

    private func projectFilesDidChange() {
        guard let projectURL else { return }
        externalRefreshTask?.cancel()
        let snapshots = openDocuments.map {
            WatchedDocumentSnapshot(url: $0.url, revision: $0.revision)
        }
        externalRefreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Self.inspectProjectChanges(projectURL: projectURL, documents: snapshots)
            }.value
            guard !Task.isCancelled, let self, self.projectURL == projectURL else { return }
            self.applyExternalRefresh(result)
        }
    }

    nonisolated private static func inspectProjectChanges(
        projectURL: URL,
        documents: [WatchedDocumentSnapshot]
    ) -> ExternalRefreshResult {
        let tree = ProjectScanner.projectTree(in: projectURL)
        let files = ProjectScanner.files(in: projectURL)
        let texFiles = files.filter { $0.pathExtension.lowercased() == "tex" }
        var urlsByIdentifier: [String: URL] = [:]
        for url in files {
            if let identifier = DocumentRevision.fileIdentifier(for: url) {
                urlsByIdentifier[identifier] = url
            }
        }

        let observations = documents.compactMap { snapshot -> ExternalDocumentObservation? in
            let currentURL: URL
            if FileManager.default.fileExists(atPath: snapshot.url.path) {
                currentURL = snapshot.url
            } else if let identifier = snapshot.revision.fileIdentifier,
                      let movedURL = urlsByIdentifier[identifier] {
                currentURL = movedURL
            } else {
                return .missing(snapshot.url)
            }
            guard let loaded = try? DocumentRevision.read(from: currentURL) else { return nil }
            return .loaded(
                originalURL: snapshot.url,
                currentURL: currentURL,
                revision: loaded.revision,
                text: loaded.text
            )
        }
        return ExternalRefreshResult(tree: tree, texFiles: texFiles, observations: observations)
    }

    private func applyExternalRefresh(_ result: ExternalRefreshResult) {
        projectTree = result.tree
        for observation in result.observations {
            switch observation {
            case let .missing(url):
                guard let index = openDocuments.firstIndex(where: { $0.url == url }) else { continue }
                openDocuments[index].externalChangeState = .deleted
                pendingExternalText[url] = nil
                pendingExternalRevision[url] = nil
            case let .loaded(originalURL, currentURL, revision, text):
                guard let index = openDocuments.firstIndex(where: { $0.url == originalURL }) else { continue }
                if currentURL != originalURL {
                    replaceDocumentURL(at: index, with: currentURL)
                }
                let effectiveURL = openDocuments[index].url
                guard revision != openDocuments[index].revision else { continue }
                if text == openDocuments[index].text {
                    openDocuments[index].revision = revision
                    openDocuments[index].externalChangeState = .none
                    pendingExternalText[effectiveURL] = nil
                    pendingExternalRevision[effectiveURL] = nil
                } else if openDocuments[index].isDirty {
                    openDocuments[index].externalChangeState = .modified
                    pendingExternalText[effectiveURL] = text
                    pendingExternalRevision[effectiveURL] = revision
                } else {
                    openDocuments[index].text = text
                    openDocuments[index].revision = revision
                    openDocuments[index].externalChangeState = .none
                }
            }
        }

        if let entryFileURL,
           !result.texFiles.contains(entryFileURL) {
            self.entryFileURL = ProjectScanner.preferredEntryPoint(from: result.texFiles)
            persistEntryFile()
        }
        refreshOutline()
        refreshCompletionIndex()
        persistOpenDocuments()
    }

    private func replaceDocumentURL(at index: Int, with newURL: URL) {
        let oldURL = openDocuments[index].url
        guard oldURL != newURL else { return }
        openDocuments[index].url = newURL.standardizedFileURL
        if selectedDocumentID == oldURL { selectedDocumentID = newURL }
        if navigatorSelection == oldURL { navigatorSelection = newURL }
        if entryFileURL == oldURL {
            entryFileURL = newURL
            persistEntryFile()
        }
        if let text = pendingExternalText.removeValue(forKey: oldURL) {
            pendingExternalText[newURL] = text
        }
        if let revision = pendingExternalRevision.removeValue(forKey: oldURL) {
            pendingExternalRevision[newURL] = revision
        }
    }

    private func migrateOpenDocumentURLs(from source: URL, to destination: URL) {
        for index in openDocuments.indices {
            let documentURL = openDocuments[index].url
            if documentURL == source {
                replaceDocumentURL(at: index, with: destination)
            } else if documentURL.path.hasPrefix(source.path + "/") {
                let suffix = String(documentURL.path.dropFirst(source.path.count + 1))
                replaceDocumentURL(
                    at: index,
                    with: destination.appendingPathComponent(suffix)
                )
            }
        }
        if let navigatorSelection {
            if navigatorSelection == source {
                self.navigatorSelection = destination
            } else if navigatorSelection.path.hasPrefix(source.path + "/") {
                let suffix = String(navigatorSelection.path.dropFirst(source.path.count + 1))
                self.navigatorSelection = destination.appendingPathComponent(suffix)
            }
        }
        persistOpenDocuments()
    }

    private func uniqueDuplicateURL(for source: URL) -> URL {
        let directory = source.deletingLastPathComponent()
        let isDirectory = findProjectItem(url: source, in: projectTree)?.isDirectory == true
        let pathExtension = isDirectory ? "" : source.pathExtension
        let stem = pathExtension.isEmpty
            ? source.lastPathComponent
            : source.deletingPathExtension().lastPathComponent
        var counter = 1
        while true {
            let suffix = counter == 1 ? " copy" : " copy \(counter)"
            let name = pathExtension.isEmpty
                ? stem + suffix
                : stem + suffix + "." + pathExtension
            let candidate = directory.appendingPathComponent(name, isDirectory: isDirectory)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private func documentURL(_ documentURL: URL, isInside itemURL: URL) -> Bool {
        documentURL == itemURL || documentURL.path.hasPrefix(itemURL.path + "/")
    }

    private func isInsideProject(_ url: URL) -> Bool {
        guard let projectURL else { return false }
        let root = projectURL.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private var selectedProjectDirectory: URL? {
        guard let projectURL else { return nil }
        guard let navigatorSelection,
              let item = findProjectItem(url: navigatorSelection, in: projectTree) else {
            return projectURL
        }
        return item.isDirectory ? item.url : item.url.deletingLastPathComponent()
    }

    private func scheduleSave(for url: URL) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            if self.settings.autosave {
                _ = self.saveDocument(url)
            }
        }
    }

    private func scheduleAutomaticBuild() {
        pendingBuildTask?.cancel()
        guard settings.automaticBuilds else {
            isAutoCompilePending = false
            return
        }
        isAutoCompilePending = true
        let delay = settings.automaticBuildDelay
        pendingBuildTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.settings.automaticBuilds else { return }
            self.isAutoCompilePending = false
            await self.performBuild()
        }
    }

    private func scheduleProjectSearch(immediately: Bool = false) {
        pendingSearchTask?.cancel()
        guard let projectURL, !projectSearchQuery.isEmpty else {
            projectSearchResults = []
            projectSearchError = nil
            isProjectSearchRunning = false
            return
        }
        let query = projectSearchQuery
        let openSources = Dictionary(uniqueKeysWithValues: openDocuments.map { ($0.url, $0.text) })
        isProjectSearchRunning = true
        pendingSearchTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled else { return }
            do {
                let results = try await Task.detached(priority: .userInitiated) {
                    try ProjectSearchService.search(
                        projectURL: projectURL,
                        query: query,
                        openSources: openSources
                    )
                }.value
                guard !Task.isCancelled, let self,
                      self.projectURL == projectURL,
                      self.projectSearchQuery == query else { return }
                self.projectSearchResults = results
                self.projectSearchError = nil
                self.isProjectSearchRunning = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.projectSearchResults = []
                self.projectSearchError = error.localizedDescription
                self.isProjectSearchRunning = false
            }
        }
    }

    private func applyReplaceTransaction(
        _ transaction: ReplaceTransaction,
        undoing: Bool
    ) throws {
        let expected: (ReplaceFileChange) -> String = {
            undoing ? $0.replacementText : $0.originalText
        }
        let target: (ReplaceFileChange) -> String = {
            undoing ? $0.originalText : $0.replacementText
        }

        for change in transaction.changes {
            if let document = openDocuments.first(where: { $0.url == change.fileURL }) {
                guard document.externalChangeState == .none,
                      document.text == expected(change) else {
                    throw ProjectSearchError.fileChanged(change.fileURL.lastPathComponent)
                }
            } else {
                let current = try String(contentsOf: change.fileURL, encoding: .utf8)
                guard current == expected(change) else {
                    throw ProjectSearchError.fileChanged(change.fileURL.lastPathComponent)
                }
            }
        }

        var writtenChanges: [ReplaceFileChange] = []
        do {
            for change in transaction.changes where !openDocuments.contains(where: { $0.url == change.fileURL }) {
                try target(change).write(to: change.fileURL, atomically: true, encoding: .utf8)
                writtenChanges.append(change)
            }
        } catch {
            for change in writtenChanges {
                try? expected(change).write(to: change.fileURL, atomically: true, encoding: .utf8)
            }
            throw error
        }

        for change in transaction.changes {
            guard let index = openDocuments.firstIndex(where: { $0.url == change.fileURL }) else { continue }
            openDocuments[index].text = target(change)
            openDocuments[index].isDirty = true
        }
        if transaction.changes.contains(where: { change in
            openDocuments.contains(where: { $0.url == change.fileURL })
        }) {
            pendingSaveTask?.cancel()
            pendingSaveTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self, self.settings.autosave else { return }
                _ = self.saveAllDocuments()
            }
        }
        scheduleAutomaticBuild()
    }

    private func refreshOutline() {
        pendingOutlineTask?.cancel()
        guard let projectURL else {
            outlineItems = []
            outlineCache = [:]
            selectedOutlineItemID = nil
            return
        }
        let texFiles = ProjectScanner.texFiles(in: projectURL)
        let openSources = Dictionary(uniqueKeysWithValues: openDocuments.map { ($0.url, $0.text) })
        pendingOutlineTask = Task { [weak self] in
            let parsed = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: texFiles.map { fileURL in
                    let source = openSources[fileURL]
                        ?? (try? String(contentsOf: fileURL, encoding: .utf8))
                        ?? ""
                    return (fileURL, LatexOutlineParser.parse(source, fileURL: fileURL))
                })
            }.value
            guard !Task.isCancelled, let self, self.projectURL == projectURL else { return }
            self.outlineCache = parsed
            self.publishOutline(for: texFiles)
        }
    }

    private func scheduleOutlineRefresh(for fileURL: URL, text: String) {
        guard fileURL.pathExtension.lowercased() == "tex" else {
            updateCurrentOutlineSelection()
            return
        }
        pendingOutlineTask?.cancel()
        pendingOutlineTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let items = await Task.detached(priority: .utility) {
                LatexOutlineParser.parse(text, fileURL: fileURL)
            }.value
            guard !Task.isCancelled, let self,
                  self.openDocuments.contains(where: { $0.url == fileURL && $0.text == text }) else {
                return
            }
            self.outlineCache[fileURL] = items
            let texFiles = ProjectScanner.texFiles(in: self.projectURL ?? fileURL.deletingLastPathComponent())
            self.publishOutline(for: texFiles)
        }
    }

    private func publishOutline(for texFiles: [URL]) {
        let validFiles = Set(texFiles)
        outlineCache = outlineCache.filter { validFiles.contains($0.key) }
        let orderedFiles = texFiles.sorted { lhs, rhs in
            if lhs == entryFileURL { return true }
            if rhs == entryFileURL { return false }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
        outlineItems = orderedFiles.flatMap { outlineCache[$0] ?? [] }
        updateCurrentOutlineSelection()
    }

    private func updateCurrentOutlineSelection() {
        guard let selectedDocumentID else {
            selectedOutlineItemID = nil
            return
        }
        selectedOutlineItemID = outlineItems
            .filter { $0.fileURL == selectedDocumentID && $0.line <= cursorLine }
            .max(by: { $0.line < $1.line })?
            .id
    }

    private func refreshCompletionIndex() {
        pendingCompletionTask?.cancel()
        guard let projectURL else {
            completionSymbols = [:]
            projectCompletionIndex = .empty
            return
        }
        let files = ProjectScanner.editableTextFiles(in: projectURL)
        let openSources = Dictionary(uniqueKeysWithValues: openDocuments.map { ($0.url, $0.text) })
        pendingCompletionTask = Task { [weak self] in
            let parsed = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: files.map { fileURL in
                    let source = openSources[fileURL]
                        ?? (try? String(contentsOf: fileURL, encoding: .utf8))
                        ?? ""
                    return (
                        fileURL,
                        LatexCompletionService.parseSymbols(in: source, fileURL: fileURL)
                    )
                })
            }.value
            guard !Task.isCancelled, let self, self.projectURL == projectURL else { return }
            self.completionSymbols = parsed
            self.projectCompletionIndex = LatexCompletionService.makeIndex(
                projectURL: projectURL,
                symbols: parsed
            )
        }
    }

    private func scheduleCompletionRefresh(for fileURL: URL, text: String) {
        guard ["tex", "bib", "sty", "cls"].contains(fileURL.pathExtension.lowercased()),
              let projectURL else { return }
        pendingCompletionTask?.cancel()
        pendingCompletionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let symbols = await Task.detached(priority: .utility) {
                LatexCompletionService.parseSymbols(in: text, fileURL: fileURL)
            }.value
            guard !Task.isCancelled, let self,
                  self.openDocuments.contains(where: { $0.url == fileURL && $0.text == text }) else {
                return
            }
            self.completionSymbols[fileURL] = symbols
            self.projectCompletionIndex = LatexCompletionService.makeIndex(
                projectURL: projectURL,
                symbols: self.completionSymbols
            )
        }
    }

    private func updateRecentProjects(with url: URL) {
        guard settings.keepRecentProjects else { return }
        recentProjects.removeAll { $0.path == url.path }
        recentProjects.insert(
            RecentProject(path: url.path, lastOpened: Date()),
            at: 0
        )
        recentProjects = Array(recentProjects.prefix(12))
        persistRecentProjects()
    }

    private func loadRecentProjects() -> [RecentProject] {
        guard let data = defaults.data(forKey: recentProjectsKey),
              let decoded = try? JSONDecoder().decode([RecentProject].self, from: data) else {
            return []
        }
        return decoded.filter { isExistingDirectory($0.url) }
    }

    private func persistRecentProjects() {
        guard let data = try? JSONEncoder().encode(recentProjects) else { return }
        defaults.set(data, forKey: recentProjectsKey)
    }

    private func openDocumentsKey(for projectURL: URL) -> String {
        "openDocuments.\(LatexBuildService.stableKey(projectURL.path))"
    }

    private func selectedDocumentKey(for projectURL: URL) -> String {
        "selectedDocument.\(LatexBuildService.stableKey(projectURL.path))"
    }

    private func entryFileKey(for projectURL: URL) -> String {
        "entryFile.\(LatexBuildService.stableKey(projectURL.path))"
    }

    private func restoredEntryFile(in projectURL: URL, candidates: [URL]) -> URL? {
        if let relativePath = defaults.string(forKey: entryFileKey(for: projectURL)) {
            let candidate = projectURL.appendingPathComponent(relativePath).standardizedFileURL
            if candidates.contains(candidate) { return candidate }
        }
        return ProjectScanner.preferredEntryPoint(from: candidates)
    }

    private func persistEntryFile() {
        guard let projectURL else { return }
        guard let entryFileURL else {
            defaults.removeObject(forKey: entryFileKey(for: projectURL))
            return
        }
        defaults.set(
            ProjectScanner.relativePath(for: entryFileURL, inside: projectURL),
            forKey: entryFileKey(for: projectURL)
        )
    }

    private func persistOpenDocuments() {
        guard let projectURL else { return }
        defaults.set(
            openDocuments.map(\.url.path),
            forKey: openDocumentsKey(for: projectURL)
        )
        defaults.set(
            selectedDocumentID?.path,
            forKey: selectedDocumentKey(for: projectURL)
        )
    }

    private func restoreOpenDocuments() {
        guard let projectURL else { return }
        let paths = defaults.stringArray(forKey: openDocumentsKey(for: projectURL)) ?? []
        let selectedPath = defaults.string(forKey: selectedDocumentKey(for: projectURL))

        for path in paths.prefix(8) {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path),
                  let item = findProjectItem(url: url, in: projectTree),
                  item.isEditableText else {
                continue
            }
            openDocument(url)
        }

        if let selectedPath {
            let selectedURL = URL(fileURLWithPath: selectedPath)
            if openDocuments.contains(where: { $0.url == selectedURL }) {
                selectDocument(selectedURL)
            }
        }
    }

    private func findProjectItem(url: URL, in items: [ProjectItem]) -> ProjectItem? {
        for item in items {
            if item.url == url { return item }
            if let found = findProjectItem(url: url, in: item.children ?? []) {
                return found
            }
        }
        return nil
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

}
