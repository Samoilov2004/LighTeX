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
        let expectedLineHeight = editorLineHeight(for: textView!.editorFont)
        #expect(paragraphStyle?.minimumLineHeight == expectedLineHeight)
        #expect(paragraphStyle?.maximumLineHeight == expectedLineHeight)
        #expect(paragraphStyle?.lineHeightMultiple == 1)
        let typingParagraph = textView?.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(typingParagraph?.minimumLineHeight == expectedLineHeight)
        #expect(typingParagraph?.maximumLineHeight == expectedLineHeight)
        #expect(
            textView?.layoutManager?.temporaryAttribute(
                .backgroundColor,
                atCharacterIndex: 0,
                effectiveRange: nil
            ) == nil
        )
    }

    @Test @MainActor
    func typingIntoBlankLineKeepsItsLineFragmentStable() async throws {
        let source = "first\n\nthird"
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

        let textView = try #require(findCodeTextView(in: host))
        let scrollView = try #require(textView.enclosingScrollView)
        let before = try lineFragmentRect(in: textView, atCharacter: 6)
        let scrollOrigin = scrollView.contentView.bounds.origin

        textView.setSelectedRange(NSRange(location: 6, length: 0))
        textView.insertText("efve", replacementRange: textView.selectedRange())
        textView.layoutManager?.ensureLayout(for: try #require(textView.textContainer))

        let after = try lineFragmentRect(in: textView, atCharacter: 6)
        let insertedParagraph = textView.textStorage?.attribute(
            .paragraphStyle,
            at: 6,
            effectiveRange: nil
        ) as? NSParagraphStyle

        #expect(textView.string == "first\nefve\nthird")
        #expect(after.minY == before.minY)
        #expect(after.height == before.height)
        #expect(scrollView.contentView.bounds.origin == scrollOrigin)
        #expect(insertedParagraph?.minimumLineHeight == textView.editorLineHeight)
        #expect(insertedParagraph?.maximumLineHeight == textView.editorLineHeight)
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

    @Test
    func usesOneFixedEditorLineMetric() {
        let font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        let lineHeight = editorLineHeight(for: font)
        let paragraph = editorParagraphStyle(font: font, tabWidth: 4)

        #expect(lineHeight == 18)
        #expect(paragraph.minimumLineHeight == lineHeight)
        #expect(paragraph.maximumLineHeight == lineHeight)
        #expect(paragraph.lineHeightMultiple == 1)
        #expect(
            lineNumberOriginY(
                sourceBaselineY: editorBaselineOffset(font: font, lineHeight: lineHeight),
                numberFontAscender: 8
            ) == editorBaselineOffset(font: font, lineHeight: lineHeight) - 8
        )
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

    @Test
    func providesFourBuiltInProjectTemplates() {
        #expect(
            ProjectTemplate.builtInTemplates.map(\.name)
                == ["Simple Article", "Math Notes", "Textbook", "Presentation"]
        )
        #expect(ProjectTemplate.builtInTemplates.map(\.id).allSatisfy { !$0.isEmpty })
        #expect(ProjectTemplate.builtInTemplates.last?.previewStyle == .presentation)
    }

    @Test
    func savesReusesAndDeletesPersonalTemplateSafely() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = temporary.appendingPathComponent("Original", isDirectory: true)
        let userLibrary = temporary.appendingPathComponent("Templates/Yours", isDirectory: true)
        let projects = temporary.appendingPathComponent("Projects", isDirectory: true)
        let store = ProjectTemplateStore(userTemplatesDirectory: userLibrary)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        try #"""
        \documentclass{article}
        \title{${PROJECT_NAME}}
        \author{${AUTHOR}}
        \begin{document}
        ${DATE}
        \end{document}
        """#.write(
            to: source.appendingPathComponent("main.tex"),
            atomically: true,
            encoding: .utf8
        )
        try "generated".write(
            to: source.appendingPathComponent("main.aux"),
            atomically: true,
            encoding: .utf8
        )
        try Data("compiled".utf8).write(to: source.appendingPathComponent("main.pdf"))
        try Data("figure".utf8).write(to: source.appendingPathComponent("figure.pdf"))
        try "private".write(
            to: source.appendingPathComponent(".git/config"),
            atomically: true,
            encoding: .utf8
        )

        let template = try store.saveUserTemplate(
            from: source,
            name: "My Article",
            summary: "A reusable article"
        )
        let templateFiles = try #require(template.userDirectory)
            .appendingPathComponent("files", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: templateFiles.appendingPathComponent("main.tex").path))
        #expect(!FileManager.default.fileExists(atPath: templateFiles.appendingPathComponent("main.aux").path))
        #expect(!FileManager.default.fileExists(atPath: templateFiles.appendingPathComponent("main.pdf").path))
        #expect(FileManager.default.fileExists(atPath: templateFiles.appendingPathComponent("figure.pdf").path))
        #expect(!FileManager.default.fileExists(atPath: templateFiles.appendingPathComponent(".git").path))

        let project = try store.instantiate(
            template: template,
            projectName: "New_Project",
            author: "Ada & Bob",
            location: projects
        )
        let contents = try String(
            contentsOf: project.appendingPathComponent("main.tex"),
            encoding: .utf8
        )
        #expect(contents.contains("\\title{New\\_Project}"))
        #expect(contents.contains("\\author{Ada \\& Bob}"))
        #expect(!contents.contains("${PROJECT_NAME}"))
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("figure.pdf").path))

        try store.deleteUserTemplate(template)
        #expect(store.loadUserTemplates().isEmpty)
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("main.tex").path))
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("main.tex").path))
    }

    @Test
    func personalTemplateReviewExcludesSecretsAndWritesV2Manifest() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = temporary.appendingPathComponent("Source", isDirectory: true)
        let library = temporary.appendingPathComponent("Templates", isDirectory: true)
        let store = ProjectTemplateStore(userTemplatesDirectory: library)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        try "\\documentclass{article}".write(
            to: source.appendingPathComponent("main.tex"),
            atomically: true,
            encoding: .utf8
        )
        try "TOKEN=secret".write(
            to: source.appendingPathComponent(".env.local"),
            atomically: true,
            encoding: .utf8
        )
        try "PRIVATE".write(
            to: source.appendingPathComponent("author.key"),
            atomically: true,
            encoding: .utf8
        )
        try "notes".write(
            to: source.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let review = try store.reviewProjectContents(from: source)
        #expect(review.included.map(\.relativePath).contains("main.tex"))
        #expect(review.included.map(\.relativePath).contains("README.md"))
        #expect(review.excluded.map(\.relativePath).contains(".env.local"))
        #expect(review.excluded.map(\.relativePath).contains("author.key"))

        let template = try store.saveUserTemplate(from: source, name: "Safe", summary: "")
        let directory = try #require(template.userDirectory)
        let files = directory.appendingPathComponent("files", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: files.appendingPathComponent(".env.local").path))
        #expect(!FileManager.default.fileExists(atPath: files.appendingPathComponent("author.key").path))
        let manifestData = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        #expect(manifest["schemaVersion"] as? Int == 2)
        #expect(manifest["previewFile"] as? String == "preview.png")
    }

    @Test
    func stillLoadsV1PersonalTemplateManifest() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = temporary.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("files", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        try "\\documentclass{article}".write(
            to: directory.appendingPathComponent("files/main.tex"),
            atomically: true,
            encoding: .utf8
        )
        let manifest = """
        {"schemaVersion":1,"id":"legacy","name":"Legacy","summary":"","createdAt":"2026-08-26T00:00:00Z","entryFile":"main.tex","previewStyle":"article"}
        """
        try manifest.write(
            to: directory.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        let templates = ProjectTemplateStore(userTemplatesDirectory: temporary).loadUserTemplates()
        #expect(templates.map(\.id) == ["legacy"])
    }

    @Test
    func comparesGitHubReleaseVersionsWithoutInstallingCode() {
        #expect(AppUpdateService.compare("v0.6.0", "0.5.2") == .orderedDescending)
        #expect(AppUpdateService.compare("v0.5.2", "0.5.2") == .orderedSame)
        #expect(AppUpdateService.compare("v1.0.0-beta", "1.0.0") == .orderedAscending)
    }

    @Test
    func inventoriesOnlyValidManagedRuntimesAndMeasuresStorage() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = temporary.appendingPathComponent("2026/standard/arm64", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let executable = bin.appendingPathComponent("pdflatex")
        try "#!/bin/sh\necho 'pdfTeX 3.14'\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let record = ManagedRuntimeRecord(
            runtimeVersion: "2026.1",
            texLiveYear: 2026,
            variant: .standard,
            architecture: .arm64,
            rootPath: root.path,
            tools: ["pdflatex": "bin/pdflatex"]
        )
        let recordURL = root.appendingPathComponent(".lightex-runtime.json")
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)

        let installed = try RuntimeManager.scanInstalledRuntimes(
            in: temporary,
            activeRecordPath: recordURL.path
        )
        #expect(installed.count == 1)
        #expect(installed.first?.isActive == true)
        #expect(installed.first?.installedSize ?? 0 > 0)
        #expect(RuntimeManager.directorySize(at: root) > 0)
    }

    @Test
    func instantiatesTextbookWithoutOpenRightBlankPages() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let templates = temporary.appendingPathComponent("Templates", isDirectory: true)
        let projects = temporary.appendingPathComponent("Projects", isDirectory: true)
        let store = ProjectTemplateStore(userTemplatesDirectory: templates)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let textbook = try #require(
            ProjectTemplate.builtInTemplates.first { $0.id == "lightex.textbook" }
        )
        let project = try store.instantiate(
            template: textbook,
            projectName: "Linear Algebra",
            author: "Author",
            location: projects
        )
        let contents = try String(
            contentsOf: project.appendingPathComponent("main.tex"),
            encoding: .utf8
        )

        #expect(contents.contains("oneside,openany"))
        #expect(contents.contains("Linear Algebra"))
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("figures").path))
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("scripts").path))
    }

    @Test
    func rejectsTemplateLibraryNestedInsideItsSource() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = temporary.appendingPathComponent("Project", isDirectory: true)
        let nestedLibrary = source.appendingPathComponent("Templates/Yours", isDirectory: true)
        let store = ProjectTemplateStore(userTemplatesDirectory: nestedLibrary)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try "\\documentclass{article}\n\\begin{document}\n\\end{document}\n".write(
            to: source.appendingPathComponent("main.tex"),
            atomically: true,
            encoding: .utf8
        )

        #expect(throws: ProjectTemplateError.self) {
            try store.saveUserTemplate(from: source, name: "Unsafe", summary: "")
        }
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
        #expect(!contents.contains("\\begin{titlepage}"))
        #expect(contents.contains("\\title{EmptyBook}"))
        #expect(contents.contains("\\section{Introduction}"))
        #expect(contents.contains("Start writing here."))

        model.closeProject()
        #expect(model.hasProject == false)
        #expect(model.recentProjects.map(\.name) == ["EmptyBook"])

        model.clearRecentProjects()
        #expect(model.recentProjects.isEmpty)
        #expect(FileManager.default.fileExists(atPath: mainFile.path))
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

    @Test @MainActor
    func dirtyDocumentCloseCanBeCancelledOrSaved() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let main = temporary.appendingPathComponent("main.tex")
        try "original".write(to: main, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporary) }

        do {
            let defaults = makeIsolatedDefaults()
            let settings = AppSettings(defaults: defaults)
            let coordinator = DirtyDocumentCoordinator { request in
                #expect(request.documentNames == ["main.tex"])
                return .cancel
            }
            let model = AppModel(
                settings: settings,
                defaults: defaults,
                dirtyDocumentCoordinator: coordinator
            )
            model.openProject(temporary)
            model.updateSelectedText("cancelled edit")
            model.closeDocument(main)
            #expect(model.openDocuments.count == 1)
            #expect(try String(contentsOf: main, encoding: .utf8) == "original")
        }

        do {
            let defaults = makeIsolatedDefaults()
            let settings = AppSettings(defaults: defaults)
            let coordinator = DirtyDocumentCoordinator { _ in .save }
            let model = AppModel(
                settings: settings,
                defaults: defaults,
                dirtyDocumentCoordinator: coordinator
            )
            model.openProject(temporary)
            model.updateSelectedText("saved edit")
            model.closeDocument(main)
            #expect(model.openDocuments.isEmpty)
            #expect(try String(contentsOf: main, encoding: .utf8) == "saved edit")
        }
    }

    @Test
    func documentRevisionDetectsAChangedFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try "one".write(to: file, atomically: true, encoding: .utf8)
        let first = try DocumentRevision.read(from: file).revision
        try "two".write(to: file, atomically: true, encoding: .utf8)
        let second = try DocumentRevision.read(from: file).revision

        #expect(first.contentHash != second.contentHash)
        #expect(first.fileSize == second.fileSize)
    }

    @Test
    func projectSearchUsesDirtySourcesAndBuildsReversibleReplacement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("main.tex")
        let notes = root.appendingPathComponent("notes.tex")
        try "Alpha on disk".write(to: main, atomically: true, encoding: .utf8)
        try "alpha in notes".write(to: notes, atomically: true, encoding: .utf8)

        let query = ProjectSearchQuery(text: "alpha", caseSensitive: false)
        let openSources = [main: "alpha from unsaved editor"]
        let results = try ProjectSearchService.search(
            projectURL: root,
            query: query,
            openSources: openSources
        )
        #expect(results.count == 2)
        #expect(results.contains { $0.fileURL == main && $0.preview.contains("unsaved") })

        let transaction = try ProjectSearchService.replacementTransaction(
            projectURL: root,
            query: query,
            replacement: "beta",
            openSources: openSources
        )
        #expect(transaction.changes.count == 2)
        #expect(transaction.changes.first { $0.fileURL == main }?.replacementText == "beta from unsaved editor")
    }

    @Test
    func incrementalHighlightRangeDoesNotCoverUnchangedDocument() {
        let source = NSString(string: (0..<100).map { "line \($0)" }.joined(separator: "\n"))
        let editedLocation = source.range(of: "line 50").location
        let range = SyntaxHighlighter.highlightRange(
            in: source,
            editedRange: NSRange(location: editedLocation, length: 1)
        )
        #expect(range.location > 0)
        #expect(range.length < source.length / 4)
        #expect(NSLocationInRange(editedLocation, range))
    }

    @Test @MainActor
    func persistsChosenMainDocumentPerProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("main.tex")
        let alternate = root.appendingPathComponent("alternate.tex")
        try "\\documentclass{article}".write(to: main, atomically: true, encoding: .utf8)
        try "\\documentclass{article}".write(to: alternate, atomically: true, encoding: .utf8)

        let defaults = makeIsolatedDefaults()
        let firstSettings = AppSettings(defaults: defaults)
        let first = AppModel(settings: firstSettings, defaults: defaults)
        first.openProject(root)
        first.setEntryFile(alternate)
        first.closeProject()

        let secondSettings = AppSettings(defaults: defaults)
        let second = AppModel(settings: secondSettings, defaults: defaults)
        second.openProject(root)
        #expect(second.entryFileURL == alternate)
        second.closeProject()
    }

    @Test
    func groupsCompilerCascadeUnderOnePrimaryProblem() {
        let problems = [
            BuildProblem(
                severity: .error,
                fileURL: URL(fileURLWithPath: "/tmp/main.tex"),
                fileDisplayName: "main.tex",
                line: 3,
                message: "File `missing.sty' not found"
            ),
            BuildProblem(
                severity: .error,
                fileURL: nil,
                fileDisplayName: "Build",
                line: nil,
                message: "Emergency stop"
            ),
            BuildProblem(
                severity: .error,
                fileURL: nil,
                fileDisplayName: "Build",
                line: nil,
                message: "Fatal error occurred"
            )
        ]
        let groups = BuildProblemParser.groups(
            from: problems,
            missingPackageFile: "missing.sty"
        )
        #expect(groups.count == 1)
        #expect(groups[0].primary.line == 3)
        #expect(groups[0].related.count == 2)
    }

    @Test
    func indexesProjectCompletionSymbolsAndSelectsContext() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("main.tex")
        let bib = root.appendingPathComponent("references.bib")
        let figure = root.appendingPathComponent("figures/plot.png")
        try FileManager.default.createDirectory(
            at: figure.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"\usepackage{tcolorbox}\label{sec:vectors}\newcommand{\vect}{}"#
            .write(to: main, atomically: true, encoding: .utf8)
        try "@book{knuth1984, title={TeX}}".write(to: bib, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: figure.path, contents: Data())

        let symbols = [
            main: LatexCompletionService.parseSymbols(
                in: try String(contentsOf: main, encoding: .utf8),
                fileURL: main
            ),
            bib: LatexCompletionService.parseSymbols(
                in: try String(contentsOf: bib, encoding: .utf8),
                fileURL: bib
            )
        ]
        let index = LatexCompletionService.makeIndex(projectURL: root, symbols: symbols)
        #expect(index.labels.contains("sec:vectors"))
        #expect(index.citations.contains("knuth1984"))
        #expect(index.packages.contains("tcolorbox"))
        #expect(index.commands.contains("vect"))
        #expect(index.graphicsPaths.contains("figures/plot.png"))

        let source = #"\ref{sec:v"#
        let context = LatexCompletionService.context(
            in: source,
            selection: NSRange(location: (source as NSString).length, length: 0)
        )
        #expect(context?.kind == .reference)
        #expect(
            LatexCompletionService.completions(for: context!, index: index).map(\.label)
                == ["sec:vectors"]
        )
    }

    @Test
    func parsesInverseSyncTeXTargetAndUsesPortableDecimals() {
        let project = URL(fileURLWithPath: "/tmp/My Book", isDirectory: true)
        let output = """
        SyncTeX result begin
        Input:sections/vectors.tex
        Line:42
        Column:-1
        SyncTeX result end
        """
        let target = SyncTeXService.sourceTarget(from: output, projectURL: project)
        #expect(target?.fileURL == project.appendingPathComponent("sections/vectors.tex"))
        #expect(target?.line == 42)
        #expect(target?.column == 1)

        let argument = SyncTeXService.editPositionArgument(
            previewPDFURL: project.appendingPathComponent("main.pdf"),
            page: 3,
            x: 12.5,
            yFromTop: 48.25
        )
        #expect(argument.hasPrefix("3:12.500:48.250:"))
    }

    @Test
    func insertShelfWrapsMathWithDollarSigns() throws {
        let request = LatexInsertionRequest(
            template: "\\alpha" + LatexInsertionRequest.cursorMarker,
            mode: .math,
            actionName: "Insert Alpha"
        )
        let result = try #require(LatexInsertionService.result(
            in: "Value: ",
            selection: NSRange(location: 7, length: 0),
            request: request
        ))
        #expect(result.replacement == "$\\alpha$")
        #expect(result.cursorLocation == 14)
    }

    @Test
    func insertShelfDoesNotNestDollarSignsInsideMath() throws {
        let source = "$x + $"
        let request = LatexInsertionRequest(
            template: "\\beta" + LatexInsertionRequest.cursorMarker,
            mode: .math,
            actionName: "Insert Beta"
        )
        let result = try #require(LatexInsertionService.result(
            in: source,
            selection: NSRange(location: 5, length: 0),
            request: request
        ))
        #expect(result.replacement == "\\beta")
        #expect(result.cursorLocation == 10)
    }

    @Test
    func insertShelfRecognizesMathEnvironmentsAndIgnoresCommentedMath() throws {
        let request = LatexInsertionRequest(
            template: "\\gamma" + LatexInsertionRequest.cursorMarker,
            mode: .math,
            actionName: "Insert Gamma"
        )
        let equation = "\\begin{equation}\nx = "
        let inEnvironment = try #require(LatexInsertionService.result(
            in: equation,
            selection: NSRange(location: (equation as NSString).length, length: 0),
            request: request
        ))
        #expect(inEnvironment.replacement == "\\gamma")

        let afterComment = "% $comment only\nValue: "
        let outsideMath = try #require(LatexInsertionService.result(
            in: afterComment,
            selection: NSRange(location: (afterComment as NSString).length, length: 0),
            request: request
        ))
        #expect(outsideMath.replacement == "$\\gamma$")
    }

    @Test
    func insertShelfResizesCompactlyAndClosesLikeABlind() {
        #expect(InsertShelfSizing.defaultHeight == 168)
        #expect(
            InsertShelfSizing.height(
                from: InsertShelfSizing.defaultHeight,
                translation: -110
            ) == 58
        )
        #expect(
            InsertShelfSizing.shouldClose(
                currentHeight: 58,
                predictedHeight: 32
            )
        )
        #expect(
            !InsertShelfSizing.shouldClose(
                currentHeight: InsertShelfSizing.minimumHeight,
                predictedHeight: InsertShelfSizing.minimumHeight
            )
        )
        #expect(
            InsertShelfSizing.height(
                from: InsertShelfSizing.maximumHeight,
                translation: 100
            ) == InsertShelfSizing.maximumHeight
        )
    }

    @Test
    func insertShelfUsesDollarSyntaxForInlineAndDisplayMath() throws {
        let inline = try #require(LatexInsertionService.result(
            in: "x + y",
            selection: NSRange(location: 0, length: 5),
            request: LatexInsertCatalog.inlineMath
        ))
        #expect(inline.replacement == "$x + y$")
        #expect(!inline.replacement.contains("\\("))

        let display = try #require(LatexInsertionService.result(
            in: "",
            selection: NSRange(location: 0, length: 0),
            request: LatexInsertCatalog.displayMath
        ))
        #expect(display.replacement == "$$\n  \n$$")
        #expect(!display.replacement.contains("\\["))
    }

    @Test @MainActor
    func insertShelfInsertionIsOneUndoableEditorAction() throws {
        let textView = CodeTextView()
        textView.allowsUndo = true
        textView.string = "vector"
        textView.setSelectedRange(NSRange(location: 0, length: 6))
        textView.performLatexInsertion(LatexInsertCatalog.inlineMath)
        #expect(textView.string == "$vector$")
        #expect(textView.undoManager?.canUndo == true)
        textView.undoManager?.undo()
        #expect(textView.string == "vector")
    }

    @Test @MainActor
    func importsFigureWithoutOverwritingAnExistingProjectFile() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = temporary.appendingPathComponent("source", isDirectory: true)
        let projects = temporary.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let image = source.appendingPathComponent("diagram.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)

        let defaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.automaticBuilds = false
        let model = AppModel(settings: settings, defaults: defaults)
        #expect(model.createProject(name: "Figures", location: projects))
        let first = model.prepareFigureImage(image)
        let second = model.prepareFigureImage(image)
        #expect(first == "diagram.png")
        #expect(second == "diagram 2.png")
        #expect(FileManager.default.fileExists(
            atPath: projects.appendingPathComponent("Figures/diagram.png").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: projects.appendingPathComponent("Figures/diagram 2.png").path
        ))
        model.closeProject()
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

@MainActor
private func lineFragmentRect(
    in textView: CodeTextView,
    atCharacter characterIndex: Int
) throws -> NSRect {
    let layoutManager = try #require(textView.layoutManager)
    let textContainer = try #require(textView.textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterIndex, length: 1),
        actualCharacterRange: nil
    )
    return layoutManager.lineFragmentRect(
        forGlyphAt: glyphRange.location,
        effectiveRange: nil
    )
}
