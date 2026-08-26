import AppKit
import Foundation
import PDFKit

enum TemplatePreviewService {
    static func generate(
        for template: ProjectTemplate,
        configuration: BuildConfiguration
    ) async {
        guard let templateDirectory = template.userDirectory else { return }
        let files = templateDirectory.appendingPathComponent("files", isDirectory: true)
        let entry = files.appendingPathComponent(template.entryFile)
        guard FileManager.default.fileExists(atPath: entry.path) else { return }

        let generatedPDF = files.appendingPathComponent(
            entry.deletingPathExtension().lastPathComponent + ".pdf"
        )
        let existedBefore = FileManager.default.fileExists(atPath: generatedPDF.path)
        let result = await LatexBuildService.build(
            projectURL: files,
            entryFileURL: entry,
            configuration: configuration
        )
        guard result.succeeded,
              let pdfURL = result.projectPDF,
              let document = PDFDocument(url: pdfURL),
              let page = document.page(at: 0) else { return }

        let image = page.thumbnail(of: NSSize(width: 900, height: 1_200), for: .cropBox)
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(using: .png, properties: [:]) else { return }
        try? png.write(
            to: templateDirectory.appendingPathComponent("preview.png"),
            options: .atomic
        )
        if !existedBefore { try? FileManager.default.removeItem(at: generatedPDF) }
    }
}
