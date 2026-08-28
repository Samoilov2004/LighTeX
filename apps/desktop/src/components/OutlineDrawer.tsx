import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { ChevronDown, ListTree, Plus } from "lucide-react";
import { OutlinePanel } from "./OutlinePanel";

const COLLAPSED_HEIGHT = 30;
const COLLAPSE_THRESHOLD = 72;
const MIN_OPEN_HEIGHT = 112;
const DEFAULT_HEIGHT = 180;

interface OutlineDrawerProps {
  expanded: boolean;
  height: number;
  onCommit(expanded: boolean, height: number): void;
}

export function OutlineDrawer({ expanded, height, onCommit }: OutlineDrawerProps) {
  const drawerRef = useRef<HTMLElement>(null);
  const suppressClick = useRef(false);
  const [maximumHeight, setMaximumHeight] = useState(() => maximumFor(window.innerHeight));
  const [draftExpanded, setDraftExpanded] = useState(expanded);
  const [draftHeight, setDraftHeight] = useState(() => clampHeight(height, maximumHeight));

  useEffect(() => {
    setDraftExpanded(expanded);
    setDraftHeight(clampHeight(height, maximumHeight));
  }, [expanded, height, maximumHeight]);

  useLayoutEffect(() => {
    const parent = drawerRef.current?.parentElement;
    const updateMaximum = () => {
      const available = parent?.clientHeight || window.innerHeight;
      setMaximumHeight(maximumFor(available));
    };
    updateMaximum();
    window.addEventListener("resize", updateMaximum);
    const observer = typeof ResizeObserver === "undefined" || !parent ? null : new ResizeObserver(updateMaximum);
    if (observer && parent) observer.observe(parent);
    return () => {
      observer?.disconnect();
      window.removeEventListener("resize", updateMaximum);
    };
  }, []);

  const toggle = () => {
    if (suppressClick.current) {
      suppressClick.current = false;
      return;
    }
    const nextExpanded = !expanded;
    const nextHeight = clampHeight(height || DEFAULT_HEIGHT, maximumHeight);
    setDraftExpanded(nextExpanded);
    setDraftHeight(nextHeight);
    onCommit(nextExpanded, nextHeight);
  };

  const startDrag = (event: React.PointerEvent<HTMLElement>, fromCollapsed: boolean) => {
    if (event.button !== 0) return;
    event.currentTarget.setPointerCapture?.(event.pointerId);
    const originY = event.clientY;
    const startingHeight = fromCollapsed ? COLLAPSED_HEIGHT : draftHeight;
    let candidate = startingHeight;
    let moved = false;

    const move = (next: PointerEvent) => {
      candidate = startingHeight + originY - next.clientY;
      moved ||= Math.abs(next.clientY - originY) >= 4;
      if (!moved) return;
      setDraftExpanded(candidate >= COLLAPSE_THRESHOLD);
      setDraftHeight(Math.min(maximumHeight, Math.max(COLLAPSED_HEIGHT, candidate)));
    };
    const finish = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", finish);
      window.removeEventListener("pointercancel", finish);
      suppressClick.current = moved;
      if (moved) window.setTimeout(() => { suppressClick.current = false; }, 0);
      if (!moved) return;
      if (candidate < COLLAPSE_THRESHOLD) {
        setDraftExpanded(false);
        setDraftHeight(clampHeight(height || DEFAULT_HEIGHT, maximumHeight));
        onCommit(false, clampHeight(height || DEFAULT_HEIGHT, maximumHeight));
      } else {
        const nextHeight = clampHeight(candidate, maximumHeight);
        setDraftExpanded(true);
        setDraftHeight(nextHeight);
        onCommit(true, nextHeight);
      }
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", finish);
    window.addEventListener("pointercancel", finish);
  };

  const resizeWithKeyboard = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onCommit(false, draftHeight);
      return;
    }
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return;
    event.preventDefault();
    const step = event.shiftKey ? 48 : 16;
    const candidate = draftHeight + (event.key === "ArrowUp" ? step : -step);
    if (candidate < MIN_OPEN_HEIGHT) {
      setDraftExpanded(false);
      onCommit(false, draftHeight);
      return;
    }
    const nextHeight = clampHeight(candidate, maximumHeight);
    setDraftHeight(nextHeight);
    onCommit(true, nextHeight);
  };

  const renderedHeight = draftExpanded ? draftHeight : COLLAPSED_HEIGHT;
  return (
    <section
      ref={drawerRef}
      className={`outline-drawer ${draftExpanded ? "expanded" : "collapsed"}`}
      style={{ height: renderedHeight }}
      aria-label="Table of Contents"
    >
      {draftExpanded && (
        <div
          className="outline-drawer-resize"
          role="separator"
          aria-label="Resize Table of Contents"
          aria-orientation="horizontal"
          aria-valuemin={MIN_OPEN_HEIGHT}
          aria-valuemax={maximumHeight}
          aria-valuenow={Math.round(draftHeight)}
          tabIndex={0}
          onPointerDown={(event) => startDrag(event, false)}
          onKeyDown={resizeWithKeyboard}
        />
      )}
      <button
        type="button"
        className="outline-drawer-header"
        aria-expanded={draftExpanded}
        aria-controls="project-table-of-contents"
        onPointerDown={draftExpanded ? undefined : (event) => startDrag(event, true)}
        onClick={toggle}
      >
        <ListTree size={13} aria-hidden="true" />
        <span>Table of Contents</span>
        {draftExpanded ? <ChevronDown size={14} aria-hidden="true" /> : <Plus size={14} aria-hidden="true" />}
      </button>
      {draftExpanded && <div id="project-table-of-contents" className="outline-drawer-content"><OutlinePanel /></div>}
    </section>
  );
}

function maximumFor(availableHeight: number) {
  return Math.max(MIN_OPEN_HEIGHT, Math.floor(availableHeight * 0.45));
}

function clampHeight(height: number, maximumHeight: number) {
  return Math.max(MIN_OPEN_HEIGHT, Math.min(maximumHeight, Math.round(height || DEFAULT_HEIGHT)));
}
