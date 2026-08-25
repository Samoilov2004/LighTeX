import AppKit
import Combine
import Foundation

enum DocumentMovePlacement: Sendable, Equatable {
    case before
    case after
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var projectURL: URL?
    @Published private(set) var projectTree: [ProjectItem] = []
    @Published private(set) var outlineItems: [DocumentOutlineItem] = []
    @Published private(set) var entryFileURL: URL?
    @Published private(set) var openDocuments: [EditorDocument] = []
    @Published var selectedDocumentID: URL?
    @Published var navigatorSelection: URL?

    @Published private(set) var previewPDFURL: URL?
    @Published private(set) var pdfRevision = 0
    @Published private(set) var pdfJumpTarget: PDFJumpTarget?
    @Published private(set) var pdfJumpToken = 0
    @Published private(set) var buildState: BuildState = .idle
    @Published private(set) var buildLog = ""
    @Published private(set) var problems: [BuildProblem] = []
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
    @Published var showsSettingsPanel = false
    @Published var alertMessage: String?
    @Published private(set) var recentProjects: [RecentProject] = []
    @Published private(set) var cursorLine = 1
    @Published private(set) var cursorColumn = 1

    let settings: AppSettings
    let runtimeManager: RuntimeManager

    private var pendingSaveTask: Task<Void, Never>?
    private var pendingBuildTask: Task<Void, Never>?
    private var buildQueuedWhileBuilding = false
    private var runtimeCancellable: AnyCancellable?
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
        defaults: UserDefaults = .standard
    ) {
        self.settings = settings
        self.runtimeManager = runtimeManager
        self.defaults = defaults
        showsSidebar = defaults.object(forKey: "ui.showsSidebar") as? Bool ?? true
        showsPDF = defaults.object(forKey: "ui.showsPDF") as? Bool ?? true
        recentProjects = loadRecentProjects()
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

    convenience init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.init(
            settings: settings,
            runtimeManager: RuntimeManager(settings: settings, startsAutomatically: false),
            defaults: defaults
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
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !trimmedName.contains("/"),
              trimmedName != ".",
              trimmedName != ".." else {
            alertMessage = "Enter a valid project name without path separators."
            return false
        }

        let project = location.appendingPathComponent(trimmedName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: project.path) else {
            alertMessage = "A folder named \(trimmedName) already exists in this location."
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: project,
                withIntermediateDirectories: false
            )
            let documentTitle = Self.latexEscaped(trimmedName)
            let starter = """
            \\documentclass[11pt]{article}

            \\usepackage[T1]{fontenc}
            \\usepackage{lmodern}
            \\usepackage[margin=1in]{geometry}
            \\usepackage{xcolor}

            \\definecolor{LighTexBlue}{HTML}{2563EB}

            \\begin{document}

            \\begin{titlepage}
              \\thispagestyle{empty}
              \\vspace*{0.18\\textheight}
              {\\color{LighTexBlue}\\rule{1.1in}{4pt}\\par}
              \\vspace{1.1cm}
              {\\Huge\\bfseries \(documentTitle)\\par}
              \\vspace{0.4cm}
              {\\Large A new LighTex project\\par}
              \\vfill
              {\\small Created with LighTex\\par}
            \\end{titlepage}

            \\section{Introduction}

            Start writing here.

            \\end{document}
            """
            try starter.write(
                to: project.appendingPathComponent("main.tex"),
                atomically: true,
                encoding: .utf8
            )
            showsCreateProjectSheet = false
            openProject(project)
            return true
        } catch {
            alertMessage = "LighTex could not create the project: \(error.localizedDescription)"
            return false
        }
    }

    private static func latexEscaped(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            switch character {
            case "\\": result += "\\textbackslash{}"
            case "{": result += "\\{"
            case "}": result += "\\}"
            case "#": result += "\\#"
            case "$": result += "\\$"
            case "%": result += "\\%"
            case "&": result += "\\&"
            case "_": result += "\\_"
            case "~": result += "\\textasciitilde{}"
            case "^": result += "\\textasciicircum{}"
            default: result.append(character)
            }
        }
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

    func openProject(_ url: URL) {
        saveAllDocuments()
        pendingSaveTask?.cancel()
        pendingBuildTask?.cancel()
        buildQueuedWhileBuilding = false

        let standardizedURL = url.standardizedFileURL
        projectURL = standardizedURL
        projectTree = ProjectScanner.projectTree(in: standardizedURL)
        let texFiles = ProjectScanner.texFiles(in: standardizedURL)
        entryFileURL = ProjectScanner.preferredEntryPoint(from: texFiles)
        openDocuments = []
        selectedDocumentID = nil
        navigatorSelection = nil
        buildLog = ""
        problems = []
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

        if settings.automaticBuilds,
           entryFileURL != nil,
           runtimeManager.isSetupComplete {
            buildNow()
        }
    }

    func closeProject() {
        saveAllDocuments()
        persistOpenDocuments()
        pendingSaveTask?.cancel()
        pendingBuildTask?.cancel()
        buildQueuedWhileBuilding = false
        projectURL = nil
        projectTree = []
        outlineItems = []
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
            let text = try String(contentsOf: url, encoding: .utf8)
            openDocuments.append(EditorDocument(
                url: url,
                text: text,
                isDirty: false,
                jumpLine: line,
                jumpToken: line == nil ? 0 : 1
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
        saveDocument(url)
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
        panel.canChooseDirectories = false
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
        refreshOutline()
        scheduleSave(for: selectedDocumentID)
        scheduleAutomaticBuild()
    }

    func saveSelectedDocument() {
        guard let selectedDocumentID else { return }
        saveDocument(selectedDocumentID)
    }

    func saveAllDocuments() {
        for url in openDocuments.map(\.url) {
            saveDocument(url)
        }
    }

    func setEntryFile(_ url: URL) {
        guard url.pathExtension.lowercased() == "tex" else { return }
        entryFileURL = url
        let existingPDF = url.deletingPathExtension().appendingPathExtension("pdf")
        previewPDFURL = FileManager.default.fileExists(atPath: existingPDF.path) ? existingPDF : nil
        if previewPDFURL != nil { pdfRevision += 1 }
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
            buildState = .failure
            problemsPanelTab = .problems
            showsProblemsPanel = true
            return
        }

        saveAllDocuments()
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
            buildState = .failure
            problemsPanelTab = .problems
            showsProblemsPanel = true
            return
        }
        buildState = .building
        buildLog = "Building \(entryRelativePath) with \(settings.latexEngine.label)…"
        problems = []
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

    private func saveDocument(_ url: URL) {
        guard let index = openDocuments.firstIndex(where: { $0.url == url }),
              openDocuments[index].isDirty else {
            return
        }
        do {
            try openDocuments[index].text.write(to: url, atomically: true, encoding: .utf8)
            openDocuments[index].isDirty = false
        } catch {
            alertMessage = "LighTex could not save \(url.lastPathComponent): \(error.localizedDescription)"
        }
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
                self.saveDocument(url)
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

    private func refreshOutline() {
        guard let projectURL else {
            outlineItems = []
            return
        }
        let texFiles = ProjectScanner.texFiles(in: projectURL)
        let orderedFiles = texFiles.sorted { lhs, rhs in
            if lhs == entryFileURL { return true }
            if rhs == entryFileURL { return false }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }

        outlineItems = orderedFiles.flatMap { fileURL in
            let source: String?
            if let document = openDocuments.first(where: { $0.url == fileURL }) {
                source = document.text
            } else {
                source = try? String(contentsOf: fileURL, encoding: .utf8)
            }
            return source.map { LatexOutlineParser.parse($0, fileURL: fileURL) } ?? []
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
