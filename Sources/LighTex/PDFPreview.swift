import PDFKit
import SwiftUI

@MainActor
final class PDFPreviewController: ObservableObject {
    @Published private(set) var zoomPercent = 100
    @Published private(set) var currentPage = 0
    @Published private(set) var pageCount = 0
    @Published private(set) var searchMatchCount = 0
    @Published private(set) var currentSearchMatch = 0

    weak var pdfView: PDFView?
    private var refreshScheduled = false
    private var pendingTarget: PDFJumpTarget?
    private var searchSelections: [PDFSelection] = []
    private var searchQuery = ""

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

    func goToPage(_ pageNumber: Int) {
        guard let pdfView,
              let page = pdfView.document?.page(at: max(0, min(pageNumber - 1, pageCount - 1))) else {
            return
        }
        pdfView.go(to: page)
        refreshState()
    }

    func search(_ query: String) {
        searchQuery = query
        guard let pdfView, let document = pdfView.document, !query.isEmpty else {
            searchSelections = []
            searchMatchCount = 0
            currentSearchMatch = 0
            pdfView?.highlightedSelections = nil
            return
        }
        searchSelections = document.findString(query, withOptions: [.caseInsensitive])
        searchMatchCount = searchSelections.count
        currentSearchMatch = searchSelections.isEmpty ? 0 : 1
        pdfView.highlightedSelections = searchSelections
        if let first = searchSelections.first {
            pdfView.setCurrentSelection(first, animate: true)
            pdfView.go(to: first)
        }
    }

    func nextSearchMatch() {
        guard !searchSelections.isEmpty, let pdfView else { return }
        currentSearchMatch = currentSearchMatch % searchSelections.count + 1
        let selection = searchSelections[currentSearchMatch - 1]
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)
    }

    func previousSearchMatch() {
        guard !searchSelections.isEmpty, let pdfView else { return }
        currentSearchMatch = currentSearchMatch <= 1
            ? searchSelections.count
            : currentSearchMatch - 1
        let selection = searchSelections[currentSearchMatch - 1]
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)
    }

    func reapplySearch() {
        search(searchQuery)
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
            positionTargetNearTop(
                point: destination.point,
                page: page,
                in: pdfView
            )
        } else {
            pdfView.go(to: page)
        }
        refreshState()
    }

    private func positionTargetNearTop(point: NSPoint, page: PDFPage, in pdfView: PDFView) {
        DispatchQueue.main.async { [weak pdfView] in
            guard let pdfView,
                  let documentView = pdfView.documentView,
                  let clipView = documentView.enclosingScrollView?.contentView else { return }
            let pointInPDFView = pdfView.convert(point, from: page)
            let pointInDocument = documentView.convert(pointInPDFView, from: pdfView)
            let targetY = max(0, pointInDocument.y - clipView.bounds.height / 3)
            clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: targetY))
            documentView.enclosingScrollView?.reflectScrolledClipView(clipView)
        }
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
    let onDoubleClick: (Int, Double, Double) -> Void

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
        let view = SyncedPDFView()
        view.onSourceRequest = onDoubleClick
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
        (view as? SyncedPDFView)?.onSourceRequest = onDoubleClick
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
        controller.reapplySearch()
        controller.scheduleRefresh()
    }
}

private final class SyncedPDFView: PDFView {
    var onSourceRequest: ((Int, Double, Double) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else {
            super.mouseDown(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true),
              let pageIndex = document?.index(for: page) else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(viewPoint, to: page)
        let bounds = page.bounds(for: displayBox)
        onSourceRequest?(
            pageIndex + 1,
            Double(max(0, point.x - bounds.minX)),
            Double(max(0, bounds.maxY - point.y))
        )
    }
}
