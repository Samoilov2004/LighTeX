import PDFKit
import SwiftUI

@MainActor
final class PDFPreviewController: ObservableObject {
    @Published private(set) var zoomPercent = 100
    @Published private(set) var currentPage = 0
    @Published private(set) var pageCount = 0

    weak var pdfView: PDFView?
    private var refreshScheduled = false
    private var pendingTarget: PDFJumpTarget?

    var pageLabel: String {
        pageCount == 0 ? "—" : "\(currentPage) of \(pageCount)"
    }

    func attach(_ view: PDFView) {
        if pdfView !== view {
            pdfView = view
        }
    }

    func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refreshState()
        }
    }

    func zoomIn() {
        guard let pdfView else { return }
        pdfView.autoScales = false
        pdfView.zoomIn(nil)
        refreshState()
    }

    func zoomOut() {
        guard let pdfView else { return }
        pdfView.autoScales = false
        pdfView.zoomOut(nil)
        refreshState()
    }

    func fitPage() {
        guard let pdfView else { return }
        pdfView.autoScales = true
        refreshState()
    }

    func fitWidth() {
        guard let pdfView,
              let page = pdfView.currentPage else {
            return
        }
        let pageWidth = page.bounds(for: pdfView.displayBox).width
        let availableWidth = max(1, pdfView.bounds.width - 32)
        pdfView.autoScales = false
        pdfView.scaleFactor = availableWidth / pageWidth
        refreshState()
    }

    func previousPage() {
        pdfView?.goToPreviousPage(nil)
        refreshState()
    }

    func nextPage() {
        pdfView?.goToNextPage(nil)
        refreshState()
    }

    func goTo(_ target: PDFJumpTarget?) {
        guard let target, target.page > 0 else { return }
        pendingTarget = target
        applyPendingNavigation()
    }

    func applyPendingNavigation() {
        guard let pendingTarget,
              let pdfView,
              let document = pdfView.document,
              let page = document.page(at: pendingTarget.page - 1) else {
            return
        }
        self.pendingTarget = nil
        if let x = pendingTarget.x, let yFromTop = pendingTarget.yFromTop {
            let pageBounds = page.bounds(for: pdfView.displayBox)
            let destination = PDFDestination(
                page: page,
                at: NSPoint(
                    x: pageBounds.minX + x,
                    y: pageBounds.maxY - yFromTop
                )
            )
            pdfView.go(to: destination)
        } else {
            pdfView.go(to: page)
        }
        refreshState()
    }

    func refreshState() {
        guard let pdfView else { return }
        let nextZoomPercent = Int((pdfView.scaleFactor * 100).rounded())
        let nextPageCount = pdfView.document?.pageCount ?? 0
        let nextCurrentPage: Int
        if let page = pdfView.currentPage,
           let index = pdfView.document?.index(for: page) {
            nextCurrentPage = index + 1
        } else {
            nextCurrentPage = 0
        }

        if zoomPercent != nextZoomPercent {
            zoomPercent = nextZoomPercent
        }
        if pageCount != nextPageCount {
            pageCount = nextPageCount
        }
        if currentPage != nextCurrentPage {
            currentPage = nextCurrentPage
        }
    }
}

struct PDFPreview: NSViewRepresentable {
    let url: URL
    let revision: Int
    @ObservedObject var controller: PDFPreviewController

    @MainActor
    final class Coordinator: NSObject {
        var loadedRevision = -1
        weak var controller: PDFPreviewController?

        @objc func stateChanged(_ notification: Notification) {
            controller?.scheduleRefresh()
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.controller = controller
        return coordinator
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.backgroundColor = NSColor(calibratedWhite: 0.94, alpha: 1)
        view.minScaleFactor = 0.2
        view.maxScaleFactor = 5

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.stateChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.stateChanged(_:)),
            name: .PDFViewScaleChanged,
            object: view
        )
        controller.attach(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.controller = controller
        controller.attach(view)
        guard context.coordinator.loadedRevision != revision else { return }
        context.coordinator.loadedRevision = revision

        let previousDocument = view.document
        let previousPageIndex = view.currentPage.flatMap { previousDocument?.index(for: $0) }
        let previousScale = view.scaleFactor
        let wasAutoScaling = view.autoScales
        view.document = PDFDocument(url: url)
        if previousDocument == nil {
            view.autoScales = true
        } else {
            view.autoScales = wasAutoScaling
            if !wasAutoScaling {
                view.scaleFactor = min(max(previousScale, view.minScaleFactor), view.maxScaleFactor)
            }
            if let previousPageIndex,
               let restoredPage = view.document?.page(at: previousPageIndex) {
                view.go(to: restoredPage)
            }
        }
        controller.applyPendingNavigation()
        controller.scheduleRefresh()
    }
}
