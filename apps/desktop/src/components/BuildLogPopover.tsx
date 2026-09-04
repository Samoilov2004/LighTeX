import { useEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import { X } from "lucide-react";

export interface BuildLogAnchor {
  rect: Pick<DOMRect, "top" | "right" | "bottom" | "left" | "width" | "height">;
  bounds?: Pick<DOMRect, "top" | "right" | "bottom" | "left" | "width" | "height">;
  trigger: HTMLElement;
}

export function BuildLogPopover({ anchor, log, failed, onClose }: {
  anchor: BuildLogAnchor;
  log: string;
  failed: boolean;
  onClose(restoreFocus?: boolean): void;
}) {
  const panel = useRef<HTMLElement>(null);
  const [copied, setCopied] = useState(false);
  const position = useMemo(() => popoverPosition(anchor.rect, anchor.bounds), [anchor]);

  useEffect(() => {
    panel.current?.focus({ preventScroll: true });
    const pointer = (event: MouseEvent) => {
      const target = event.target as Node;
      if (panel.current?.contains(target) || anchor.trigger.contains(target)) return;
      onClose(false);
    };
    const keys = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.preventDefault();
      onClose(true);
    };
    const dismiss = () => onClose(false);
    const scroll = (event: Event) => {
      if (panel.current?.contains(event.target as Node)) return;
      onClose(false);
    };
    document.addEventListener("mousedown", pointer, true);
    window.addEventListener("keydown", keys);
    window.addEventListener("resize", dismiss);
    window.addEventListener("blur", dismiss);
    document.addEventListener("scroll", scroll, true);
    return () => {
      document.removeEventListener("mousedown", pointer, true);
      window.removeEventListener("keydown", keys);
      window.removeEventListener("resize", dismiss);
      window.removeEventListener("blur", dismiss);
      document.removeEventListener("scroll", scroll, true);
    };
  }, [anchor, onClose]);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(log);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1400);
    } catch {
      setCopied(false);
    }
  };

  const close = (restoreFocus = false) => onClose(restoreFocus);
  return <section
    ref={panel}
    className="build-log-popover"
    role="dialog"
    aria-modal="false"
    aria-labelledby="build-log-title"
    tabIndex={-1}
    style={position}
  >
    <header className="build-log-popover-header">
      <strong id="build-log-title">Build Log</strong>
      <span className={failed ? "failed" : "succeeded"}>{failed ? "Failed" : "Succeeded"}</span>
      <button type="button" className="build-log-copy" onClick={() => void copy()}>{copied ? "Copied" : "Copy"}</button>
      <button type="button" className="icon-button" onClick={() => close(true)} aria-label="Close Build Log"><X size={14} /></button>
    </header>
    <pre className="build-log-popover-content">{logLines(log || "No build output.")}</pre>
  </section>;
}

function popoverPosition(rect: BuildLogAnchor["rect"], bounds?: BuildLogAnchor["bounds"]): CSSProperties {
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;
  const boundaryLeft = Math.max(0, bounds?.left ?? 0);
  const boundaryRight = Math.min(viewportWidth, bounds?.right ?? viewportWidth);
  const width = Math.min(580, Math.max(280, boundaryRight - boundaryLeft - 24));
  const left = Math.max(boundaryLeft + 12, Math.min(boundaryRight - width - 12, rect.right - width + 36));
  const top = Math.min(rect.bottom + 5, viewportHeight - 194);
  const maxHeight = Math.max(180, viewportHeight - top - 34);
  const pointer = Math.max(24, Math.min(width - 24, rect.left + rect.width / 2 - left));
  return { left, top, width, maxHeight, "--build-log-pointer-x": `${pointer}px` } as CSSProperties;
}

function logLines(log: string) {
  let highlightNextLocation = false;
  const lines = log.split("\n");
  return lines.map((line, index) => {
    const error = /^!\s/.test(line) || highlightNextLocation;
    highlightNextLocation = /^!\s/.test(line);
    return <span className={error ? "error" : ""} key={`${index}:${line}`}>{line || " "}</span>;
  });
}
