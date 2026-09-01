import { useState } from "react";
import { ChevronDown, ChevronRight, Copy, ExternalLink, FilePlus2, FileText, Folder, FolderPlus, FolderUp, Pencil, Star, Trash2 } from "lucide-react";
import type { ProjectEntry } from "../types";

interface FileTreeProps {
  entries: ProjectEntry[];
  selectedPath: string | null;
  mainDocument: string | null;
  onOpen(path: string): void;
  onCreateFile(parent: string): void;
  onCreateFolder(parent: string): void;
  onUpload(parent: string): void;
  onRename(path: string): void;
  onDuplicate(path: string): void;
  onTrash(path: string): void;
  onSetMain(path: string): void;
  onMove(path: string, destinationFolder: string): void;
  onReveal(path: string): void;
  readOnly?: boolean;
}

export function FileTree(props: FileTreeProps) {
  return (
    <div className={`files-panel ${props.readOnly ? "read-only" : ""}`}>
      {!props.readOnly && <div className="sidebar-actions" aria-label="File actions">
        <button className="sidebar-action-button" onClick={() => props.onCreateFile("")} aria-label="Create file" title="Create file"><FilePlus2 size={14} /><span>File</span></button>
        <button className="sidebar-action-button" onClick={() => props.onCreateFolder("")} aria-label="Create folder" title="Create folder"><FolderPlus size={14} /><span>Folder</span></button>
        <button className="sidebar-action-button" onClick={() => props.onUpload("")} aria-label="Upload files or folder" title="Upload files or folder"><FolderUp size={14} /><span>Upload</span></button>
      </div>}
      <div className="file-tree" role="tree" aria-label="Project files">
        {props.entries.map((entry) => <FileRow key={entry.relativePath} entry={entry} depth={0} {...props} />)}
      </div>
    </div>
  );
}

function FileRow({ entry, depth, ...props }: { entry: ProjectEntry; depth: number } & FileTreeProps) {
  const [expanded, setExpanded] = useState(depth < 1);
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null);
  const open = () => entry.isDirectory ? setExpanded(!expanded) : props.onOpen(entry.relativePath);
  return (
    <>
      <div
        className={`file-row ${props.selectedPath === entry.relativePath ? "selected" : ""}`}
        style={{ paddingLeft: 7 + depth * 14 }}
        role="treeitem"
        aria-expanded={entry.isDirectory ? expanded : undefined}
        tabIndex={0}
        draggable={!props.readOnly && !entry.isDirectory}
        onDragStart={(event) => {
          event.dataTransfer.effectAllowed = "copyMove";
          event.dataTransfer.setData("application/x-lightex-file", entry.relativePath);
          event.dataTransfer.setData("application/x-lightex-entry", entry.relativePath);
        }}
        onDragOver={(event) => {
          if (!props.readOnly && entry.isDirectory && event.dataTransfer.types.includes("application/x-lightex-entry")) {
            event.preventDefault();
            event.dataTransfer.dropEffect = "move";
          }
        }}
        onDrop={(event) => {
          if (props.readOnly || !entry.isDirectory) return;
          const path = event.dataTransfer.getData("application/x-lightex-entry");
          if (path && path !== entry.relativePath && !entry.relativePath.startsWith(`${path}/`)) {
            event.preventDefault();
            props.onMove(path, entry.relativePath);
          }
        }}
        onDoubleClick={open}
        onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") open(); }}
        onContextMenu={(event) => { if (!props.readOnly) { event.preventDefault(); setMenu({ x: event.clientX, y: event.clientY }); } }}
      >
        {entry.isDirectory
          ? expanded ? <ChevronDown size={12} aria-hidden="true" /> : <ChevronRight size={12} aria-hidden="true" />
          : <span className="tree-chevron-placeholder" />}
        {entry.isDirectory ? <Folder size={14} aria-hidden="true" /> : <FileText size={14} aria-hidden="true" />}
        <button className="file-name-button" onClick={open} title={entry.relativePath}>{entry.name}</button>
        {entry.relativePath === props.mainDocument && <span className="main-label">MAIN</span>}
      </div>
      {entry.isDirectory && expanded && entry.children.map((child) => (
        <FileRow key={child.relativePath} entry={child} depth={depth + 1} {...props} />
      ))}
      {menu && !props.readOnly && (
        <div className="popover-menu context-menu" role="menu" style={{ left: menu.x, top: menu.y }} onMouseLeave={() => setMenu(null)}>
          {entry.isDirectory && <>
            <button role="menuitem" onClick={() => { props.onCreateFile(entry.relativePath); setMenu(null); }}><FilePlus2 size={14} />New File</button>
            <button role="menuitem" onClick={() => { props.onCreateFolder(entry.relativePath); setMenu(null); }}><FolderPlus size={14} />New Folder</button>
            <button role="menuitem" onClick={() => { props.onUpload(entry.relativePath); setMenu(null); }}><FolderUp size={14} />Upload Here</button>
            <div className="menu-separator" />
          </>}
          {!entry.isDirectory && entry.name.endsWith(".tex") && <button role="menuitem" onClick={() => { props.onSetMain(entry.relativePath); setMenu(null); }}><Star size={14} />Use as Main Document</button>}
          <button role="menuitem" onClick={() => { props.onRename(entry.relativePath); setMenu(null); }}><Pencil size={14} />Rename</button>
          <button role="menuitem" onClick={() => { props.onDuplicate(entry.relativePath); setMenu(null); }}><Copy size={14} />Duplicate</button>
          <button role="menuitem" onClick={() => { props.onReveal(entry.relativePath); setMenu(null); }}><ExternalLink size={14} />Reveal in {navigator.platform.toLowerCase().includes("mac") ? "Finder" : "Files"}</button>
          <div className="menu-separator" />
          <button role="menuitem" className="destructive" onClick={() => { props.onTrash(entry.relativePath); setMenu(null); }}><Trash2 size={14} />Move to Trash</button>
        </div>
      )}
    </>
  );
}
