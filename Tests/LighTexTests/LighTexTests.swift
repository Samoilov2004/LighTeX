import Testing
import AppKit
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
@testable import LighTex

struct LighTexTests {
    @Test
    func scansProjectTreeAndPrefersMainDocument() throws {
        #expect(try scannerFindsExpectedFilesAndMain())
    }

    @Test
    func ignoresBuildDirectories() throws {
        #expect(try scannerIgnoresBuildDirectory())
    }

    @Test
    func recognizesCommonProjectTextFiles() {
        let markdown = ProjectItem(
            url: URL(fileURLWithPath: "/tmp/README.md"),
            isDirectory: false,
            children: nil
        )
        let makefile = ProjectItem(
            url: URL(fileURLWithPath: "/tmp/Makefile"),
            isDirectory: false,
            children: nil
        )
        let image = ProjectItem(
            url: URL(fileURLWithPath: "/tmp/cover.png"),
            isDirectory: false,
            children: nil
        )

        #expect(markdown.isEditableText)
        #expect(makefile.isEditableText)
        #expect(!image.isEditableText)
    }

    @Test
    func parsesActionableCompilerProblem() {
        #expect(parserFindsFileLineAndMessage())
    }

    @Test
    func buildCacheKeyIsStable() {
        #expect(cacheKeyIsStableAndDistinct())
    }

    @Test
    func parsesDocumentOutlineHierarchy() {
        let source = #"""
        % \chapter{Ignored}
        \chapter{Linear Algebra}
        \section{Vectors \textbf{and} direction}\label{sec:vectors}
        \subsection*{Addition}
        """#
        let items = LatexOutlineParser.parse(
            source,
            fileURL: URL(fileURLWithPath: "/tmp/main.tex")
        )

        #expect(items.map(\.title) == ["Linear Algebra", "Vectors and direction", "Addition"])
        #expect(items.map(\.level) == [0, 1, 2])
        #expect(items.map(\.line) == [2, 3, 4])
    }

    @Test
    func parsesSyncTeXPage() {
        let output = "SyncTeX result begin\nPage:3\nx:120.0\nSyncTeX result end"
        let target = SyncTeXService.target(from: output)
        #expect(target?.page == 3)
        #expect(target?.x == 120)
    }

    @Test
    func buildsSyncTeXSourcePositionWithColumn() {
        let source = URL(fileURLWithPath: "/tmp/My Book/main.tex")
        #expect(
            SyncTeXService.sourcePositionArgument(sourceURL: source, line: 17, column: 9)
                == "17:9:/tmp/My Book/main.tex"
        )
    }

    @Test
    func projectFileDragUsesNativeFileURLRepresentation() {
        let url = URL(fileURLWithPath: "/tmp/main.tex")
        let provider = NSItemProvider(object: url as NSURL)
        let pasteboard = NSPasteboard(name: .init("LighTexTests.fileDrop.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])

        #expect(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        #expect(droppedFilePath(from: url as NSURL) == url.path)
        #expect(droppedFilePath(from: url.absoluteString as NSString) == url.path)
        #expect(projectFileURLs(from: pasteboard) == [url])
    }

    @Test
    func resolvesTwoTabDropPositionsAcrossTheWholeBar() {
        let remaining = URL(fileURLWithPath: "/tmp/notes.tex")
        let frames = [remaining: CGRect(x: 0, y: 0, width: 100, height: 34)]

        #expect(
            editorTabDropIndicator(
                locationX: 20,
                orderedDocumentIDs: [remaining],
                frames: frames
            ) == EditorTabDropIndicator(targetDocumentID: remaining, placement: .before)
        )
        #expect(
            editorTabDropIndicator(
                locationX: 400,
                orderedDocumentIDs: [remaining],
                frames: frames
            ) == EditorTabDropIndicator(targetDocumentID: remaining, placement: .after)
        )
    }

    @Test
    func compilesMinimalLatexProject() async throws {
        #expect(try await latexBuildProducesPDF())
    }

    @Test @MainActor
    func sourceEditorShowsLoadedDocument() async throws {
        let source = "\\documentclass{article}\n\\begin{document}\nVisible text.\n\\end{document}"
        let text = EditorTextBox(source)
        let editor = SourceEditor(
            text: Binding(
                get: { text.value },
                set: { text.value = $0 }
            ),
            fontSize: 13.5,
            tabWidth: 4,
            showsLineNumbers: true,
            wordWrap: false,
            autoCloseBrackets: true,
            jumpLine: nil,
            jumpToken: 0,
            onCursorChange: { _, _ in },
            onWordDoubleClick: { _, _ in }
        )
        let host = NSHostingView(rootView: editor)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()

        let textView = findCodeTextView(in: host)
        #expect(textView?.string == source)
        #expect(textView?.selectedRange().location == 0)
        #expect((textView?.frame.width ?? 0) > 0)
        #expect((textView?.frame.height ?? 0) > 0)
        #expect(textView?.appearance?.name == .aqua)
        #expect(textView?.textContainerInset.width == 6)
        #expect(textView?.textContainerInset.height == 8)
        #expect(textView?.textContainer?.lineFragmentPadding == 0)
        let paragraphStyle = textView?.textStorage?.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(paragraphStyle?.lineHeightMultiple == editorLineHeightMultiple)
        #expect(
            textView?.layoutManager?.temporaryAttribute(
                .backgroundColor,
                atCharacterIndex: 0,
                effectiveRange: nil
            ) == nil
        )
    }

    @Test @MainActor
    func completesLatexEnvironmentAfterNativePreviewOnReturn() {
        let textView = CodeTextView()
        textView.editorTabWidth = 4
        textView.string = "  \\begin{eq}"
        textView.setSelectedRange(NSRange(
            location: ("  \\begin{eq" as NSString).length,
            length: 0
        ))

        let context = latexEnvironmentCompletionContext(
            in: textView.string,
            selection: textView.selectedRange()
        )
        #expect(context?.query == "eq")
        #expect(context?.replacementRange.length == 3)
        #expect(latexEnvironmentCompletions(for: "eq") == ["equation", "equation*"])

        textView.insertCompletion(
            "equation",
            forPartialWordRange: context!.partialRange,
            movement: NSTextMovement.return.rawValue,
            isFinal: false
        )
        #expect(textView.string == "  \\begin{eq}")

        textView.insertCompletion(
            "equation",
            forPartialWordRange: context!.partialRange,
            movement: NSTextMovement.return.rawValue,
            isFinal: true
        )

        #expect(
            textView.string
                == "  \\begin{equation}\n      \n  \\end{equation}"
        )
        #expect(
            textView.selectedRange().location
                == ("  \\begin{equation}\n      " as NSString).length
        )
    }

    @Test
    func numbersTheTrailingEmptySourceLine() {
        let source = "first\nsecond\n" as NSString

        #expect(sourceLineNumber(atUTF16Location: 0, in: source) == 1)
        #expect(sourceLineNumber(atUTF16Location: 6, in: source) == 2)
        #expect(sourceLineNumber(atUTF16Location: source.length, in: source) == 3)
    }

    @Test @MainActor
    func startsAtProjectHubByDefault() {
        let testDefaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: testDefaults)
        let model = AppModel(settings: settings, defaults: testDefaults)

        #expect(settings.openLastProject == false)
        #expect(settings.automaticBuildDelay == 5)
        #expect(settings.texProvider == nil)
        #expect(model.hasProject == false)
    }

    @Test @MainActor
    func loadingSettingsDoesNotOverwriteManagedRuntimeSelection() {
        let testDefaults = makeIsolatedDefaults()
        let recordPath = "/tmp/lightex-runtime-record.json"
        testDefaults.set(TeXProvider.managed.rawValue, forKey: "settings.texProvider")
        testDefaults.set(recordPath, forKey: "settings.managedRuntimeRecordPath")

        let settings = AppSettings(defaults: testDefaults)

        #expect(settings.texProvider == .managed)
        #expect(settings.managedRuntimeRecordPath == recordPath)
        #expect(testDefaults.string(forKey: "settings.texProvider") == TeXProvider.managed.rawValue)
        #expect(testDefaults.string(forKey: "settings.managedRuntimeRecordPath") == recordPath)
    }

    @Test
    func extractsMissingPackageFromCompilerLog() {
        let log = "! LaTeX Error: File `tcolorbox.sty' not found."
        #expect(LatexBuildService.missingPackageFile(in: log) == "tcolorbox.sty")
    }

    @Test
    func parsesTeXLivePackageSearchResult() {
        let output = "tcolorbox:\n\tte xmf-dist/tex/latex/tcolorbox/tcolorbox.sty\n"
            .replacingOccurrences(of: "te xmf", with: "texmf")
        #expect(RuntimeManager.packageName(fromSearchOutput: output) == "tcolorbox")
    }

    @Test
    func verifiesSignedRuntimeManifest() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let data = Data("{\"schemaVersion\":1}".utf8)
        let signature = try privateKey.signature(for: data)
        try RuntimeSecurity.verifyManifest(
            data,
            signature: signature,
            publicKey: privateKey.publicKey.rawRepresentation
        )
    }

    @Test
    func rejectsInvalidManifestSignatureAndHashesArchives() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let data = Data("manifest".utf8)
        let wrongSignature = try Curve25519.Signing.PrivateKey().signature(for: data)
        #expect(throws: RuntimeError.self) {
            try RuntimeSecurity.verifyManifest(
                data,
                signature: wrongSignature,
                publicKey: signingKey.publicKey.rawRepresentation
            )
        }

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try RuntimeSecurity.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test
    func rejectsUnsafeRuntimeToolPath() {
        let root = URL(fileURLWithPath: "/tmp/runtime", isDirectory: true)
        #expect(throws: RuntimeError.self) {
            try ToolchainService.safeToolURL(relativePath: "../pdflatex", root: root)
        }
    }

    @Test
    func validatesRuntimeManifestAndRejectsDuplicateAssets() throws {
        let asset = RuntimeAsset(
            variant: .standard,
            architecture: .current,
            downloadURL: URL(string: "https://example.com/runtime.zip")!,
            compressedSize: 100,
            installedSize: 200,
            sha256: String(repeating: "a", count: 64),
            tools: ["pdflatex": "bin/pdflatex"]
        )
        let valid = RuntimeManifest(
            schemaVersion: 1,
            runtimeVersion: "2026.1",
            texLiveYear: 2026,
            assets: [asset]
        )
        try RuntimeManager.validate(valid)
        let invalid = RuntimeManifest(
            schemaVersion: 1,
            runtimeVersion: "2026.1",
            texLiveYear: 2026,
            assets: [asset, asset]
        )
        #expect(throws: RuntimeError.self) {
            try RuntimeManager.validate(invalid)
        }

        let multipart = RuntimeAsset(
            variant: .full,
            architecture: .current,
            downloadParts: [
                RuntimeArchivePart(
                    downloadURL: URL(string: "https://example.com/runtime.zip.part-00")!,
                    compressedSize: 60
                ),
                RuntimeArchivePart(
                    downloadURL: URL(string: "https://example.com/runtime.zip.part-01")!,
                    compressedSize: 40
                ),
            ],
            compressedSize: 100,
            installedSize: 200,
            sha256: String(repeating: "b", count: 64),
            tools: ["pdflatex": "bin/pdflatex"]
        )
        let multipartManifest = RuntimeManifest(
            schemaVersion: 1,
            runtimeVersion: "2026.1",
            texLiveYear: 2026,
            assets: [multipart]
        )
        try RuntimeManager.validate(multipartManifest)
        let decoded = try JSONDecoder().decode(
            RuntimeManifest.self,
            from: JSONEncoder().encode(multipartManifest)
        )
        #expect(decoded == multipartManifest)
        #expect(decoded.assets[0].archiveParts.count == 2)
    }

    @Test
    func concatenatesMultipartRuntimeArchive() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let first = temporary.appendingPathComponent("part-00")
        let second = temporary.appendingPathComponent("part-01")
        let combined = temporary.appendingPathComponent("runtime.zip")
        try Data("hello ".utf8).write(to: first)
        try Data("runtime".utf8).write(to: second)

        try RuntimeManager.concatenateArchiveParts([first, second], to: combined)

        #expect(try Data(contentsOf: combined) == Data("hello runtime".utf8))
    }

    @Test
    func runtimeInstallStatesReportBusyOnlyDuringWork() {
        let progress = RuntimeDownloadProgress(
            receivedBytes: 50,
            totalBytes: 100,
            bytesPerSecond: 25
        )
        #expect(RuntimeInstallState.checking.isBusy)
        #expect(RuntimeInstallState.downloading(progress).isBusy)
        #expect(RuntimeInstallState.verifying.isBusy)
        #expect(RuntimeInstallState.installing.isBusy)
        #expect(!RuntimeInstallState.idle.isBusy)
        #expect(!RuntimeInstallState.failed("offline").isBusy)
    }

    @Test
    func detectsWorkingSystemEngineAtAbsolutePath() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let executable = temporary.appendingPathComponent("pdflatex")
        try "#!/bin/sh\necho 'pdfTeX fixture 1.0'\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let status = ToolchainService.detectSystemSynchronously(
            environment: ["PATH": temporary.path]
        )

        #expect(status.engines[.pdfLaTeX]?.url.standardizedFileURL == executable.standardizedFileURL)
        #expect(status.engines[.pdfLaTeX]?.version == "pdfTeX fixture 1.0")
    }

    @Test
    func preservesTeXFormatSymlinkName() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let target = temporary.appendingPathComponent("pdftex")
        try "#!/bin/sh\necho 'pdfTeX fixture 1.0'\n".write(
            to: target,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: target.path
        )
        let symlink = temporary.appendingPathComponent("pdflatex")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        let status = ToolchainService.detectSystemSynchronously(
            environment: ["PATH": temporary.path]
        )

        #expect(status.engines[.pdfLaTeX]?.url.lastPathComponent == "pdflatex")
    }

    @Test
    func cleanRoomModeHidesSystemTeX() {
        let status = ToolchainService.detectSystemSynchronously(
            environment: [
                "PATH": "/Library/TeX/texbin:/usr/local/bin:/usr/bin",
                "LIGHTEX_SIMULATE_NO_SYSTEM_TEX": "1"
            ]
        )
        #expect(status == .empty)
    }

    @Test
    func installsRuntimeArchiveAtomically() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payload = temporary.appendingPathComponent("runtime", isDirectory: true)
        let bin = payload.appendingPathComponent("bin", isDirectory: true)
        let base = temporary.appendingPathComponent("installed", isDirectory: true)
        let archive = temporary.appendingPathComponent("runtime.zip")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let toolNames = ["pdflatex", "xelatex", "lualatex", "latexmk", "synctex", "tlmgr"]
        var tools: [String: String] = [:]
        for name in toolNames {
            let url = bin.appendingPathComponent(name)
            try "#!/bin/sh\necho '\(name) fake 1.0'\n".write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
            tools[name] = "runtime/bin/\(name)"
        }

        let zipped = try CommandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", payload.path, archive.path]
        )
        #expect(zipped.status == 0)
        let asset = RuntimeAsset(
            variant: .minimal,
            architecture: .current,
            downloadURL: archive,
            compressedSize: Int64((try archive.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 1),
            installedSize: 1_000_000,
            sha256: try RuntimeSecurity.sha256(of: archive),
            tools: tools
        )
        let manifest = RuntimeManifest(
            schemaVersion: 1,
            runtimeVersion: "test-1",
            texLiveYear: 2026,
            assets: [asset]
        )
        let record = try RuntimeInstallationService.install(
            archiveURL: archive,
            manifest: manifest,
            asset: asset,
            baseDirectory: base
        )
        #expect(FileManager.default.fileExists(atPath: RuntimeManager.recordURL(for: record).path))
        #expect(try ToolchainService.status(for: record).engines.count == 3)
    }

    @Test @MainActor
    func createsEmptyProjectAndKeepsItInRecents() throws {
        let testDefaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: testDefaults)
        settings.automaticBuilds = false
        let model = AppModel(settings: settings, defaults: testDefaults)
        let location = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: location) }

        #expect(model.createProject(name: "EmptyBook", location: location))
        let mainFile = location.appendingPathComponent("EmptyBook/main.tex")
        let contents = try String(contentsOf: mainFile, encoding: .utf8)
        #expect(contents.contains("\\documentclass[11pt]{article}"))
        #expect(contents.contains("\\begin{document}"))
        #expect(contents.contains("\\begin{titlepage}"))
        #expect(contents.contains("{\\Huge\\bfseries EmptyBook\\par}"))
        #expect(contents.contains("\\section{Introduction}"))
        #expect(contents.contains("Start writing here."))

        model.closeProject()
        #expect(model.hasProject == false)
        #expect(model.recentProjects.map(\.name) == ["EmptyBook"])
    }

    @Test @MainActor
    func createsProjectItemsAndReordersEditorTabs() throws {
        let testDefaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: testDefaults)
        settings.automaticBuilds = false
        let model = AppModel(settings: settings, defaults: testDefaults)
        let location = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: location) }

        #expect(model.createProject(name: "Workspace", location: location))
        let root = location.appendingPathComponent("Workspace", isDirectory: true)
        let folder = root.appendingPathComponent("sections", isDirectory: true)
        #expect(model.createProjectFolder(named: "sections"))
        #expect(model.projectTree.contains(where: { $0.url == folder && $0.isDirectory }))

        model.navigatorSelection = folder
        #expect(model.createProjectFile(named: "vectors.tex"))
        let vectors = folder.appendingPathComponent("vectors.tex")
        #expect(FileManager.default.fileExists(atPath: vectors.path))
        #expect(model.selectedDocumentID == vectors)

        let main = root.appendingPathComponent("main.tex")
        model.navigatorSelection = nil
        #expect(model.createProjectFile(named: "notes.tex"))
        let notes = root.appendingPathComponent("notes.tex")
        #expect(model.openDocuments.map(\.url) == [main, vectors, notes])

        model.moveDocument(main, relativeTo: notes, placement: .after)
        #expect(model.openDocuments.map(\.url) == [vectors, notes, main])
        model.moveDocument(main, relativeTo: vectors, placement: .before)
        #expect(model.openDocuments.map(\.url) == [main, vectors, notes])
        model.moveDocument(vectors, relativeTo: notes, placement: .after)
        #expect(model.openDocuments.map(\.url) == [main, notes, vectors])

        model.closeDocument(notes)
        #expect(model.openDocuments.map(\.url) == [main, vectors])
        model.moveDocument(main, relativeTo: vectors, placement: .after)
        #expect(model.openDocuments.map(\.url) == [vectors, main])
        model.moveDocument(main, relativeTo: vectors, placement: .before)
        #expect(model.openDocuments.map(\.url) == [main, vectors])

        #expect(model.openDroppedProjectItem(atPath: notes.path))
        #expect(model.selectedDocumentID == notes)
        #expect(model.openDocuments.map(\.url) == [main, vectors, notes])
        #expect(AppModel.validProjectItemName("../bad") == nil)
        #expect(AppModel.validProjectItemName(" chapter.tex ") == "chapter.tex")
    }
}

private func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "LighTexTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private final class EditorTextBox {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}

@MainActor
private func findCodeTextView(in view: NSView) -> CodeTextView? {
    if let textView = view as? CodeTextView {
        return textView
    }
    for subview in view.subviews {
        if let textView = findCodeTextView(in: subview) {
            return textView
        }
    }
    return nil
}
