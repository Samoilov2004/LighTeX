import AppKit
import Foundation

@MainActor
final class DirtyDocumentCoordinator {
    typealias DecisionProvider = @MainActor (CloseRequest) -> CloseDecision

    private let decisionProvider: DecisionProvider

    init(decisionProvider: DecisionProvider? = nil) {
        self.decisionProvider = decisionProvider ?? Self.presentNativePrompt
    }

    func decision(for request: CloseRequest) -> CloseDecision {
        decisionProvider(request)
    }

    private static func presentNativePrompt(for request: CloseRequest) -> CloseDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let count = request.documentNames.count
        switch request.kind {
        case .document:
            alert.messageText = "Do you want to save the changes?"
            alert.informativeText = "Your changes to \(request.documentNames.first ?? "this document") will be lost if you don’t save them."
            alert.addButton(withTitle: "Save")
        case .project, .switchProject, .application:
            alert.messageText = "Save changes to \(count) document\(count == 1 ? "" : "s")?"
            let visibleNames = request.documentNames.prefix(6).joined(separator: "\n")
            let remainder = max(0, count - 6)
            alert.informativeText = visibleNames
                + (remainder > 0 ? "\nand \(remainder) more…" : "")
                + "\n\nUnsaved changes will be lost if you don’t save them."
            alert.addButton(withTitle: "Save All")
        }
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }
}
