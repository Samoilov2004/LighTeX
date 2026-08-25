import Foundation
import UniformTypeIdentifiers

struct ProjectItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let children: [ProjectItem]?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var iconName: String {
        if isDirectory { return "folder" }
        switch url.pathExtension.lowercased() {
        case "tex": return "doc.plaintext"
        case "bib": return "books.vertical"
        case "sty", "cls": return "doc.badge.gearshape"
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "svg", "eps": return "photo"
        default: return "doc"
        }
    }

    var isEditableText: Bool {
        let pathExtension = url.pathExtension.lowercased()
        let knownTextExtensions: Set<String> = [
            "tex", "bib", "sty", "cls", "txt", "md", "markdown",
            "json", "yaml", "yml", "toml", "csv", "tsv", "xml",
            "html", "css", "js", "ts", "py", "rb", "sh", "lua"
        ]
        if knownTextExtensions.contains(pathExtension) {
            return true
        }
        if pathExtension.isEmpty {
            return ["Makefile", "Dockerfile"].contains(name)
        }
        return UTType(filenameExtension: pathExtension)?.conforms(to: .text) == true
    }
}

enum ProjectScanner {
    private static let ignoredDirectories: Set<String> = [
        ".git", ".build", "build", "node_modules", "DerivedData", ".idea"
    ]
    static func projectTree(in projectURL: URL) -> [ProjectItem] {
        children(of: projectURL)
    }

    static func texFiles(in projectURL: URL) -> [URL] {
        flatten(projectTree(in: projectURL))
            .filter { !$0.isDirectory && $0.url.pathExtension.lowercased() == "tex" }
            .map(\.url)
    }

    static func preferredEntryPoint(from files: [URL]) -> URL? {
        if let main = files.first(where: { $0.lastPathComponent.lowercased() == "main.tex" }) {
            return main
        }

        if let document = files.first(where: {
            (try? String(contentsOf: $0, encoding: .utf8))?.contains("\\documentclass") == true
        }) {
            return document
        }

        return files.first
    }

    static func relativePath(for fileURL: URL, inside projectURL: URL) -> String {
        let root = projectURL.standardizedFileURL.path
        let file = fileURL.standardizedFileURL.path
        guard file.hasPrefix(root + "/") else { return fileURL.lastPathComponent }
        return String(file.dropFirst(root.count + 1))
    }

    private static func children(of directory: URL) -> [ProjectItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url -> ProjectItem? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isHidden != true else {
                return nil
            }

            if values.isDirectory == true {
                guard !ignoredDirectories.contains(url.lastPathComponent) else { return nil }
                let nested = children(of: url)
                return ProjectItem(
                    url: url,
                    isDirectory: true,
                    children: nested
                )
            }
            guard values.isRegularFile == true else { return nil }
            return ProjectItem(url: url, isDirectory: false, children: nil)
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func flatten(_ items: [ProjectItem]) -> [ProjectItem] {
        items.flatMap { item in
            [item] + flatten(item.children ?? [])
        }
    }
}
