import { useEffect, useRef, useState } from "react";
import { DndContext, DragOverlay, PointerSensor, closestCenter, useSensor, useSensors, type DragEndEvent, type DragStartEvent } from "@dnd-kit/core";
import { SortableContext, horizontalListSortingStrategy, useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { ChevronDown, FileText, X } from "lucide-react";
import type { EditorDocument } from "../types";

interface EditorTabsProps {
  tabs: string[];
  selectedPath: string | null;
  documents: Record<string, EditorDocument>;
  onSelect(path: string): void;
  onClose(path: string): void;
  onReorder(active: string, over: string): void;
  onMove(path: string, direction: -1 | 1): void;
  onFileDrop(path: string): void;
}

export function EditorTabs(props: EditorTabsProps) {
  const [activeDrag, setActiveDrag] = useState<string | null>(null);
  const [overflowOpen, setOverflowOpen] = useState(false);
  const [fileDropActive, setFileDropActive] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }));
  const dragEnd = (event: DragEndEvent) => {
    setActiveDrag(null);
    if (event.over && event.active.id !== event.over.id) props.onReorder(String(event.active.id), String(event.over.id));
  };
  const externalDrop = (event: React.DragEvent) => {
    event.preventDefault();
    setFileDropActive(false);
    const path = event.dataTransfer.getData("application/x-lightex-file");
    if (path) props.onFileDrop(path);
  };
  useEffect(() => {
    const selected = Array.from(scrollRef.current?.querySelectorAll<HTMLElement>("[data-tab-path]") ?? [])
      .find((element) => element.dataset.tabPath === props.selectedPath);
    selected?.scrollIntoView({ block: "nearest", inline: "nearest", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
  }, [props.selectedPath, props.tabs.length]);
  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCenter}
      onDragStart={(event: DragStartEvent) => setActiveDrag(String(event.active.id))}
      onDragCancel={() => setActiveDrag(null)}
      onDragEnd={dragEnd}
    >
      <div
        className={`editor-tabs ${fileDropActive ? "file-drop-active" : ""}`}
        role="tablist"
        aria-label="Open files"
        onDragOver={(event) => {
          if (event.dataTransfer.types.includes("application/x-lightex-file")) {
            event.preventDefault();
            event.dataTransfer.dropEffect = "copy";
            setFileDropActive(true);
          }
        }}
        onDragLeave={(event) => {
          if (!event.currentTarget.contains(event.relatedTarget as Node)) setFileDropActive(false);
        }}
        onDrop={externalDrop}
      >
        <div className="tab-scroll" ref={scrollRef}>
          <SortableContext items={props.tabs} strategy={horizontalListSortingStrategy}>
            {props.tabs.map((path) => (
              <EditorTab
                key={path}
                path={path}
                document={props.documents[path]}
                active={path === props.selectedPath}
                onSelect={props.onSelect}
                onClose={props.onClose}
                onMove={props.onMove}
              />
            ))}
          </SortableContext>
        </div>
        {props.tabs.length > 0 && (
          <div className="tab-overflow">
            <button className="icon-button" onClick={() => setOverflowOpen(!overflowOpen)} aria-label="All open files" aria-expanded={overflowOpen}><ChevronDown size={14} /></button>
            {overflowOpen && (
              <div className="popover-menu tab-menu" role="menu">
                {props.tabs.map((path) => (
                  <button key={path} role="menuitem" onClick={() => { props.onSelect(path); setOverflowOpen(false); }}>
                    <FileText size={14} aria-hidden="true" />
                    <span>{fileName(path)}</span>
                    {props.documents[path]?.dirty && <span className="dirty-dot" aria-label="Unsaved" />}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
        {fileDropActive && <div className="file-drop-badge">+ Open as tab</div>}
      </div>
      <DragOverlay dropAnimation={null}>
        {activeDrag && <TabSurface path={activeDrag} document={props.documents[activeDrag]} active overlay />}
      </DragOverlay>
    </DndContext>
  );
}

function EditorTab({ path, document, active, onSelect, onClose, onMove }: {
  path: string;
  document?: EditorDocument;
  active: boolean;
  onSelect(path: string): void;
  onClose(path: string): void;
  onMove(path: string, direction: -1 | 1): void;
}) {
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null);
  const { listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: path });
  return (
    <div
      ref={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0 : 1 }}
      className="tab-wrapper"
      data-tab-path={path}
      onContextMenu={(event) => { event.preventDefault(); setMenu({ x: event.clientX, y: event.clientY }); }}
    >
      <div {...listeners}>
        <TabSurface path={path} document={document} active={active} onSelect={onSelect} onClose={onClose} />
      </div>
      {menu && (
        <div className="popover-menu context-menu" role="menu" style={{ left: menu.x, top: menu.y }} onMouseLeave={() => setMenu(null)}>
          <button role="menuitem" onClick={() => { onMove(path, -1); setMenu(null); }}>Move Tab Left</button>
          <button role="menuitem" onClick={() => { onMove(path, 1); setMenu(null); }}>Move Tab Right</button>
          <div className="menu-separator" />
          <button role="menuitem" onClick={() => { onClose(path); setMenu(null); }}>Close</button>
        </div>
      )}
    </div>
  );
}

function TabSurface({ path, document, active, overlay = false, onSelect, onClose }: {
  path: string;
  document?: EditorDocument;
  active: boolean;
  overlay?: boolean;
  onSelect?(path: string): void;
  onClose?(path: string): void;
}) {
  return (
    <div
      className={`editor-tab ${active ? "active" : ""} ${overlay ? "drag-overlay" : ""}`}
      role="tab"
      aria-selected={active}
      tabIndex={active ? 0 : -1}
      onClick={() => onSelect?.(path)}
      onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") onSelect?.(path); }}
    >
      <FileText size={14} aria-hidden="true" />
      <span className="tab-title">{fileName(path)}</span>
      {document?.dirty && <span className="dirty-dot" aria-label="Unsaved changes" />}
      {!overlay && (
        <button
          className="tab-close"
          onPointerDown={(event) => event.stopPropagation()}
          onClick={(event) => { event.stopPropagation(); onClose?.(path); }}
          aria-label={`Close ${fileName(path)}`}
        ><X size={13} /></button>
      )}
    </div>
  );
}

function fileName(path: string) {
  return path.split("/").pop() ?? path;
}
