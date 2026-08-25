import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let openLastProject = "settings.openLastProject.v2"
        static let autosave = "settings.autosave"
        static let automaticBuilds = "settings.automaticBuilds"
        static let automaticBuildDelay = "settings.automaticBuildDelay"
        static let keepRecentProjects = "settings.keepRecentProjects"
        static let editorFontSize = "settings.editorFontSize"
        static let tabWidth = "settings.tabWidth"
        static let showLineNumbers = "settings.showLineNumbers"
        static let wordWrap = "settings.wordWrap"
        static let autoCloseBrackets = "settings.autoCloseBrackets"
        static let latexEngine = "settings.latexEngine"
        static let buildTool = "settings.buildTool"
        static let showLogOnFailure = "settings.showLogOnFailure"
        static let texProvider = "settings.texProvider"
        static let managedRuntimeRecordPath = "settings.managedRuntimeRecordPath"
    }

    @Published var openLastProject: Bool { didSet { save() } }
    @Published var autosave: Bool { didSet { save() } }
    @Published var automaticBuilds: Bool { didSet { save() } }
    @Published var automaticBuildDelay: Double { didSet { save() } }
    @Published var keepRecentProjects: Bool { didSet { save() } }
    @Published var editorFontSize: Double { didSet { save() } }
    @Published var tabWidth: Int { didSet { save() } }
    @Published var showLineNumbers: Bool { didSet { save() } }
    @Published var wordWrap: Bool { didSet { save() } }
    @Published var autoCloseBrackets: Bool { didSet { save() } }
    @Published var latexEngine: LatexEngine { didSet { save() } }
    @Published var buildTool: BuildTool { didSet { save() } }
    @Published var showLogOnFailure: Bool { didSet { save() } }
    @Published var texProvider: TeXProvider? { didSet { save() } }
    @Published var managedRuntimeRecordPath: String? { didSet { save() } }

    private let defaults: UserDefaults
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openLastProject = defaults.object(forKey: Key.openLastProject) as? Bool ?? false
        autosave = defaults.object(forKey: Key.autosave) as? Bool ?? true
        automaticBuilds = defaults.object(forKey: Key.automaticBuilds) as? Bool ?? true
        automaticBuildDelay = defaults.object(forKey: Key.automaticBuildDelay) as? Double ?? 5
        keepRecentProjects = defaults.object(forKey: Key.keepRecentProjects) as? Bool ?? true
        editorFontSize = defaults.object(forKey: Key.editorFontSize) as? Double ?? 13.5
        tabWidth = defaults.object(forKey: Key.tabWidth) as? Int ?? 4
        showLineNumbers = defaults.object(forKey: Key.showLineNumbers) as? Bool ?? true
        wordWrap = defaults.object(forKey: Key.wordWrap) as? Bool ?? true
        autoCloseBrackets = defaults.object(forKey: Key.autoCloseBrackets) as? Bool ?? true
        latexEngine = LatexEngine(
            rawValue: defaults.string(forKey: Key.latexEngine) ?? ""
        ) ?? .pdfLaTeX
        buildTool = BuildTool(
            rawValue: defaults.string(forKey: Key.buildTool) ?? ""
        ) ?? .latexmk
        showLogOnFailure = defaults.object(forKey: Key.showLogOnFailure) as? Bool ?? true
        texProvider = defaults.string(forKey: Key.texProvider).flatMap(TeXProvider.init(rawValue:))
        managedRuntimeRecordPath = defaults.string(forKey: Key.managedRuntimeRecordPath)
        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        defaults.set(openLastProject, forKey: Key.openLastProject)
        defaults.set(autosave, forKey: Key.autosave)
        defaults.set(automaticBuilds, forKey: Key.automaticBuilds)
        defaults.set(automaticBuildDelay, forKey: Key.automaticBuildDelay)
        defaults.set(keepRecentProjects, forKey: Key.keepRecentProjects)
        defaults.set(editorFontSize, forKey: Key.editorFontSize)
        defaults.set(tabWidth, forKey: Key.tabWidth)
        defaults.set(showLineNumbers, forKey: Key.showLineNumbers)
        defaults.set(wordWrap, forKey: Key.wordWrap)
        defaults.set(autoCloseBrackets, forKey: Key.autoCloseBrackets)
        defaults.set(latexEngine.rawValue, forKey: Key.latexEngine)
        defaults.set(buildTool.rawValue, forKey: Key.buildTool)
        defaults.set(showLogOnFailure, forKey: Key.showLogOnFailure)
        defaults.set(texProvider?.rawValue, forKey: Key.texProvider)
        defaults.set(managedRuntimeRecordPath, forKey: Key.managedRuntimeRecordPath)
    }
}
