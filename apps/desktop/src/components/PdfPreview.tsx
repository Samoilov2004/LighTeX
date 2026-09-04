import { useCallback, useEffect, useMemo, useRef, useState, type MouseEvent as ReactMouseEvent, type RefObject } from "react";
import { createPortal } from "react-dom";
import { ChevronLeft, ChevronRight, CircleX, Maximize2, Minus, Plus, Search, X } from "lucide-react";
import type { PDFDocumentProxy, PDFPageProxy } from "pdfjs-dist";
import type { OutlineItem, SyncTeXPdfTarget } from "../types";
import type { BuildFailurePresentation } from "../buildDiagnostics";
import { pdfjs } from "../pdf";
import { findOutlinePages, findOutlinePagesFromBookmarks, type PdfBookmarkPage } from "../outlinePages";
import { BuildLogPopover, type BuildLogAnchor } from "./BuildLogPopover";

interface PdfPreviewProps {
  base64: string | null;
  target: SyncTeXPdfTarget | null;
  outline: OutlineItem[];
  failure?: BuildFailurePresentation | null;
  onOutlinePages(pages: Record<string, number>): void;
  onInverse(page: number, x: number, yFromTop: number): void;
  onRecover(engine: BuildFailurePresentation["suggestedEngine"]): void;
}

export function PdfPreview({ base64, target, outline, failure = null, onOutlinePages, onInverse, onRecover }: PdfPreviewProps) {
  const [document, setDocument] = useState<PDFDocumentProxy | null>(null);
  const [page, setPage] = useState(1);
  const [zoom, setZoom] = useState(0.9);
  const [basePageSize, setBasePageSize] = useState({ width: 612, height: 792 });
  const [query, setQuery] = useState("");
  const [searchOpen, setSearchOpen] = useState(false);
  const [matches, setMatches] = useState<Array<{ page: number; count: number }>>([]);
  const scroll = useRef<HTMLDivElement>(null);
  const scrollFrame = useRef<number | null>(null);
  const pageTextCache = useRef<{ document: PDFDocumentProxy | null; texts: Array<string | undefined> }>({ document: null, texts: [] });

  useEffect(() => {
    let active = true;
    setDocument(null);
    setPage(1);
    setBasePageSize({ width: 612, height: 792 });
    pageTextCache.current = { document: null, texts: [] };
    if (!base64) return;
    const binary = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
    const task = pdfjs.getDocument({ data: binary });
    task.promise.then(async (loaded) => {
      if (!active) {
        void loaded.destroy();
        return;
      }
      setDocument(loaded);
      const first = await loaded.getPage(1);
      if (active) {
        const viewport = first.getViewport({ scale: 1 });
        setBasePageSize({ width: viewport.width, height: viewport.height });
      }
    });
    return () => {
      active = false;
      void task.destroy();
    };
  }, [base64]);

  useEffect(() => {
    if (!document || outline.length === 0) return;
    let cancelled = false;
    if (pageTextCache.current.document !== document) {
      pageTextCache.current = { document, texts: Array.from({ length: document.numPages }) };
    }
    const cache = pageTextCache.current;
    void (async () => {
      const bookmarkPages = await extractBookmarkPages(document);
      const mappedBookmarks = findOutlinePagesFromBookmarks(outline, bookmarkPages);
      if (cancelled) return;
      if (Object.keys(mappedBookmarks).length > 0) onOutlinePages(mappedBookmarks);
      if (Object.keys(mappedBookmarks).length === outline.length) return;
      let cursor = 0;
      const loadPageText = async () => {
        while (!cancelled) {
          const index = cursor;
          cursor += 1;
          if (index >= document.numPages) return;
          if (cache.texts[index] !== undefined) continue;
          try {
            const pdfPage = await document.getPage(index + 1);
            const content = await pdfPage.getTextContent();
            cache.texts[index] = content.items.map((item) => "str" in item ? item.str : "").join(" ");
          } catch {
            cache.texts[index] = "";
          }
        }
      };
      await Promise.all(Array.from({ length: Math.min(3, document.numPages) }, () => loadPageText()));
      if (!cancelled) {
        const textPages = findOutlinePages(outline, cache.texts.map((text) => text ?? ""));
        onOutlinePages({ ...textPages, ...mappedBookmarks });
      }
    })();
    return () => { cancelled = true; };
  }, [document, outline, onOutlinePages]);

  useEffect(() => {
    let cancelled = false;
    if (!document || !query.trim()) {
      setMatches([]);
      return;
    }
    void (async () => {
      const found: Array<{ page: number; count: number }> = [];
      for (let number = 1; number <= document.numPages; number += 1) {
        const pdfPage = await document.getPage(number);
        const text = await pdfPage.getTextContent();
        const source = text.items.map((item) => "str" in item ? item.str : "").join(" ");
        const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const count = (source.match(new RegExp(escaped, "giu")) ?? []).length;
        if (count > 0) found.push({ page: number, count });
      }
      if (!cancelled) setMatches(found);
    })();
    return () => { cancelled = true; };
  }, [document, query]);

  const matchPosition = matches.findIndex((match) => match.page === page);
  const matchCount = matches.reduce((sum, match) => sum + match.count, 0);
  const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const scrollToPage = useCallback((requested: number, behavior: ScrollBehavior = reducedMotion() ? "auto" : "smooth", yFromTop?: number) => {
    const scroller = scroll.current;
    if (!scroller || !document) return;
    const nextPage = Math.max(1, Math.min(requested, document.numPages));
    setPage(nextPage);
    window.requestAnimationFrame(() => {
      const slot = scroller.querySelector<HTMLElement>(`.pdf-page-slot[data-page="${nextPage}"]`);
      if (!slot) return;
      const targetTop = yFromTop == null
        ? slot.offsetTop - 12
        : slot.offsetTop + yFromTop * zoom - scroller.clientHeight / 3;
      scroller.scrollTo({ top: Math.max(0, targetTop), behavior });
    });
  }, [document, zoom]);
  const nextMatch = (direction: -1 | 1) => {
    if (matches.length === 0) return;
    const current = matchPosition < 0 ? 0 : matchPosition;
    const next = (current + direction + matches.length) % matches.length;
    scrollToPage(matches[next].page);
  };

  useEffect(() => {
    if (!target?.page) return;
    scrollToPage(target.page, "auto", target.yFromTop ?? undefined);
  }, [target, scrollToPage]);

  const handleScroll = () => {
    if (scrollFrame.current != null) return;
    scrollFrame.current = window.requestAnimationFrame(() => {
      scrollFrame.current = null;
      const scroller = scroll.current;
      if (!scroller) return;
      const marker = scroller.scrollTop + scroller.clientHeight * 0.32;
      let visiblePage = 1;
      for (const slot of scroller.querySelectorAll<HTMLElement>(".pdf-page-slot")) {
        if (slot.offsetTop <= marker) visiblePage = Number(slot.dataset.page) || visiblePage;
        else break;
      }
      setPage((current) => current === visiblePage ? current : visiblePage);
    });
  };

  useEffect(() => () => {
    if (scrollFrame.current != null) window.cancelAnimationFrame(scrollFrame.current);
  }, []);

  const changeZoom = (nextZoom: number) => {
    const activePage = page;
    setZoom(nextZoom);
    window.requestAnimationFrame(() => scrollToPage(activePage, "auto"));
  };

  const fitWidth = () => {
    const available = Math.max(240, (scroll.current?.clientWidth ?? 700) - 36);
    changeZoom(Math.max(0.35, Math.min(2.5, available / basePageSize.width)));
  };

  const pageNumbers = useMemo(() => Array.from({ length: document?.numPages ?? 0 }, (_, index) => index + 1), [document]);

  if (!base64) {
    return (
      <section className={`pdf-pane empty-pdf ${failure ? "build-failed" : ""}`} aria-label="PDF preview">
        <div className="pdf-toolbar">
          <strong>PDF</strong>
          <div className="toolbar-spacer" />
          {failure && <span className="pdf-failed-status"><CircleX size={12} aria-hidden="true" />Failed</span>}
        </div>
        {failure ? <PdfBuildFailure failure={failure} onRecover={onRecover} /> : <div className="empty-state compact">
          <span className="empty-state-title">PDF Preview</span>
          <span>Compile the main document to see the result.</span>
        </div>}
      </section>
    );
  }

  return (
    <section className="pdf-pane" aria-label="PDF preview">
      <div className="pdf-toolbar">
        <strong>PDF</strong>
        <div className="toolbar-spacer" />
        {searchOpen && (
          <div className="pdf-search">
            <Search size={13} aria-hidden="true" />
            <input value={query} onChange={(event) => setQuery(event.target.value)} aria-label="Search PDF" autoFocus />
            <span>{matchCount}</span>
            <button className="icon-button small" onClick={() => setSearchOpen(false)} aria-label="Close PDF search" title="Close search"><X size={13} /></button>
          </div>
        )}
        {!searchOpen && <button className="icon-button" onClick={() => setSearchOpen(true)} aria-label="Search PDF" title="Search PDF"><Search size={15} /></button>}
        {searchOpen && <>
          <button className="icon-button" onClick={() => nextMatch(-1)} disabled={matches.length === 0} aria-label="Previous match"><ChevronLeft size={15} /></button>
          <button className="icon-button" onClick={() => nextMatch(1)} disabled={matches.length === 0} aria-label="Next match"><ChevronRight size={15} /></button>
        </>}
        <button className="icon-button" onClick={() => scrollToPage(page - 1)} disabled={page <= 1} aria-label="Previous page"><ChevronLeft size={15} /></button>
        <label className="page-field">
          <span className="sr-only">Current page</span>
          <input
            value={page}
            inputMode="numeric"
            onChange={(event) => scrollToPage(Number(event.target.value) || 1)}
          />
          <span>of {document?.numPages ?? "—"}</span>
        </label>
        <button className="icon-button" onClick={() => scrollToPage(page + 1)} disabled={!document || page >= document.numPages} aria-label="Next page"><ChevronRight size={15} /></button>
        <button className="icon-button" onClick={() => changeZoom(Math.max(0.35, zoom - 0.1))} aria-label="Zoom out"><Minus size={15} /></button>
        <span className="zoom-label">{Math.round(zoom * 100)}%</span>
        <button className="icon-button" onClick={() => changeZoom(Math.min(2.5, zoom + 0.1))} aria-label="Zoom in"><Plus size={15} /></button>
        <button className="icon-button" onClick={fitWidth} aria-label="Fit width" title="Fit width"><Maximize2 size={15} /></button>
      </div>
      <div className="pdf-scroll" ref={scroll} onScroll={handleScroll}>
        <div className="pdf-pages">
          {document && pageNumbers.map((pageNumber) => <PdfPage
            key={pageNumber}
            document={document}
            pageNumber={pageNumber}
            zoom={zoom}
            query={query}
            target={target?.page === pageNumber ? target : null}
            scrollRoot={scroll}
            estimatedSize={{ width: basePageSize.width * zoom, height: basePageSize.height * zoom }}
            onInverse={onInverse}
          />)}
        </div>
      </div>
    </section>
  );
}

function PdfBuildFailure({ failure, onRecover }: {
  failure: BuildFailurePresentation;
  onRecover(engine: BuildFailurePresentation["suggestedEngine"]): void;
}) {
  const [logAnchor, setLogAnchor] = useState<BuildLogAnchor | null>(null);

  useEffect(() => setLogAnchor(null), [failure.log, failure.detail]);

  const closeLog = useCallback((restoreFocus = false) => {
    setLogAnchor((current) => {
      if (restoreFocus) current?.trigger.focus({ preventScroll: true });
      return null;
    });
  }, []);

  const openLog = (event: ReactMouseEvent<HTMLButtonElement>) => {
    const trigger = event.currentTarget;
    const rect = trigger.getBoundingClientRect();
    const bounds = trigger.closest(".pdf-pane")?.getBoundingClientRect();
    setLogAnchor({
      trigger,
      rect: { top: rect.top, right: rect.right, bottom: rect.bottom, left: rect.left, width: rect.width, height: rect.height },
      bounds: bounds ? { top: bounds.top, right: bounds.right, bottom: bounds.bottom, left: bounds.left, width: bounds.width, height: bounds.height } : undefined,
    });
  };

  return <div className="pdf-build-failure" role="alert" aria-labelledby="pdf-build-failure-title">
    <div className="pdf-build-failure-content">
      <CircleX size={20} strokeWidth={1.7} aria-hidden="true" />
      <h2 id="pdf-build-failure-title">{failure.title}</h2>
      <p>{failure.detail}</p>
      {failure.location && <code>{failure.location}</code>}
      <div className="pdf-build-failure-actions">
        <button type="button" className="primary-button compact" onClick={() => onRecover(failure.suggestedEngine)}>
          {failure.suggestedEngine ? `Switch to ${engineName(failure.suggestedEngine)} & Recompile` : "Recompile"}
        </button>
        <button type="button" className="secondary-button compact" onClick={openLog}>View Log</button>
      </div>
    </div>
    {logAnchor && createPortal(<BuildLogPopover anchor={logAnchor} log={failure.log} failed onClose={closeLog} />, document.body)}
  </div>;
}

function engineName(engine: NonNullable<BuildFailurePresentation["suggestedEngine"]>): string {
  if (engine === "xeLaTex") return "XeLaTeX";
  if (engine === "luaLaTex") return "LuaLaTeX";
  return "pdfLaTeX";
}

type PdfOutlineNode = {
  title: string;
  dest: string | unknown[] | null;
  items: PdfOutlineNode[];
};

async function extractBookmarkPages(document: PDFDocumentProxy): Promise<PdfBookmarkPage[]> {
  try {
    const tree = await document.getOutline() as PdfOutlineNode[] | null;
    const bookmarks: PdfBookmarkPage[] = [];
    const visit = async (items: PdfOutlineNode[]) => {
      for (const item of items) {
        let destination: unknown[] | null = null;
        if (typeof item.dest === "string") destination = await document.getDestination(item.dest) as unknown[] | null;
        else if (Array.isArray(item.dest)) destination = item.dest;
        const reference = destination?.[0];
        if (typeof reference === "number") bookmarks.push({ title: item.title, page: reference + 1 });
        else if (reference && typeof reference === "object") {
          const pageIndex = await document.getPageIndex(reference as Parameters<PDFDocumentProxy["getPageIndex"]>[0]);
          bookmarks.push({ title: item.title, page: pageIndex + 1 });
        }
        if (item.items.length > 0) await visit(item.items);
      }
    };
    if (tree) await visit(tree);
    return bookmarks;
  } catch {
    return [];
  }
}

function PdfPage({ document, pageNumber, zoom, query, target, scrollRoot, estimatedSize, onInverse }: {
  document: PDFDocumentProxy;
  pageNumber: number;
  zoom: number;
  query: string;
  target: SyncTeXPdfTarget | null;
  scrollRoot: RefObject<HTMLDivElement | null>;
  estimatedSize: { width: number; height: number };
  onInverse(page: number, x: number, yFromTop: number): void;
}) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const textLayer = useRef<HTMLDivElement>(null);
  const slot = useRef<HTMLDivElement>(null);
  const [nearViewport, setNearViewport] = useState(pageNumber <= 2);
  const [pdfPage, setPdfPage] = useState<PDFPageProxy | null>(null);
  const viewport = useMemo(() => pdfPage?.getViewport({ scale: zoom }) ?? null, [pdfPage, zoom]);

  useEffect(() => {
    const element = slot.current;
    if (!element || !scrollRoot.current || typeof IntersectionObserver === "undefined") {
      setNearViewport(true);
      return;
    }
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) setNearViewport(true);
    }, { root: scrollRoot.current, rootMargin: "700px 0px" });
    observer.observe(element);
    return () => observer.disconnect();
  }, [scrollRoot]);

  useEffect(() => {
    if (!nearViewport) return;
    let cancelled = false;
    document.getPage(pageNumber).then((loaded) => { if (!cancelled) setPdfPage(loaded); });
    return () => { cancelled = true; };
  }, [document, pageNumber, nearViewport]);

  useEffect(() => {
    if (!pdfPage || !viewport || !canvas.current) return;
    const ratio = window.devicePixelRatio || 1;
    const element = canvas.current;
    element.width = Math.floor(viewport.width * ratio);
    element.height = Math.floor(viewport.height * ratio);
    element.style.width = `${viewport.width}px`;
    element.style.height = `${viewport.height}px`;
    const context = element.getContext("2d");
    if (!context) return;
    const render = pdfPage.render({ canvasContext: context, viewport, transform: ratio === 1 ? undefined : [ratio, 0, 0, ratio, 0, 0] });
    return () => { render.cancel(); };
  }, [pdfPage, viewport]);

  useEffect(() => {
    if (!pdfPage || !viewport || !textLayer.current) return;
    const container = textLayer.current;
    container.replaceChildren();
    const layer = new pdfjs.TextLayer({ textContentSource: pdfPage.streamTextContent(), container, viewport });
    void layer.render().then(() => {
      const needle = query.trim().toLocaleLowerCase();
      if (!needle) return;
      for (const span of container.querySelectorAll<HTMLElement>("span")) {
        if (span.textContent?.toLocaleLowerCase().includes(needle)) span.classList.add("search-hit");
      }
    });
    return () => layer.cancel();
  }, [pdfPage, viewport, query]);

  return (
    <div ref={slot} className="pdf-page-slot" data-page={pageNumber} style={{ minHeight: estimatedSize.height }}>
      {viewport ? <div className="pdf-page-wrapper" style={{ width: viewport.width, height: viewport.height }} onDoubleClick={(event) => {
        event.preventDefault();
        const bounds = event.currentTarget.getBoundingClientRect();
        onInverse(pageNumber, (event.clientX - bounds.left) / zoom, (event.clientY - bounds.top) / zoom);
      }}>
        <canvas className="pdf-page" ref={canvas} aria-label={`PDF page ${pageNumber}`} />
        <div className="textLayer" ref={textLayer} aria-label={`Selectable text for PDF page ${pageNumber}`} />
        {target?.x != null && target.yFromTop != null && <span className="synctex-marker" style={{ left: target.x * zoom, top: target.yFromTop * zoom }} aria-hidden="true" />}
      </div> : <div className="pdf-page-placeholder" style={{ width: estimatedSize.width, height: estimatedSize.height }}><span>Page {pageNumber}</span></div>}
    </div>
  );
}
