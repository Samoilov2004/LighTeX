import { useEffect, useMemo, useRef, useState } from "react";
import { ChevronLeft, ChevronRight, Maximize2, Minus, Plus, Search, X } from "lucide-react";
import type { PDFDocumentProxy, PDFPageProxy } from "pdfjs-dist";
import type { SyncTeXPdfTarget } from "../types";
import { pdfjs } from "../pdf";

interface PdfPreviewProps {
  base64: string | null;
  target: SyncTeXPdfTarget | null;
  onInverse(page: number, x: number, yFromTop: number): void;
}

export function PdfPreview({ base64, target, onInverse }: PdfPreviewProps) {
  const [document, setDocument] = useState<PDFDocumentProxy | null>(null);
  const [page, setPage] = useState(1);
  const [zoom, setZoom] = useState(0.9);
  const [query, setQuery] = useState("");
  const [searchOpen, setSearchOpen] = useState(false);
  const [matches, setMatches] = useState<Array<{ page: number; count: number }>>([]);
  const scroll = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let active = true;
    setDocument(null);
    setPage(1);
    if (!base64) return;
    const binary = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
    const task = pdfjs.getDocument({ data: binary });
    task.promise.then((loaded) => {
      if (active) setDocument(loaded);
      else void loaded.destroy();
    });
    return () => {
      active = false;
      void task.destroy();
    };
  }, [base64]);

  useEffect(() => {
    if (target?.page) setPage(target.page);
  }, [target]);

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
  const nextMatch = (direction: -1 | 1) => {
    if (matches.length === 0) return;
    const current = matchPosition < 0 ? 0 : matchPosition;
    const next = (current + direction + matches.length) % matches.length;
    setPage(matches[next].page);
  };

  useEffect(() => {
    if (!target?.page || target.page !== page || target.yFromTop == null || !scroll.current) return;
    const frame = window.requestAnimationFrame(() => {
      const pageElement = scroll.current?.querySelector<HTMLElement>(".pdf-page-wrapper");
      if (!pageElement || !scroll.current) return;
      scroll.current.scrollTop = Math.max(0, pageElement.offsetTop + target.yFromTop! * zoom - scroll.current.clientHeight / 3);
    });
    return () => window.cancelAnimationFrame(frame);
  }, [target, page, zoom, document]);

  if (!base64) {
    return (
      <section className="pdf-pane empty-pdf" aria-label="PDF preview">
        <div className="empty-state compact">
          <span className="empty-state-title">PDF Preview</span>
          <span>Compile the main document to see the result.</span>
        </div>
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
        <button className="icon-button" onClick={() => setPage(Math.max(1, page - 1))} disabled={page <= 1} aria-label="Previous page"><ChevronLeft size={15} /></button>
        <label className="page-field">
          <span className="sr-only">Current page</span>
          <input
            value={page}
            inputMode="numeric"
            onChange={(event) => setPage(Math.max(1, Math.min(Number(event.target.value) || 1, document?.numPages ?? 1)))}
          />
          <span>of {document?.numPages ?? "—"}</span>
        </label>
        <button className="icon-button" onClick={() => setPage(Math.min(document?.numPages ?? 1, page + 1))} disabled={!document || page >= document.numPages} aria-label="Next page"><ChevronRight size={15} /></button>
        <button className="icon-button" onClick={() => setZoom(Math.max(0.35, zoom - 0.1))} aria-label="Zoom out"><Minus size={15} /></button>
        <span className="zoom-label">{Math.round(zoom * 100)}%</span>
        <button className="icon-button" onClick={() => setZoom(Math.min(2.5, zoom + 0.1))} aria-label="Zoom in"><Plus size={15} /></button>
        <button className="icon-button" onClick={() => setZoom(0.9)} aria-label="Fit page" title="Fit page"><Maximize2 size={15} /></button>
      </div>
      <div className="pdf-scroll" ref={scroll}>
        {document && <PdfPage key={`${page}-${zoom}`} document={document} pageNumber={page} zoom={zoom} query={query} target={target?.page === page ? target : null} onInverse={onInverse} />}
      </div>
    </section>
  );
}

function PdfPage({ document, pageNumber, zoom, query, target, onInverse }: {
  document: PDFDocumentProxy;
  pageNumber: number;
  zoom: number;
  query: string;
  target: SyncTeXPdfTarget | null;
  onInverse(page: number, x: number, yFromTop: number): void;
}) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const textLayer = useRef<HTMLDivElement>(null);
  const [pdfPage, setPdfPage] = useState<PDFPageProxy | null>(null);
  const viewport = useMemo(() => pdfPage?.getViewport({ scale: zoom }) ?? null, [pdfPage, zoom]);

  useEffect(() => {
    let cancelled = false;
    document.getPage(pageNumber).then((loaded) => { if (!cancelled) setPdfPage(loaded); });
    return () => { cancelled = true; };
  }, [document, pageNumber]);

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

  if (!viewport) return <div className="pdf-loading">Rendering…</div>;
  return (
    <div className="pdf-page-wrapper" style={{ width: viewport.width, height: viewport.height }} onDoubleClick={(event) => {
      event.preventDefault();
      const bounds = event.currentTarget.getBoundingClientRect();
      onInverse(pageNumber, (event.clientX - bounds.left) / zoom, (event.clientY - bounds.top) / zoom);
    }}>
      <canvas className="pdf-page" ref={canvas} aria-label={`PDF page ${pageNumber}`} />
      <div className="textLayer" ref={textLayer} aria-label={`Selectable text for PDF page ${pageNumber}`} />
      {target?.x != null && target.yFromTop != null && <span className="synctex-marker" style={{ left: target.x * zoom, top: target.yFromTop * zoom }} aria-hidden="true" />}
    </div>
  );
}
