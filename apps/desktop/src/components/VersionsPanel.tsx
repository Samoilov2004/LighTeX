import { useEffect, useState } from "react";
import { FileClock, History, LoaderCircle, MoreHorizontal, Pencil, RefreshCw, Trash2, X } from "lucide-react";
import { ask } from "@tauri-apps/plugin-dialog";
import { api, isDesktop } from "../api";
import { useAppStore } from "../store";
import type { ProjectVersionId, ProjectVersionSummary, VersionChangeSummary, VersionSnapshotReview } from "../types";
import { useModalFocus } from "../useModalFocus";

export function VersionsPanel() {
  const versions = useAppStore((state) => state.versions);
  const close = () => useAppStore.setState({ versionsOpen: false });
  const openPreview = useAppStore((state) => state.openVersionPreview);
  const retry = useAppStore((state) => state.retryVersionPreview);
  const rename = useAppStore((state) => state.renameVersion);
  const remove = useAppStore((state) => state.deleteVersion);
  const [menu, setMenu] = useState<ProjectVersionId | null>(null);
  const [renaming, setRenaming] = useState<ProjectVersionSummary | null>(null);
  const panel = useModalFocus<HTMLElement>(close, renaming === null);
  const named = versions.filter((version) => version.kind === "named");
  const recovery = versions.filter((version) => version.kind === "recovery");

  const deleteVersion = async (version: ProjectVersionSummary) => {
    setMenu(null);
    const message = `Delete “${version.name}”? The project files are not changed, but this saved version cannot be restored afterward.`;
    const confirmed = isDesktop()
      ? await ask(message, { title: "Delete Saved Version", kind: "warning", okLabel: "Delete", cancelLabel: "Cancel" })
      : window.confirm(message);
    if (confirmed) await remove(version.id);
  };

  return (
    <div className="versions-layer" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) close(); }}>
      <aside ref={panel} className="versions-panel" role="dialog" aria-modal="true" aria-label="Saved Versions">
        <header className="versions-header">
          <span><History size={16} aria-hidden="true" /><strong>Versions</strong></span>
          <button className="icon-button" onClick={close} aria-label="Close Versions"><X size={16} /></button>
        </header>
        <div className="versions-body">
          {versions.length === 0 && (
            <div className="versions-empty">
              <FileClock size={27} aria-hidden="true" />
              <strong>No saved versions</strong>
              <span>Name a milestone and return to it whenever you need.</span>
              <button className="primary-button compact" onClick={() => { close(); window.dispatchEvent(new CustomEvent("lightex:save-version")); }}>Save Version…</button>
            </div>
          )}
          {named.length > 0 && <VersionSection title="Saved" versions={named} menu={menu} setMenu={setMenu} onOpen={openPreview} onRetry={retry} onRename={setRenaming} onDelete={deleteVersion} />}
          {recovery.length > 0 && <VersionSection title="Recovery" versions={recovery} menu={menu} setMenu={setMenu} onOpen={openPreview} onRetry={retry} onRename={setRenaming} onDelete={deleteVersion} />}
        </div>
      </aside>
      {renaming && <RenameVersionDialog version={renaming} onClose={() => setRenaming(null)} onRename={async (name) => { await rename(renaming.id, name); setRenaming(null); }} />}
    </div>
  );
}

function VersionSection({ title, versions, menu, setMenu, onOpen, onRetry, onRename, onDelete }: {
  title: string;
  versions: ProjectVersionSummary[];
  menu: ProjectVersionId | null;
  setMenu(value: ProjectVersionId | null): void;
  onOpen(version: ProjectVersionSummary): Promise<void>;
  onRetry(versionId: ProjectVersionId): Promise<void>;
  onRename(version: ProjectVersionSummary): void;
  onDelete(version: ProjectVersionSummary): Promise<void>;
}) {
  return (
    <section className="versions-section" aria-labelledby={`versions-${title.toLowerCase()}`}>
      <h3 id={`versions-${title.toLowerCase()}`}>{title}</h3>
      <div className="version-list">
        {versions.map((version) => (
          <article key={version.id} className="version-row">
            <button className="version-open" onClick={() => void onOpen(version)}>
              <span className="version-row-title"><strong title={version.name}>{version.name}</strong>{version.kind === "recovery" && <small className="recovery-badge">Recovery</small>}</span>
              <span className="version-meta"><time dateTime={version.createdAt}>{formatDate(version.createdAt)}</time><span>·</span><span>{version.fileCount} files</span><span>·</span><span>{formatBytes(version.totalSize)}</span></span>
              <PreviewStatus version={version} />
            </button>
            {version.previewStatus === "failed" && (
              <button
                className="icon-button version-retry"
                onClick={() => void onRetry(version.id)}
                aria-label={`Retry PDF preview for ${version.name}`}
                title="Retry PDF preview"
              >
                <RefreshCw size={13} />
              </button>
            )}
            <button className="icon-button version-more" aria-label={`Actions for ${version.name}`} aria-haspopup="menu" aria-expanded={menu === version.id} onClick={() => setMenu(menu === version.id ? null : version.id)}><MoreHorizontal size={15} /></button>
            {menu === version.id && <div className="popover-menu version-menu" role="menu">
              <button role="menuitem" onClick={() => { setMenu(null); onRename(version); }}><Pencil size={13} />Rename</button>
              <button role="menuitem" className="destructive" onClick={() => void onDelete(version)}><Trash2 size={13} />Delete</button>
            </div>}
          </article>
        ))}
      </div>
    </section>
  );
}

function PreviewStatus({ version }: { version: ProjectVersionSummary }) {
  if (version.previewStatus === "building") return <span className="version-preview-status"><LoaderCircle className="spinning" size={11} />Preparing PDF…</span>;
  if (version.previewStatus === "ready") return <span className="version-preview-status ready">PDF ready</span>;
  if (version.previewStatus === "failed") return <span className="version-preview-status failed" title={version.previewError ?? undefined}>PDF unavailable</span>;
  return <span className="version-preview-status">PDF not prepared</span>;
}

export function SaveVersionDialog({ onClose }: { onClose(): void }) {
  const project = useAppStore((state) => state.project);
  const mainDocument = useAppStore((state) => state.mainDocument);
  const createVersion = useAppStore((state) => state.createVersion);
  const operation = useAppStore((state) => state.versionOperation);
  const [name, setName] = useState("");
  const [review, setReview] = useState<VersionSnapshotReview | null>(null);
  const [reviewError, setReviewError] = useState<string | null>(null);
  const dialog = useModalFocus<HTMLFormElement>(() => { if (operation !== "saving") onClose(); });
  useEffect(() => {
    if (!project) return;
    let active = true;
    void api.reviewProjectVersion(project.id, mainDocument)
      .then((value) => { if (active) setReview(value); })
      .catch((error) => { if (active) setReviewError(String(error)); });
    return () => { active = false; };
  }, [project?.id, mainDocument]);
  const trimmed = name.trim();
  return (
    <div className="modal-layer" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && operation !== "saving") onClose(); }}>
      <form ref={dialog} className="native-dialog save-version-dialog" role="dialog" aria-modal="true" aria-labelledby="save-version-title" onSubmit={async (event) => {
        event.preventDefault();
        if (!trimmed || operation === "saving") return;
        if (await createVersion(trimmed)) onClose();
      }}>
        <h2 id="save-version-title">Save Version</h2>
        <p>Create a named snapshot of the entire project without changing its Git history.</p>
        <label><span>Name</span><input value={name} maxLength={80} onChange={(event) => setName(event.target.value)} placeholder="For example, First complete draft" autoFocus /></label>
        <p className={`version-review ${reviewError ? "error" : ""}`} aria-live="polite">
          {review ? `${review.fileCount} files · ${formatBytes(review.totalSize)}` : reviewError ? `Could not review the project: ${reviewError}` : "Reviewing project files…"}
        </p>
        <div className="dialog-actions">
          <button type="button" className="secondary-button" onClick={onClose} disabled={operation === "saving"}>Cancel</button>
          <button className="primary-button" disabled={!trimmed || trimmed.length > 80 || operation === "saving"}>{operation === "saving" && <LoaderCircle className="spinning" size={13} />}{operation === "saving" ? "Saving…" : "Save Version"}</button>
        </div>
      </form>
    </div>
  );
}

export function RestoreVersionDialog({ version, onClose }: { version: ProjectVersionSummary; onClose(): void }) {
  const compare = useAppStore((state) => state.compareVersion);
  const restore = useAppStore((state) => state.restoreVersion);
  const operation = useAppStore((state) => state.versionOperation);
  const [changes, setChanges] = useState<VersionChangeSummary | null>(null);
  const dialog = useModalFocus<HTMLElement>(() => { if (operation !== "restoring") onClose(); });
  useEffect(() => {
    let active = true;
    void compare(version.id).then((value) => { if (active) setChanges(value); });
    return () => { active = false; };
  }, [version.id]);
  const count = changes ? changes.added.length + changes.modified.length + changes.removed.length : null;
  const paths = changes ? [...changes.added, ...changes.modified, ...changes.removed].slice(0, 7) : [];
  return (
    <div className="modal-layer" role="presentation">
      <section ref={dialog} className="native-dialog restore-version-dialog" role="alertdialog" aria-modal="true" aria-labelledby="restore-version-title" aria-describedby="restore-version-description">
        <h2 id="restore-version-title">Restore “{version.name}”?</h2>
        <p id="restore-version-description">LighTex will first save the current project as a recovery version, then replace the project with this snapshot. Git metadata is never changed.</p>
        <div className="restore-summary" aria-live="polite">
          {!changes && <span>Comparing project files…</span>}
          {changes && <><strong>{count === 0 ? "The project already matches this version." : `${count} project ${count === 1 ? "file" : "files"} will change`}</strong><span>{changes.added.length} restored · {changes.modified.length} replaced · {changes.removed.length} removed</span>{paths.length > 0 && <ul>{paths.map((path) => <li key={path}>{path}</li>)}</ul>}</>}
        </div>
        <div className="dialog-actions">
          <button className="secondary-button" onClick={onClose} disabled={operation === "restoring"}>Cancel</button>
          <button className="primary-button" disabled={!changes || operation === "restoring"} onClick={async () => { if (await restore(version)) onClose(); }}>{operation === "restoring" && <LoaderCircle className="spinning" size={13} />}{operation === "restoring" ? "Restoring…" : "Restore Version"}</button>
        </div>
      </section>
    </div>
  );
}

function RenameVersionDialog({ version, onClose, onRename }: { version: ProjectVersionSummary; onClose(): void; onRename(name: string): Promise<void> }) {
  const [name, setName] = useState(version.name);
  const dialog = useModalFocus<HTMLFormElement>(onClose);
  return <div className="modal-layer nested-modal" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><form ref={dialog} className="native-dialog name-dialog" role="dialog" aria-modal="true" aria-labelledby="rename-version-title" onSubmit={(event) => { event.preventDefault(); if (name.trim()) void onRename(name.trim()); }}><h2 id="rename-version-title">Rename Version</h2><label><span>Name</span><input value={name} maxLength={80} onChange={(event) => setName(event.target.value)} autoFocus onFocus={(event) => event.currentTarget.select()} /></label><div className="dialog-actions"><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button className="primary-button" disabled={!name.trim()}>Rename</button></div></form></div>;
}

function formatBytes(bytes: number) {
  if (bytes < 1_000) return `${bytes} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let value = bytes / 1_000;
  let unit = 0;
  while (value >= 1_000 && unit < units.length - 1) { value /= 1_000; unit += 1; }
  return `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(value)} ${units[unit]}`;
}

function formatDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(undefined, { year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(date);
}
