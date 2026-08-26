import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case editor = "Editor"
    case latex = "LaTeX"

    var id: String { rawValue }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var runtimeManager: RuntimeManager
    @State private var section: SettingsSection = .general
    @FocusState private var closeButtonFocused: Bool

    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let requestedSection = ProcessInfo.processInfo.environment["LIGHTEX_SNAPSHOT_SETTINGS_SECTION"]
            .flatMap(SettingsSection.init(rawValue:))
        _section = State(initialValue: requestedSection ?? .general)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .focused($closeButtonFocused)
                .help("Close Settings")
                .accessibilityLabel("Close Settings")
            }
            .padding(.horizontal, 18)
            .frame(height: 48)

            Picker("Settings Section", selection: $section) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            Divider()

            Group {
                switch section {
                case .general:
                    GeneralSettingsView()
                case .editor:
                    EditorSettingsView()
                case .latex:
                    LatexSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .onAppear {
            closeButtonFocused = true
        }
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var confirmsClearingRecentProjects = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open last project on launch", isOn: $settings.openLastProject)
            }
            Section("Documents") {
                Toggle("Autosave changes", isOn: $settings.autosave)
            }
            Section("Recent Projects") {
                Toggle("Remember opened projects", isOn: $settings.keepRecentProjects)
                LabeledContent("Stored projects", value: "\(model.recentProjects.count)")
                Button("Clear History") {
                    confirmsClearingRecentProjects = true
                }
                .disabled(model.recentProjects.isEmpty)
            }
            Section("Updates") {
                updateStatus
                Button("Check for Updates") {
                    model.checkForAppUpdates()
                }
                .disabled(model.appUpdateState == .checking)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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

    @ViewBuilder
    private var updateStatus: some View {
        switch model.appUpdateState {
        case .idle:
            LabeledContent("LighTex", value: currentVersion)
        case .checking:
            ProgressView("Checking GitHub Releases…")
                .controlSize(.small)
        case .upToDate:
            Label("LighTex is up to date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case let .available(version, _):
            VStack(alignment: .leading, spacing: 6) {
                Label("Version \(version) is available", systemImage: "arrow.down.circle")
                Button("Open Release Page") {
                    model.openAvailableAppUpdate()
                }
            }
        case let .failed(message):
            Label(message, systemImage: "wifi.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build"
    }
}

private struct EditorSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Typography") {
                HStack {
                    Text("Font size")
                    Slider(value: $settings.editorFontSize, in: 11...20, step: 0.5)
                    Text(settings.editorFontSize.formatted(.number.precision(.fractionLength(1))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            Section("Editing") {
                Picker("Tab width", selection: $settings.tabWidth) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("8 spaces").tag(8)
                }
                Toggle("Show line numbers", isOn: $settings.showLineNumbers)
                Toggle("Word wrap", isOn: $settings.wordWrap)
                Toggle("Automatically close brackets", isOn: $settings.autoCloseBrackets)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct LatexSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var runtimeManager: RuntimeManager
    @State private var selectedVariant: RuntimeVariant = .standard
    @State private var runtimePendingRemoval: InstalledRuntime?
    @State private var confirmsClearingRuntimeCache = false
    @State private var confirmsClearingBuildCache = false

    var body: some View {
        Form {
            Section("TeX Environment") {
                LabeledContent("Active") {
                    Label(
                        settings.texProvider?.label ?? "Not configured",
                        systemImage: runtimeManager.isSetupComplete
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle"
                    )
                }
                if runtimeManager.systemStatus.hasAnyEngine {
                    Button("Use System TeX") {
                        runtimeManager.useSystemTeX()
                    }
                    .disabled(settings.texProvider == .system)
                }
                if settings.managedRuntimeRecordPath != nil {
                    Button("Use Installed LighTeX Runtime") {
                        runtimeManager.useManagedRuntime()
                    }
                    .disabled(settings.texProvider == .managed)
                }
                Button("Refresh Detection") {
                    runtimeManager.refreshSystemStatus()
                }
            }

            Section("LighTeX Runtime") {
                Picker("Preset", selection: $selectedVariant) {
                    ForEach(RuntimeVariant.allCases) { variant in
                        Text(variant.label).tag(variant)
                    }
                }
                if let asset = runtimeManager.asset(for: selectedVariant) {
                    LabeledContent("Download", value: RuntimeFormatting.bytes(asset.presentedCompressedSize))
                    Button(settings.managedRuntimeRecordPath == nil
                        ? "Install Runtime"
                        : "Install or Replace Runtime") {
                        runtimeManager.install(selectedVariant)
                    }
                    .disabled(runtimeManager.installState.isBusy)
                } else if let error = runtimeManager.manifestError {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Retry Runtime Catalog") {
                        runtimeManager.retryManifest()
                    }
                }
                RuntimeProgressView()
            }

            if !runtimeManager.installedRuntimes.isEmpty {
                Section("Installed Runtimes") {
                    ForEach(runtimeManager.installedRuntimes) { runtime in
                        installedRuntimeRow(runtime)
                    }
                }
            }

            Section("Storage") {
                LabeledContent(
                    "Runtime downloads and staging",
                    value: RuntimeFormatting.bytes(runtimeManager.cacheUsage.downloadsAndStaging)
                )
                Button("Clear Runtime Downloads…") {
                    confirmsClearingRuntimeCache = true
                }
                .disabled(runtimeManager.cacheUsage.downloadsAndStaging == 0)

                LabeledContent(
                    "Build cache",
                    value: RuntimeFormatting.bytes(runtimeManager.cacheUsage.buildCache)
                )
                Button("Clear Build Cache…") {
                    confirmsClearingBuildCache = true
                }
                .disabled(runtimeManager.cacheUsage.buildCache == 0)

                if let message = runtimeManager.storageOperationMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Compiler") {
                Picker("LaTeX engine", selection: $settings.latexEngine) {
                    ForEach(LatexEngine.allCases) { engine in
                        Text(engineLabel(engine)).tag(engine)
                            .disabled(runtimeManager.currentStatus.engines[engine] == nil)
                    }
                }
                Picker("Build tool", selection: $settings.buildTool) {
                    Text("latexmk").tag(BuildTool.latexmk)
                        .disabled(runtimeManager.currentStatus.latexmk == nil)
                    Text("Direct compiler").tag(BuildTool.directCompiler)
                }
            }

            Section("Automatic Build") {
                Toggle("Auto Compile after edits", isOn: $settings.automaticBuilds)
                Picker("Wait after last edit", selection: $settings.automaticBuildDelay) {
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }
                .disabled(!settings.automaticBuilds)
                Toggle("Show Problems panel on failure", isOn: $settings.showLogOnFailure)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task {
            await runtimeManager.refreshStorageInfo()
        }
        .alert(
            "Remove LighTeX Runtime?",
            isPresented: Binding(
                get: { runtimePendingRemoval != nil },
                set: { if !$0 { runtimePendingRemoval = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let runtimePendingRemoval {
                    runtimeManager.removeInstalledRuntime(runtimePendingRemoval)
                }
                runtimePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { runtimePendingRemoval = nil }
        } message: {
            Text("The selected inactive runtime will be deleted from Application Support. Projects are not affected.")
        }
        .alert("Clear Runtime Downloads?", isPresented: $confirmsClearingRuntimeCache) {
            Button("Clear", role: .destructive) {
                runtimeManager.clearRuntimeDownloadsAndStaging()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes downloaded archives and incomplete installations, freeing \(RuntimeFormatting.bytes(runtimeManager.cacheUsage.downloadsAndStaging)). Installed runtimes stay available.")
        }
        .alert("Clear Build Cache?", isPresented: $confirmsClearingBuildCache) {
            Button("Clear", role: .destructive) {
                runtimeManager.clearBuildCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(RuntimeFormatting.bytes(runtimeManager.cacheUsage.buildCache)). Project source files and generated PDFs in project folders are not deleted.")
        }
    }

    private func engineLabel(_ engine: LatexEngine) -> String {
        runtimeManager.currentStatus.engines[engine] == nil
            ? "\(engine.label) — Not installed"
            : engine.label
    }

    private func installedRuntimeRow(_ runtime: InstalledRuntime) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("\(runtime.record.runtimeVersion) · \(runtime.record.variant.label)")
                            .fontWeight(.medium)
                        if runtime.isActive {
                            Text("ACTIVE")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    Text("\(runtime.record.architecture.rawValue) · \(RuntimeFormatting.bytes(runtime.installedSize))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !runtime.isActive {
                    Button("Use") {
                        runtimeManager.useInstalledRuntime(runtime)
                    }
                    .controlSize(.small)
                    Button(role: .destructive) {
                        runtimePendingRemoval = runtime
                    } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Remove runtime \(runtime.record.runtimeVersion)")
                }
            }
            Text(runtime.record.rootPath)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(runtime.record.rootPath)
        }
    }
}

struct RuntimeProgressView: View {
    @EnvironmentObject private var runtimeManager: RuntimeManager
    var centered = false

    @ViewBuilder
    var body: some View {
        switch runtimeManager.installState {
        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress.fraction)
                    .tint(.accentColor)
                    .accessibilityLabel("Downloading LighTeX Runtime")
                    .accessibilityValue("\(Int(progress.fraction * 100)) percent")
                HStack {
                    Text("Downloading \(Int(progress.fraction * 100))%")
                    Spacer()
                    Text("\(RuntimeFormatting.bytes(progress.receivedBytes)) of \(RuntimeFormatting.bytes(progress.totalBytes))")
                    Text("\(RuntimeFormatting.bytes(Int64(progress.bytesPerSecond)))/s")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                Button("Cancel", role: .cancel) {
                    runtimeManager.cancelInstall()
                }
            }
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        case .verifying:
            ProgressView("Verifying download…")
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .accessibilityLabel("Verifying runtime download")
        case .installing:
            ProgressView("Installing runtime…")
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .accessibilityLabel("Installing LighTeX Runtime")
        case let .failed(message):
            Label(message, systemImage: "xmark.circle")
                .font(.footnote)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        case let .ready(record):
            Label("Runtime \(record.runtimeVersion) is ready", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        default:
            EmptyView()
        }
    }
}

enum RuntimeFormatting {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
