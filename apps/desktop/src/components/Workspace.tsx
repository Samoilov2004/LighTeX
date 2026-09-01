import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ArchiveRestore, BookmarkPlus, CircleX, FileText, Folder, History, PanelLeft, PanelRight, Search, Settings, Sigma } from "lucide-react";
import { ask, open, save } from "@tauri-apps/plugin-dialog";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { revealItemInDir } from "@tauri-apps/plugin-opener";
import { api, isDesktop } from "../api";
import { useAppStore, type SidebarMode } from "../store";
import { BackToProjectsControl } from "./BackToProjectsControl";
import { BuildControls } from "./BuildControls";
import { EditorQuickControls } from "./EditorQuickControls";
import { EditorTabs } from "./EditorTabs";
import { FileTree } from "./FileTree";
import { InsertShelf } from "./InsertShelf";
import { OutlineDrawer } from "./OutlineDrawer";
import { outlineItemKey } from "../outlinePages";
import { PdfPreview } from "./PdfPreview";
import { SearchPanel } from "./SearchPanel";
import { SourceEditor, type SourceEditorHandle } from "./SourceEditor";
import { WindowDragRegion } from "./WindowDragRegion";
import type { ProjectVersionSummary, SyncTeXPdfTarget } from "../types";
import { useModalFocus } from "../useModalFocus";
import { RestoreVersionDialog, SaveVersionDialog, VersionsPanel } from "./VersionsPanel";
import { buildErrorEntryPaths } from "../buildDiagnostics";

export function Workspace() {
  const state = useAppStore();
  const [sidebarWidth, setSidebarWidth] = useState(230);
  const [editorFraction, setEditorFraction] = useState(0.51);
  const [pdfTarget, setPdfTarget] = useState<SyncTeXPdfTarget | null>(null);
  const [canUndo, setCanUndo] = useState(false);
  const [uploadTarget, setUploadTarget] = useState<string | null>(null);
  const [nameRequest, setNameRequest] = useState<{ kind: "file" | "folder" | "rename"; parent: string; path?: string; initial: string } | null>(null);
  const [saveVersionOpen, setSaveVersionOpen] = useState(false);
  const [restoreVersion, setRestoreVersion] = useState<ProjectVersionSummary | null>(null);
  const uploadDialog = useModalFocus<HTMLElement>(() => setUploadTarget(null), uploadTarget !== null);
  const sourceEditorRef = useRef<SourceEditorHandle>(null);
  const preview = state.versionPreview;
  const displayedDocuments = preview?.documents ?? state.documents;
  const displayedTabs = preview?.tabs ?? state.tabs;
  const displayedSelectedPath = preview?.selectedPath ?? state.selectedPath;
  const displayedOutline = preview?.outline ?? state.outline;
  const displayedPdf = preview?.pdfBase64 ?? state.pdfBase64;
  const selectedDocument = displayedSelectedPath ? displayedDocuments[displayedSelectedPath] : null;
  const inlineDiagnostics = useMemo(() => !preview && selectedDocument
    ? (state.buildResult?.diagnostics ?? []).filter((group) => group.primary.relativePath === selectedDocument.relativePath)
    : [], [preview, selectedDocument?.relativePath, state.buildResult]);
  const buildErrorPaths = useMemo<ReadonlySet<string>>(
    () => preview ? new Set<string>() : buildErrorEntryPaths(state.buildResult),
    [preview, state.buildResult],
  );
  const syncExecutable = state.activeToolchain.synctex?.path;
  const acceptPdfOutlinePages = useCallback((pages: Record<string, number>) => {
    useAppStore.setState((current) => current.versionPreview
      ? { versionPreview: { ...current.versionPreview, outlinePages: { ...current.versionPreview.outlinePages, ...pages } } }
      : { outlinePages: { ...current.outlinePages, ...pages } });
  }, []);

  useEffect(() => setPdfTarget(null), [preview?.version.id, displayedPdf]);

  useEffect(() => {
    const openSaveVersion = () => { if (!useAppStore.getState().versionPreview) setSaveVersionOpen(true); };
    window.addEventListener("lightex:save-version", openSaveVersion);
    return () => window.removeEventListener("lightex:save-version", openSaveVersion);
  }, []);

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
      if (action === "save-version" && !useAppStore.getState().versionPreview) setSaveVersionOpen(true);
      if (action === "show-versions") void useAppStore.getState().toggleVersions();
    };
    window.addEventListener("lightex:menu-action", menu);
    return () => window.removeEventListener("lightex:menu-action", menu);
  }, []);

  useEffect(() => {
    const sync = async (event: Event) => {
      const detail = (event as CustomEvent<{ path: string; line: number; column: number }>).detail;
      if (!state.project || !syncExecutable) return;
      const target = state.versionPreview
        ? await api.synctexProjectVersionForward(state.project.id, state.versionPreview.version.id, syncExecutable, detail.path, detail.line, detail.column)
        : state.buildResult?.previewPdfPath
          ? await api.synctexForward(state.project.id, syncExecutable, detail.path, detail.line, detail.column, state.buildResult.previewPdfPath)
          : null;
      if (target) setPdfTarget(target);
    };
    window.addEventListener("lightex:source-sync", sync);
    return () => window.removeEventListener("lightex:source-sync", sync);
  }, [state.project?.id, syncExecutable, state.buildResult?.previewPdfPath, state.versionPreview?.version.id]);

  useEffect(() => {
    if (state.versionPreview || !isDesktop() || !state.project || !syncExecutable || !state.buildResult?.succeeded || !state.buildResult.previewPdfPath || !state.selectedPath) return;
    if (state.documents[state.selectedPath]?.dirty) return;
    const projectId = state.project.id;
    const selectedPath = state.selectedPath;
    const previewPdfPath = state.buildResult.previewPdfPath;
    const buildResult = state.buildResult;
    const outline = state.outline.filter((item) => item.relativePath === selectedPath);
    let cancelled = false;
    const timer = window.setTimeout(() => {
      void (async () => {
        const pages: Record<string, number> = {};
        let cursor = 0;
        const worker = async () => {
          while (!cancelled) {
            const index = cursor;
            cursor += 1;
            if (index >= outline.length) return;
            const item = outline[index];
            try {
              const target = await api.synctexForward(projectId, syncExecutable, item.relativePath, item.line, 1, previewPdfPath);
              if (target?.page) pages[outlineItemKey(item)] = target.page;
            } catch {
              // A heading can be absent from SyncTeX (for example before its first successful build).
            }
          }
        };
        await Promise.all(Array.from({ length: Math.min(3, outline.length) }, () => worker()));
        const current = useAppStore.getState();
        if (!cancelled && current.project?.id === projectId && current.selectedPath === selectedPath && current.buildResult === buildResult) {
          useAppStore.setState({ outlinePages: { ...current.outlinePages, ...pages } });
        }
      })();
    }, 220);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [state.project?.id, state.selectedPath, state.outline, state.buildResult, syncExecutable, state.versionPreview?.version.id]);

  useEffect(() => {
    if (!isDesktop() || !state.project) return;
    let unlisten: (() => void) | undefined;
    void getCurrentWindow().onDragDropEvent((event) => {
      if (state.versionPreview || event.payload.type !== "drop" || event.payload.paths.length === 0) return;
      void api.uploadEntries(state.project!.id, "", event.payload.paths)
        .then(async (skipped) => {
          await state.refreshProject();
          if (skipped.length > 0) state.setError(`Skipped existing files: ${skipped.join(", ")}`);
        })
        .catch((error) => state.setError(String(error)));
    }).then((value) => { unlisten = value; });
    return () => unlisten?.();
  }, [state.project?.id, state.versionPreview?.version.id]);

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
      <header className="project-toolbar">
        <BackToProjectsControl onBack={() => void state.leaveProject()} />
        <button className="icon-button" onClick={() => useAppStore.setState({ sidebarVisible: !state.sidebarVisible })} aria-label="Toggle project sidebar" aria-pressed={state.sidebarVisible} title="Project sidebar"><PanelLeft size={16} /></button>
        <WindowDragRegion />
        <div className="project-toolbar-group version-controls" role="group" aria-label="Project versions">
          <button className="toolbar-button" onClick={() => setSaveVersionOpen(true)} disabled={Boolean(preview) || state.versionOperation !== null} aria-label="Save Version" title="Save a named project version"><BookmarkPlus size={15} aria-hidden="true" /><span>Save Version</span></button>
          <button className={`toolbar-button ${state.versionsOpen ? "pressed" : ""}`} onClick={() => void state.toggleVersions()} aria-label="Show saved versions" aria-pressed={state.versionsOpen} title="Saved versions"><History size={15} aria-hidden="true" /><span>Versions</span></button>
        </div>
        <div className="project-toolbar-group" role="group" aria-label="Editor panels">
          <button className={`toolbar-button ${state.insertShelfOpen ? "pressed" : ""}`} disabled={Boolean(preview)} onClick={() => useAppStore.setState({ insertShelfOpen: !state.insertShelfOpen })} aria-label="Toggle Insert Shelf" aria-pressed={state.insertShelfOpen} title="Symbols, equations, figures, and tables"><Sigma size={15} /><span>Insert</span></button>
        </div>
        <BuildControls
          automaticBuilds={state.config.automaticBuilds}
          delaySeconds={state.config.automaticBuildDelaySeconds}
          buildState={state.buildState}
          disabled={Boolean(preview)}
          onAutomaticBuildsChange={(automaticBuilds) => void state.updateConfig({ automaticBuilds })}
          onDelayChange={(automaticBuildDelaySeconds) => void state.updateConfig({ automaticBuildDelaySeconds })}
          onBuild={() => void state.build()}
          onCancel={() => void state.cancelBuild()}
        />
        <div className="project-toolbar-group" role="group" aria-label="Window controls">
          <button className="icon-button" onClick={() => useAppStore.setState({ pdfVisible: !state.pdfVisible })} aria-label="Toggle PDF preview" aria-pressed={state.pdfVisible} title="PDF preview"><PanelRight size={16} /></button>
          <button className="icon-button" onClick={() => useAppStore.setState({ settingsOpen: true })} aria-label="Open Settings" title="Settings"><Settings size={16} /></button>
        </div>
      </header>
      <div className="workspace-main" style={{ gridTemplateColumns: state.sidebarVisible ? `${sidebarWidth}px 5px 1fr` : "1fr" }}>
        {state.sidebarVisible && <>
          <aside className="project-sidebar">
            {preview ? <div className="preview-sidebar-heading"><Folder size={14} /><span>Saved Files</span><small>Read Only</small></div> : <div className="sidebar-mode-tabs" role="tablist" aria-label="Project navigation">
              <SidebarTab mode="files" current={state.sidebarMode} icon={<Folder size={14} />} label="Files" />
              <SidebarTab mode="search" current={state.sidebarMode} icon={<Search size={14} />} label="Search" />
            </div>}
            <div className="sidebar-primary-content">
              {preview ? <FileTree readOnly entries={preview.entries} selectedPath={preview.selectedPath} mainDocument={preview.version.mainDocument} onOpen={(path) => void state.openVersionDocument(path)} onCreateFile={() => undefined} onCreateFolder={() => undefined} onUpload={() => undefined} onRename={() => undefined} onDuplicate={() => undefined} onTrash={() => undefined} onMove={() => undefined} onReveal={() => undefined} onSetMain={() => undefined} /> : <>
                {state.sidebarMode === "files" && <FileTree errorPaths={buildErrorPaths} entries={state.entries} selectedPath={state.selectedPath} mainDocument={state.mainDocument} onOpen={(path) => void state.openDocument(path)} onCreateFile={createFile} onCreateFolder={createFolder} onUpload={upload} onRename={rename} onDuplicate={duplicate} onTrash={trash} onMove={move} onReveal={(path) => { if (state.project) void revealItemInDir(`${state.project.rootPath}/${path}`); }} onSetMain={(path) => void state.setMainDocument(path)} />}
                {state.sidebarMode === "search" && <SearchPanel />}
              </>}
            </div>
            <OutlineDrawer expanded={state.outlineExpanded} height={state.outlineHeight} onCommit={state.setOutlineDrawer} />
          </aside>
          <ResizeDivider axis="x" onMove={(delta) => setSidebarWidth((width) => Math.max(185, Math.min(330, width + delta)))} />
        </>}
        <div className="document-area">
          {preview && <div className="version-preview-bar">
            <div className="version-preview-identity">
              <History size={13} aria-hidden="true" />
              <div><strong>{preview.version.name}</strong><span><time dateTime={preview.version.createdAt}>{new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(new Date(preview.version.createdAt))}</time><span aria-hidden="true">·</span><span>Read only</span></span></div>
            </div>
            <div className="version-line-summary" aria-label={`${preview.lineSummary.additions} lines added and ${preview.lineSummary.deletions} lines removed across ${preview.lineSummary.changedFiles} files`} title="Changes in this saved version compared with the current project">
              <strong className="added">+{preview.lineSummary.additions}</strong>
              <strong className="deleted">−{preview.lineSummary.deletions}</strong>
              <span>{preview.lineSummary.changedFiles} {preview.lineSummary.changedFiles === 1 ? "file" : "files"}</span>
            </div>
            <button className="secondary-button compact" onClick={state.closeVersionPreview}>Back to Current</button>
            <button className="primary-button compact" onClick={() => setRestoreVersion(preview.version)}><ArchiveRestore size={13} aria-hidden="true" />Restore Version</button>
          </div>}
          <div className="editor-pdf-split" style={editorStyle}>
            <div className="source-column">
              <div className="source-header">
                <EditorTabs readOnly={Boolean(preview)} tabs={displayedTabs} selectedPath={displayedSelectedPath} documents={displayedDocuments} onSelect={(path) => preview ? void state.openVersionDocument(path) : state.selectDocument(path)} onClose={(path) => { if (!preview) void state.closeDocument(path); }} onReorder={preview ? () => undefined : state.reorderTabs} onMove={preview ? () => undefined : state.moveTab} onFileDrop={(path) => { if (!preview) void state.openDocument(path); }} />
                <EditorQuickControls
                  canUndo={!preview && canUndo}
                  fontSize={state.config.editorFontSize}
                  onUndo={() => { if (!preview) sourceEditorRef.current?.undo(); }}
                  onFontSizeChange={(editorFontSize) => void state.updateConfig({ editorFontSize })}
                />
              </div>
              {!preview && selectedDocument && selectedDocument.externalChange !== "none" && <div className="conflict-banner" role="alert">
                <span>{selectedDocument.externalChange === "deleted" ? `${selectedDocument.relativePath} was deleted outside LighTex.` : `${selectedDocument.relativePath} changed outside LighTex.`}</span>
                {selectedDocument.externalChange === "modified" && <button onClick={() => state.resolveConflict(selectedDocument.relativePath, "reload")}>Reload</button>}
                {selectedDocument.externalChange === "modified" && <button onClick={() => state.resolveConflict(selectedDocument.relativePath, "keep")}>Keep Mine</button>}
                <button onClick={() => void saveConflictCopy(selectedDocument.relativePath)}>{selectedDocument.externalChange === "deleted" ? "Save As" : "Save Copy"}</button>
                {selectedDocument.externalChange === "deleted" && <button onClick={() => void state.closeDocument(selectedDocument.relativePath)}>Close</button>}
              </div>}
              <section className="source-pane" aria-label="Source editor">
                {selectedDocument ? <SourceEditor readOnly={Boolean(preview)} diff={preview?.fileDiffs[selectedDocument.relativePath] ?? null} diagnostics={inlineDiagnostics} buildLog={state.buildResult?.log ?? ""} ref={sourceEditorRef} key={`${preview?.version.id ?? "current"}:${selectedDocument.relativePath}`} historyKey={preview ? `version:${preview.version.id}:${selectedDocument.relativePath}` : `${state.project?.id ?? "project"}:${selectedDocument.relativePath}`} path={selectedDocument.relativePath} value={selectedDocument.text} config={state.config} completion={state.completion} onUndoAvailabilityChange={setCanUndo} onChange={(text) => { if (!preview) state.updateText(selectedDocument.relativePath, text); }} /> : <div className="empty-state"><FileText size={25} /><span className="empty-state-title">No file open</span><span>Choose a text file from the project sidebar.</span></div>}
              </section>
              {!preview && state.insertShelfOpen && <InsertShelf onClose={() => useAppStore.setState({ insertShelfOpen: false })} />}
            </div>
            {state.pdfVisible && <>
              <ResizeDivider axis="x" onMove={(delta) => setEditorFraction((fraction) => Math.max(0.3, Math.min(0.7, fraction + delta / Math.max(700, window.innerWidth - sidebarWidth))))} />
              <PdfPreview base64={displayedPdf} target={pdfTarget} outline={displayedOutline} onOutlinePages={acceptPdfOutlinePages} onInverse={async (page, x, y) => {
                if (!state.project || !syncExecutable) return;
                if (preview) {
                  const target = await api.synctexProjectVersionInverse(state.project.id, preview.version.id, syncExecutable, page, x, y);
                  if (target) await state.openVersionDocument(target.relativePath, target.line);
                } else if (state.buildResult?.previewPdfPath) {
                  const target = await api.synctexInverse(state.project.id, syncExecutable, state.buildResult.previewPdfPath, page, x, y);
                  if (target) await state.openDocument(target.relativePath, target.line);
                }
              }} />
            </>}
          </div>
        </div>
      </div>
      <footer className="status-bar">
        {state.buildState === "failure" ? <CircleX className="status-failure-icon" size={13} aria-hidden="true" /> : <span className={`status-dot ${state.buildState}`} />}
        <span>{state.statusMessage}</span>
        <div className="toolbar-spacer" />
        <span>{displayedSelectedPath ?? "No file"}</span>
        <span>UTF-8</span>
      </footer>
      {uploadTarget !== null && <div className="modal-layer" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setUploadTarget(null); }}><section ref={uploadDialog} className="native-dialog upload-dialog" role="dialog" aria-modal="true" aria-labelledby="upload-title"><h2 id="upload-title">Upload to Project</h2><p>Choose files or copy an entire folder into {uploadTarget || "the project root"}. Existing items are never overwritten.</p><div className="dialog-actions"><button className="secondary-button" onClick={() => setUploadTarget(null)}>Cancel</button><button className="secondary-button" onClick={() => { const target = uploadTarget; setUploadTarget(null); void chooseUpload(target, true); }}>Choose Folder…</button><button className="primary-button" onClick={() => { const target = uploadTarget; setUploadTarget(null); void chooseUpload(target, false); }}>Choose Files…</button></div></section></div>}
      {nameRequest && <NameDialog request={nameRequest} onClose={() => setNameRequest(null)} onSubmit={commitName} />}
      {saveVersionOpen && <SaveVersionDialog onClose={() => setSaveVersionOpen(false)} />}
      {state.versionsOpen && <VersionsPanel />}
      {restoreVersion && <RestoreVersionDialog version={restoreVersion} onClose={() => setRestoreVersion(null)} />}
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
