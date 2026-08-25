import AppKit
import SwiftUI

@MainActor
final class LighTexAppDelegate: NSObject, NSApplicationDelegate {
    private var snapshotWindow: NSWindow?
    private var snapshotSettings: AppSettings?
    private var snapshotModel: AppModel?
    private var snapshotRuntimeManager: RuntimeManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let path = ProcessInfo.processInfo.environment["LIGHTEX_SNAPSHOT_PATH"] else {
            return
        }
        prepareSnapshotWindow()
        if ProcessInfo.processInfo.environment["LIGHTEX_SNAPSHOT_SHOW_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.snapshotModel?.showsSettingsPanel = true
            }
        }
        if let rawIndex = ProcessInfo.processInfo.environment["LIGHTEX_SNAPSHOT_OUTLINE_INDEX"],
           let index = Int(rawIndex) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let model = self?.snapshotModel,
                      model.outlineItems.indices.contains(index) else {
                    return
                }
                model.openOutlineItem(model.outlineItems[index])
            }
        }
        let snapshotDelay = ProcessInfo.processInfo.environment["LIGHTEX_SNAPSHOT_DELAY"]
            .flatMap(Double.init) ?? 3
        perform(#selector(captureWindow(_:)), with: path as NSString, afterDelay: snapshotDelay)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private func prepareSnapshotWindow() {
        let defaults = Self.configuredDefaults()
        let settings = AppSettings(defaults: defaults)
        let runtimeManager = RuntimeManager(settings: settings)
        let model = AppModel(
            settings: settings,
            runtimeManager: runtimeManager,
            defaults: defaults
        )
        let root = ContentView()
            .environmentObject(model)
            .environmentObject(settings)
            .environmentObject(runtimeManager)
            .preferredColorScheme(.light)
            .frame(width: 1_320, height: 820)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_320, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = model.hasProject ? model.projectName : "LighTex"
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.contentViewController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: 1_320, height: 820)
        window.center()
        window.makeKeyAndOrderFront(nil)
        snapshotSettings = settings
        snapshotModel = model
        snapshotRuntimeManager = runtimeManager
        snapshotWindow = window
    }

    @objc private func captureWindow(_ path: NSString) {
        guard let window = snapshotWindow, let view = window.contentView else { return }
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        let imageURL = URL(fileURLWithPath: path as String)
        try? data.write(to: imageURL, options: .atomic)
        let pdfURL = imageURL.deletingPathExtension().appendingPathExtension("pdf")
        try? view.dataWithPDF(inside: view.bounds).write(to: pdfURL, options: .atomic)

        let metricsURL = imageURL.deletingPathExtension().appendingPathExtension("chrome.txt")
        try? windowChromeMetrics(window).write(to: metricsURL, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    private func windowChromeMetrics(_ window: NSWindow) -> String {
        func frame(for type: NSWindow.ButtonType) -> String {
            guard let button = window.standardWindowButton(type),
                  let superview = button.superview else {
                return "missing"
            }
            return NSStringFromRect(superview.convert(button.frame, to: nil))
        }

        return [
            "styleMask=\(window.styleMask.rawValue)",
            "toolbarStyle=\(window.toolbarStyle)",
            "frame=\(NSStringFromRect(window.frame))",
            "contentLayoutRect=\(NSStringFromRect(window.contentLayoutRect))",
            "close=\(frame(for: .closeButton))",
            "miniaturize=\(frame(for: .miniaturizeButton))",
            "zoom=\(frame(for: .zoomButton))"
        ].joined(separator: "\n") + "\n"
    }

    private static func configuredDefaults() -> UserDefaults {
        guard let suite = ProcessInfo.processInfo.environment["LIGHTEX_DEFAULTS_SUITE"],
              let defaults = UserDefaults(suiteName: suite) else {
            return .standard
        }
        return defaults
    }
}

@main
@MainActor
struct LighTexApp: App {
    @NSApplicationDelegateAdaptor(LighTexAppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var runtimeManager: RuntimeManager
    @StateObject private var model: AppModel

    init() {
        let defaults: UserDefaults
        if let suite = ProcessInfo.processInfo.environment["LIGHTEX_DEFAULTS_SUITE"],
           let suiteDefaults = UserDefaults(suiteName: suite) {
            defaults = suiteDefaults
        } else {
            defaults = .standard
        }
        let settings = AppSettings(defaults: defaults)
        let runtimeManager = RuntimeManager(
            settings: settings,
            startsAutomatically: ProcessInfo.processInfo.environment["LIGHTEX_SNAPSHOT_PATH"] == nil
        )
        _settings = StateObject(wrappedValue: settings)
        _runtimeManager = StateObject(wrappedValue: runtimeManager)
        _model = StateObject(wrappedValue: AppModel(
            settings: settings,
            runtimeManager: runtimeManager,
            defaults: defaults
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(runtimeManager)
                .navigationTitle(model.hasProject ? model.projectName : "LighTex")
                .frame(minWidth: 820, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1_320, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Empty Project…") {
                    model.showsCreateProjectSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!runtimeManager.isSetupComplete)

                Button("Open Project…") {
                    model.chooseProject()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!runtimeManager.isSetupComplete)

                if model.hasProject {
                    Divider()
                    Button("Back to Projects") {
                        model.closeProject()
                    }
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.showsSettingsPanel.toggle()
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(!runtimeManager.isSetupComplete)
            }

            CommandGroup(after: .saveItem) {
                Button("Save") {
                    model.saveSelectedDocument()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.selectedDocument == nil)

                Button("Save All") {
                    model.saveAllDocuments()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(model.openDocuments.isEmpty)
            }

            CommandGroup(after: .toolbar) {
                Divider()
                Button(model.showsSidebar ? "Hide Project Navigator" : "Show Project Navigator") {
                    model.showsSidebar.toggle()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!model.hasProject)

                Button(model.showsPDF ? "Hide PDF Preview" : "Show PDF Preview") {
                    model.showsPDF.toggle()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(!model.hasProject)

                Button(model.showsProblemsPanel ? "Hide Problems" : "Show Problems") {
                    model.showsProblemsPanel.toggle()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!model.hasProject)
            }

            CommandMenu("Build") {
                Button("Build PDF") {
                    model.buildNow()
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(!model.canBuild)

                Divider()

                Picker("LaTeX Engine", selection: $settings.latexEngine) {
                    ForEach(LatexEngine.allCases) { engine in
                        Text(engine.label).tag(engine)
                            .disabled(runtimeManager.currentStatus.engines[engine] == nil)
                    }
                }

                Button("Show Build Log") {
                    model.problemsPanelTab = .log
                    model.showsProblemsPanel = true
                }
                .disabled(!model.hasProject)
            }
        }
    }
}
