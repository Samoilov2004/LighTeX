import SwiftUI

struct RuntimeSetupView: View {
    @EnvironmentObject private var runtimeManager: RuntimeManager
    @State private var selectedVariant: RuntimeVariant = .standard

    var body: some View {
        Group {
            if isInstallingRuntime {
                installationState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if runtimeManager.systemStatus.hasAnyEngine {
                            systemTeXOption
                        }
                        runtimeOptions
                        RuntimeProgressView(centered: true)
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 42)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color.white)
    }

    private var isInstallingRuntime: Bool {
        switch runtimeManager.installState {
        case .downloading, .verifying, .installing:
            true
        default:
            false
        }
    }

    private var installationState: some View {
        VStack(spacing: 18) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Installing LighTeX Runtime")
                .font(.system(size: 24, weight: .semibold))
            RuntimeProgressView(centered: true)
                .frame(maxWidth: 560)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 28, weight: .medium))
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up LaTeX")
                    .font(.system(size: 28, weight: .semibold))
                Text("LighTex needs a TeX environment to compile projects. Every managed preset includes pdfLaTeX, XeLaTeX, LuaLaTeX, latexmk, and SyncTeX; presets differ only in included packages.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var systemTeXOption: some View {
        GroupBox("Existing installation") {
            HStack(spacing: 14) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("System TeX detected")
                        .font(.system(size: 13, weight: .medium))
                    Text(availableEngineNames)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use Existing TeX") {
                    runtimeManager.useSystemTeX()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(4)
        }
    }

    private var runtimeOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install LighTeX Runtime")
                .font(.system(size: 13, weight: .semibold))

            if runtimeManager.manifest != nil {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(RuntimeVariant.allCases) { variant in
                        runtimeCard(variant)
                    }
                }
            } else if let error = runtimeManager.manifestError {
                HStack(alignment: .firstTextBaseline) {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        runtimeManager.retryManifest()
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                        .accessibilityLabel("Loading runtime catalog")
                    Text("Loading runtime catalog…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 190, alignment: .center)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func runtimeCard(_ variant: RuntimeVariant) -> some View {
        let selected = selectedVariant == variant
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(variant.label)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if variant == .standard {
                    Text("RECOMMENDED")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(variant.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let asset = runtimeManager.asset(for: variant) {
                Text(RuntimeFormatting.bytes(asset.presentedCompressedSize))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if selected {
                    Button("Install \(variant.label)") {
                        runtimeManager.install(variant)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(runtimeManager.installState.isBusy)
                } else {
                    Button("Select") {
                        selectedVariant = variant
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(runtimeManager.installState.isBusy)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    selected ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: selected ? 2 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var availableEngineNames: String {
        LatexEngine.allCases
            .filter { runtimeManager.systemStatus.engines[$0] != nil }
            .map(\.label)
            .joined(separator: ", ")
    }
}
