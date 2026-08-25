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
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .leading) {
            Divider()
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
    }

    private func engineLabel(_ engine: LatexEngine) -> String {
        runtimeManager.currentStatus.engines[engine] == nil
            ? "\(engine.label) — Not installed"
            : engine.label
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
