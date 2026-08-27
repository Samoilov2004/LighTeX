import { useEffect, useMemo, useState } from "react";
import { ArrowLeft, BookOpen, Braces, Bug, FileText, Folder, ListTree, PanelLeft, PanelRight, Play, Search, Settings, Sparkles, Square } from "lucide-react";
import { ask, open, save } from "@tauri-apps/plugin-dialog";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { revealItemInDir } from "@tauri-apps/plugin-opener";
import { api, isDesktop } from "../api";
import { useAppStore, type SidebarMode } from "../store";
import { EditorTabs } from "./EditorTabs";
import { FileTree } from "./FileTree";
import { InsertShelf } from "./InsertShelf";
import { OutlinePanel } from "./OutlinePanel";
import { PdfPreview } from "./PdfPreview";
import { ProblemsPanel } from "./ProblemsPanel";
import { SearchPanel } from "./SearchPanel";
import { SourceEditor } from "./SourceEditor";
import type { SyncTeXPdfTarget } from "../types";
import { useModalFocus } from "../useModalFocus";

export function Workspace() {
  const state = useAppStore();
  const [sidebarWidth, setSidebarWidth] = useState(230);
  const [editorFraction, setEditorFraction] = useState(0.51);
  const [pdfTarget, setPdfTarget] = useState<SyncTeXPdfTarget | null>(null);
  const [uploadTarget, setUploadTarget] = useState<string | null>(null);
  const [nameRequest, setNameRequest] = useState<{ kind: "file" | "folder" | "rename"; parent: string; path?: string; initial: string } | null>(null);
  const uploadDialog = useModalFocus<HTMLElement>(() => setUploadTarget(null), uploadTarget !== null);
  const selectedDocument = state.selectedPath ? state.documents[state.selectedPath] : null;
  const syncExecutable = state.activeToolchain.synctex?.path;

  useEffect(() => {
    const keys = (event: KeyboardEvent) => {
      const command = navigator.platform.toLowerCase().includes("mac") ? event.metaKey : event.ctrlKey;
      if (!command) return;
      if (event.key.toLowerCase() === "s") { event.preventDefault(); void state.saveAll(); }
      if (event.key.toLowerCase() === "b") { event.preventDefault(); void state.build(); }
      if (event.key.toLowerCase() === "p") { event.preventDefault(); state.setSidebarMode("files"); useAppStore.setState({ sidebarVisible: true }); }
      if (event.shiftKey && event.key.toLowerCase() === "f") { event.preventDefault(); state.setSidebarMode("search"); useAppStore.setState({ sidebarVisible: true }); }
      if (event.key === ",") { event.preventDefault(); useAppStore.setState({ settingsOpen: true }); }
    };
    window.addEventListener("keydown", keys);
    return () => window.removeEventListener("keydown", keys);
  }, [state.project?.id, state.tabs, state.buildState]);
  useEffect(() => {
    const menu = (event: Event) => {
      const action = (event as CustomEvent<string>).detail;
      if (action === "save") void useAppStore.getState().saveAll();
      if (action === "build") void useAppStore.getState().build();
      if (action === "project-search") {
        useAppStore.getState().setSidebarMode("search");
        useAppStore.setState({ sidebarVisible: true });
      }
      if (action === "insert-shelf") useAppStore.setState({ insertShelfOpen: !useAppStore.getState().insertShelfOpen });
    };
    window.addEventListener("lightex:menu-action", menu);
    return () => window.removeEventListener("lightex:menu-action", menu);
  }, []);

  useEffect(() => {
    const sync = async (event: Event) => {
      const detail = (event as CustomEvent<{ path: string; line: number; column: number }>).detail;
      if (!state.project || !syncExecutable || !state.buildResult?.previewPdfPath) return;
      const target = await api.synctexForward(state.project.id, syncExecutable, detail.path, detail.line, detail.column, state.buildResult.previewPdfPath);
      if (target) setPdfTarget(target);
    };
    window.addEventListener("lightex:source-sync", sync);
    return () => window.removeEventListener("lightex:source-sync", sync);
  }, [state.project?.id, syncExecutable, state.buildResult?.previewPdfPath]);

  useEffect(() => {
    if (!isDesktop() || !state.project) return;
    let unlisten: (() => void) | undefined;
    void getCurrentWindow().onDragDropEvent((event) => {
      if (event.payload.type !== "drop" || event.payload.paths.length === 0) return;
      void api.uploadEntries(state.project!.id, "", event.payload.paths)
        .then(async (skipped) => {
          await state.refreshProject();
          if (skipped.length > 0) state.setError(`Skipped existing files: ${skipped.join(", ")}`);
        })
        .catch((error) => state.setError(String(error)));
    }).then((value) => { unlisten = value; });
    return () => unlisten?.();
  }, [state.project?.id]);

  const createFile = (parent: string) => setNameRequest({ kind: "file", parent, initial: "untitled.tex" });
  const createFolder = (parent: string) => setNameRequest({ kind: "folder", parent, initial: "figures" });
  const upload = (parent: string) => setUploadTarget(parent);
  const chooseUpload = async (parent: string, directory: boolean) => {
    if (!state.project) return;
    const selected = await open({ multiple: !directory, directory, title: directory ? "Upload Folder" : "Upload Files" });
    const sources = typeof selected === "string" ? [selected] : selected ?? [];
    if (sources.length === 0) return;
    try {
      const skipped = await api.uploadEntries(state.project.id, parent, sources);
      await state.refreshProject();
      if (skipped.length > 0) state.setError(`Skipped existing files: ${skipped.join(", ")}`);
    } catch (error) { state.setError(String(error)); }
  };
  const rename = (path: string) => setNameRequest({ kind: "rename", parent: path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "", path, initial: path.split("/").pop() ?? path });
  const commitName = async (name: string) => {
    if (!state.project || !nameRequest) return;
    const request = nameRequest;
    setNameRequest(null);
    try {
      if (request.kind === "file") {
        const path = await api.createFile(state.project.id, request.parent, name);
        await state.refreshProject();
        await state.openDocument(path);
      } else if (request.kind === "folder") {
        await api.createFolder(state.project.id, request.parent, name);
        await state.refreshProject();
      } else if (request.path) {
        const renamed = await api.renameEntry(state.project.id, request.path, name);
        state.remapEntryPaths(request.path, renamed);
        await state.refreshProject();
      }
    } catch (error) { state.setError(String(error)); }
  };
  const duplicate = async (path: string) => {
    if (!state.project) return;
    try { await api.duplicateEntry(state.project.id, path); await state.refreshProject(); }
    catch (error) { state.setError(String(error)); }
  };
  const move = async (path: string, destinationFolder: string) => {
    if (!state.project) return;
    try {
      const moved = await api.moveEntry(state.project.id, path, destinationFolder);
      state.remapEntryPaths(path, moved);
      await state.refreshProject();
    } catch (error) { state.setError(String(error)); }
  };
  const trash = async (path: string) => {
    if (!state.project) return;
    const confirmed = await ask(`Move ${path} to Trash?`, { title: "Move to Trash", kind: "warning", okLabel: "Move to Trash", cancelLabel: "Cancel" });
    if (!confirmed) return;
    try { await api.trashEntry(state.project.id, path); await state.refreshProject(); }
    catch (error) { state.setError(String(error)); }
  };
  const saveConflictCopy = async (path: string) => {
    const document = state.documents[path];
    if (!document) return;
    const destination = await save({
      title: document.externalChange === "deleted" ? "Save Deleted Document As" : "Save Local Version As",
      defaultPath: `${path.split("/").pop()?.replace(/\.tex$/i, "") ?? "document"} copy.tex`,
      filters: [{ name: "LaTeX document", extensions: ["tex"] }],
    });
    if (destination) await state.resolveConflict(path, "copy", destination);
  };

  const editorStyle = useMemo(() => ({
    gridTemplateColumns: state.pdfVisible ? `${editorFraction * 100}% 5px 1fr` : "1fr",
  }), [editorFraction, state.pdfVisible]);

  return (
    <main className="workspace">
      <header className="project-toolbar" data-tauri-drag-region>
        <button className="icon-button project-back" onClick={() => void state.leaveProject()} aria-label="Back to Projects" title="Projects"><ArrowLeft size={16} /></button>
        <button className="icon-button" onClick={() => useAppStore.setState({ sidebarVisible: !state.sidebarVisible })} aria-label="Toggle project sidebar" aria-pressed={state.sidebarVisible}><PanelLeft size={16} /></button>
        <div className="toolbar-spacer" data-tauri-drag-region />
        <button className="icon-button" onClick={() => useAppStore.setState({ insertShelfOpen: !state.insertShelfOpen })} aria-label="Toggle Insert Shelf" aria-pressed={state.insertShelfOpen} title="Insert Shelf"><Sparkles size={16} /></button>
        <button className="icon-button" onClick={() => useAppStore.setState({ problemsOpen: !state.problemsOpen })} aria-label="Toggle Problems" aria-pressed={state.problemsOpen} title="Problems"><Bug size={16} /></button>
        <label className="auto-compile"><input type="checkbox" checked={state.config.automaticBuilds} onChange={(event) => state.updateConfig({ automaticBuilds: event.target.checked })} /><span>Auto Compile</span></label>
        <button className="primary-button compact" onClick={() => void (state.buildState === "building" ? state.cancelBuild() : state.build())}>{state.buildState === "building" ? <Square size={11} fill="currentColor" /> : <Play size={13} fill="currentColor" />}{state.buildState === "building" ? "Cancel" : "Recompile"}</button>
        <button className="icon-button" onClick={() => useAppStore.setState({ pdfVisible: !state.pdfVisible })} aria-label="Toggle PDF preview" aria-pressed={state.pdfVisible}><PanelRight size={16} /></button>
        <button className="icon-button" onClick={() => useAppStore.setState({ settingsOpen: true })} aria-label="Open Settings"><Settings size={16} /></button>
      </header>
      <div className="workspace-main" style={{ gridTemplateColumns: state.sidebarVisible ? `${sidebarWidth}px 5px 1fr` : "1fr" }}>
        {state.sidebarVisible && <>
          <aside className="project-sidebar">
            <div className="sidebar-mode-tabs" role="tablist" aria-label="Project navigation">
              <SidebarTab mode="files" current={state.sidebarMode} icon={<Folder size={14} />} label="Files" />
              <SidebarTab mode="search" current={state.sidebarMode} icon={<Search size={14} />} label="Search" />
              <SidebarTab mode="outline" current={state.sidebarMode} icon={<ListTree size={14} />} label="Outline" />
            </div>
            <div className="sidebar-content">
              {state.sidebarMode === "files" && <FileTree entries={state.entries} selectedPath={state.selectedPath} mainDocument={state.mainDocument} onOpen={(path) => void state.openDocument(path)} onCreateFile={createFile} onCreateFolder={createFolder} onUpload={upload} onRename={rename} onDuplicate={duplicate} onTrash={trash} onMove={move} onReveal={(path) => { if (state.project) void revealItemInDir(`${state.project.rootPath}/${path}`); }} onSetMain={(path) => void state.setMainDocument(path)} />}
              {state.sidebarMode === "search" && <SearchPanel />}
              {state.sidebarMode === "outline" && <OutlinePanel />}
            </div>
          </aside>
          <ResizeDivider axis="x" onMove={(delta) => setSidebarWidth((width) => Math.max(185, Math.min(330, width + delta)))} />
        </>}
        <div className="document-area">
          <EditorTabs tabs={state.tabs} selectedPath={state.selectedPath} documents={state.documents} onSelect={state.selectDocument} onClose={(path) => void state.closeDocument(path)} onReorder={state.reorderTabs} onMove={state.moveTab} onFileDrop={(path) => void state.openDocument(path)} />
          {selectedDocument && selectedDocument.externalChange !== "none" && <div className="conflict-banner" role="alert">
            <span>{selectedDocument.externalChange === "deleted" ? `${selectedDocument.relativePath} was deleted outside LighTex.` : `${selectedDocument.relativePath} changed outside LighTex.`}</span>
            {selectedDocument.externalChange === "modified" && <button onClick={() => state.resolveConflict(selectedDocument.relativePath, "reload")}>Reload</button>}
            {selectedDocument.externalChange === "modified" && <button onClick={() => state.resolveConflict(selectedDocument.relativePath, "keep")}>Keep Mine</button>}
            <button onClick={() => void saveConflictCopy(selectedDocument.relativePath)}>{selectedDocument.externalChange === "deleted" ? "Save As" : "Save Copy"}</button>
            {selectedDocument.externalChange === "deleted" && <button onClick={() => void state.closeDocument(selectedDocument.relativePath)}>Close</button>}
          </div>}
          <div className="editor-pdf-split" style={editorStyle}>
            <section className="source-pane" aria-label="Source editor">
              {selectedDocument ? <SourceEditor key={selectedDocument.relativePath} path={selectedDocument.relativePath} value={selectedDocument.text} config={state.config} completion={state.completion} onChange={(text) => state.updateText(selectedDocument.relativePath, text)} /> : <div className="empty-state"><FileText size={25} /><span className="empty-state-title">No file open</span><span>Choose a text file from the project sidebar.</span></div>}
            </section>
            {state.pdfVisible && <>
              <ResizeDivider axis="x" onMove={(delta) => setEditorFraction((fraction) => Math.max(0.3, Math.min(0.7, fraction + delta / Math.max(700, window.innerWidth - sidebarWidth))))} />
              <PdfPreview base64={state.pdfBase64} target={pdfTarget} onInverse={async (page, x, y) => {
                if (!state.project || !syncExecutable || !state.buildResult?.previewPdfPath) return;
                const target = await api.synctexInverse(state.project.id, syncExecutable, state.buildResult.previewPdfPath, page, x, y);
                if (target) await state.openDocument(target.relativePath, target.line);
              }} />
            </>}
          </div>
          {state.insertShelfOpen && <InsertShelf onClose={() => useAppStore.setState({ insertShelfOpen: false })} />}
          {state.problemsOpen && <ProblemsPanel />}
        </div>
      </div>
      <footer className="status-bar">
        <span className={`status-dot ${state.buildState}`} />
        <span>{state.statusMessage}</span>
        <div className="toolbar-spacer" />
        <span>{state.selectedPath ?? "No file"}</span>
        <span>UTF-8</span>
      </footer>
      {uploadTarget !== null && <div className="modal-layer" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setUploadTarget(null); }}><section ref={uploadDialog} className="native-dialog upload-dialog" role="dialog" aria-modal="true" aria-labelledby="upload-title"><h2 id="upload-title">Add to Project</h2><p>Choose files or copy an entire folder into {uploadTarget || "the project root"}. Existing items are never overwritten.</p><div className="dialog-actions"><button className="secondary-button" onClick={() => setUploadTarget(null)}>Cancel</button><button className="secondary-button" onClick={() => { const target = uploadTarget; setUploadTarget(null); void chooseUpload(target, true); }}>Choose Folder…</button><button className="primary-button" onClick={() => { const target = uploadTarget; setUploadTarget(null); void chooseUpload(target, false); }}>Choose Files…</button></div></section></div>}
      {nameRequest && <NameDialog request={nameRequest} onClose={() => setNameRequest(null)} onSubmit={commitName} />}
    </main>
  );
}

function NameDialog({ request, onClose, onSubmit }: { request: { kind: "file" | "folder" | "rename"; initial: string }; onClose(): void; onSubmit(value: string): Promise<void> }) {
  const [value, setValue] = useState(request.initial);
  const title = request.kind === "file" ? "Create File" : request.kind === "folder" ? "Create Folder" : "Rename Item";
  const dialog = useModalFocus<HTMLFormElement>(onClose);
  return <div className="modal-layer" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><form ref={dialog} className="native-dialog name-dialog" role="dialog" aria-modal="true" aria-labelledby="name-dialog-title" onSubmit={(event) => { event.preventDefault(); if (value.trim()) void onSubmit(value.trim()); }}><h2 id="name-dialog-title">{title}</h2><label><span>Name</span><input value={value} onChange={(event) => setValue(event.target.value)} autoFocus onFocus={(event) => { const dot = value.lastIndexOf("."); event.currentTarget.setSelectionRange(0, dot > 0 ? dot : value.length); }} /></label><div className="dialog-actions"><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button className="primary-button" disabled={!value.trim()}>{request.kind === "rename" ? "Rename" : "Create"}</button></div></form></div>;
}

function SidebarTab({ mode, current, icon, label }: { mode: SidebarMode; current: SidebarMode; icon: React.ReactNode; label: string }) {
  const set = useAppStore((state) => state.setSidebarMode);
  return <button role="tab" aria-selected={mode === current} className={mode === current ? "selected" : ""} onClick={() => set(mode)}>{icon}<span>{label}</span></button>;
}

function ResizeDivider({ axis, onMove }: { axis: "x" | "y"; onMove(delta: number): void }) {
  return <div className={`resize-divider ${axis}`} role="separator" aria-orientation={axis === "x" ? "vertical" : "horizontal"} tabIndex={0} onPointerDown={(event) => {
    event.currentTarget.setPointerCapture(event.pointerId);
    let previous = axis === "x" ? event.clientX : event.clientY;
    const move = (next: PointerEvent) => {
      const coordinate = axis === "x" ? next.clientX : next.clientY;
      onMove(coordinate - previous);
      previous = coordinate;
    };
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  }} onKeyDown={(event) => {
    if (axis === "x" && event.key === "ArrowLeft") onMove(-8);
    if (axis === "x" && event.key === "ArrowRight") onMove(8);
  }} />;
}
