import { useEffect, useState } from "react";
import { FilePlus2, FolderOpen, LayoutTemplate, Settings, Trash2 } from "lucide-react";
import { ask, open } from "@tauri-apps/plugin-dialog";
import { api, isDesktop } from "../api";
import { useAppStore } from "../store";
import type { PersonalTemplateManifestV2, TemplateReview } from "../types";
import { renderFirstPagePreview } from "../pdf";
import { useModalFocus } from "../useModalFocus";

interface TemplateDefinition {
  id: string;
  name: string;
  summary: string;
  style: string;
}

const templates: TemplateDefinition[] = [
  { id: "article", name: "Article", summary: "Abstract, sections, figures, and references.", style: "article" },
  { id: "mathematics", name: "Mathematics", summary: "Theorems, definitions, proofs, and aligned equations.", style: "math" },
  { id: "textbook", name: "Textbook", summary: "A book structure with contents, chapters, and figures.", style: "book" },
  { id: "presentation", name: "Presentation", summary: "A restrained Beamer deck for technical talks.", style: "slides" },
];

export function ProjectHub() {
  const config = useAppStore((state) => state.config);
  const openProject = useAppStore((state) => state.openProjectPath);
  const updateConfig = useAppStore((state) => state.updateConfig);
  const [create, setCreate] = useState<{ template: string; title: string } | null>(null);
  const [personal, setPersonal] = useState<PersonalTemplateManifestV2[]>([]);
  const [review, setReview] = useState<TemplateReview | null>(null);
  const [hubError, setHubError] = useState<string | null>(null);
  useEffect(() => {
    if (isDesktop()) void api.listPersonalTemplates().then(setPersonal).catch((error) => setHubError(String(error)));
  }, []);
  const chooseFolder = async () => {
    if (!isDesktop()) return;
    const selected = await open({ directory: true, multiple: false, title: "Open LaTeX Project" });
    if (typeof selected === "string") await openProject(selected);
  };
  const clearRecent = async () => {
    const confirmed = await ask("Remove all recent projects from LighTex? The project folders and every local file will remain on your Mac or Linux computer.", {
      title: "Clear Recent Projects",
      kind: "warning",
      okLabel: "Clear History",
      cancelLabel: "Cancel",
    });
    if (confirmed) await updateConfig({ recentProjects: [] });
  };
  const reviewTemplate = async () => {
    const selected = await open({ directory: true, multiple: false, title: "Choose a Project to Save as a Template" });
    if (typeof selected !== "string") return;
    try { setReview(await api.templateReview(selected)); }
    catch (error) { setHubError(String(error)); }
  };
  const removeTemplate = async (template: PersonalTemplateManifestV2) => {
    const confirmed = await ask(`Move the personal template “${template.name}” to Trash? Projects already created from it are not affected.`, {
      title: "Remove Personal Template",
      kind: "warning",
      okLabel: "Move to Trash",
      cancelLabel: "Cancel",
    });
    if (!confirmed) return;
    try {
      await api.removePersonalTemplate(template.id);
      setPersonal(await api.listPersonalTemplates());
    } catch (error) { setHubError(String(error)); }
  };
  useEffect(() => {
    const menu = (event: Event) => {
      const action = (event as CustomEvent<string>).detail;
      if (action === "new-project") setCreate({ template: "empty", title: "New Empty Project" });
      if (action === "open-project") void chooseFolder();
    };
    window.addEventListener("lightex:menu-action", menu);
    return () => window.removeEventListener("lightex:menu-action", menu);
  }, []);
  return (
    <main className="hub-view">
      <div className="hub-toolbar" data-tauri-drag-region>
        <div data-tauri-drag-region className="toolbar-spacer" />
        <button className="icon-button" onClick={() => useAppStore.setState({ settingsOpen: true })} aria-label="Open Settings" title="Settings"><Settings size={16} /></button>
      </div>
      <div className="hub-content">
        <header className="hub-heading"><h1>LighTex</h1><p>A focused workspace for local LaTeX projects.</p></header>
        <div className="hub-actions">
          <button className="primary-button large" onClick={() => setCreate({ template: "empty", title: "New Empty Project" })}><FilePlus2 size={17} />New Empty Project</button>
          <button className="secondary-button large" onClick={chooseFolder}><FolderOpen size={17} />Open Project</button>
          <button className="secondary-button large" onClick={() => document.getElementById("templates")?.scrollIntoView()}><LayoutTemplate size={17} />Templates</button>
        </div>
        <section className="recent-section">
          <div className="section-heading"><h2>Recent Projects</h2>{config.recentProjects.length > 0 && <button onClick={() => void clearRecent()}>Clear</button>}</div>
          {config.recentProjects.length === 0 ? <p className="empty-copy">Projects you open will appear here. Their files always remain in normal folders.</p> : (
            <div className="recent-list">{config.recentProjects.map((path) => <button key={path} onClick={() => openProject(path)}><FolderOpen size={15} /><span><strong>{fileName(path)}</strong><small>{path}</small></span></button>)}</div>
          )}
        </section>
        <section className="templates-section" id="templates">
          <div className="section-heading"><h2>Yours</h2></div>
          {personal.length === 0 ? <div className="personal-template-empty"><LayoutTemplate size={21} /><span><strong>No personal templates yet</strong><small>Reusable copies of your own projects will appear here.</small></span><button className="secondary-button" onClick={() => void reviewTemplate()}>Create Template</button></div> : <>
            <div className="personal-template-actions"><button className="secondary-button" onClick={() => void reviewTemplate()}><FilePlus2 size={14} />Create Template</button></div>
            <div className="template-grid personal-grid">{personal.map((template) => <div className="template-card personal-template-card" key={template.id}>
              <button className="template-open" onClick={() => setCreate({ template: `personal:${template.id}`, title: `New ${template.name}` })}><PersonalTemplatePreview template={template} /><span><strong>{template.name}</strong><small>{template.mainDocument ?? "Project template"}</small></span></button>
              <button className="icon-button template-delete" aria-label={`Remove ${template.name}`} onClick={() => void removeTemplate(template)}><Trash2 size={13} /></button>
            </div>)}</div>
          </>}
          <div className="section-heading bundled"><h2>LighTex Templates</h2></div>
          <div className="template-grid">{templates.map((template) => <button className="template-card" key={template.id} onClick={() => setCreate({ template: template.id, title: `New ${template.name}` })}><TemplatePreview styleName={template.style} /><span><strong>{template.name}</strong><small>{template.summary}</small></span></button>)}</div>
        </section>
      </div>
      {create && <CreateProjectDialog template={create.template} title={create.title} onClose={() => setCreate(null)} onCreated={openProject} />}
      {review && <TemplateReviewDialog review={review} onClose={() => setReview(null)} onCreated={async () => { setReview(null); setPersonal(await api.listPersonalTemplates()); }} />}
      {hubError && <div className="error-toast" role="alert">{hubError}<button className="icon-button" onClick={() => setHubError(null)} aria-label="Dismiss error">×</button></div>}
    </main>
  );
}

function CreateProjectDialog({ template, title, onClose, onCreated }: { template: string; title: string; onClose(): void; onCreated(path: string): void }) {
  const [name, setName] = useState(template === "empty" ? "Untitled" : `My ${title.replace("New ", "")}`);
  const [parent, setParent] = useState("");
  const [error, setError] = useState<string | null>(null);
  const dialog = useModalFocus<HTMLFormElement>(onClose);
  const choose = async () => {
    const selected = await open({ directory: true, multiple: false, title: "Choose Project Location" });
    if (typeof selected === "string") setParent(selected);
  };
  const submit = async () => {
    if (!name.trim() || !parent) return;
    try {
      const path = template === "empty"
        ? await api.createProject(parent, name)
        : template.startsWith("personal:")
          ? await api.createProjectFromPersonalTemplate(template.slice("personal:".length), parent, name)
          : await api.createProjectFromTemplate(parent, name, template);
      onClose();
      await onCreated(path);
    } catch (reason) { setError(String(reason)); }
  };
  return (
    <div className="modal-layer" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <form ref={dialog} className="native-dialog" role="dialog" aria-modal="true" aria-labelledby="create-project-title" onSubmit={(event) => { event.preventDefault(); void submit(); }}>
        <h2 id="create-project-title">{title}</h2>
        <label><span>Name</span><input value={name} onChange={(event) => setName(event.target.value)} autoFocus /></label>
        <label><span>Location</span><div className="path-picker"><input value={parent} readOnly placeholder="Choose a folder" /><button type="button" className="secondary-button" onClick={choose}>Choose…</button></div></label>
        {error && <p className="inline-error" role="alert">{error}</p>}
        <div className="dialog-actions"><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button className="primary-button" disabled={!name.trim() || !parent}>Create</button></div>
      </form>
    </div>
  );
}

function TemplateReviewDialog({ review, onClose, onCreated }: { review: TemplateReview; onClose(): void; onCreated(): Promise<void> }) {
  const [name, setName] = useState(`${fileName(review.sourcePath)} Template`);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const dialog = useModalFocus<HTMLElement>(onClose);
  const submit = async () => {
    if (!name.trim()) return;
    setSaving(true);
    try {
      const sourcePdf = await api.templatePreviewPdf(review).catch(() => null);
      const preview = sourcePdf ? await renderFirstPagePreview(sourcePdf) : null;
      await api.createPersonalTemplate(name.trim(), review, preview);
      await onCreated();
    } catch (reason) { setError(String(reason)); setSaving(false); }
  };
  return <div className="modal-layer" role="presentation">
    <section ref={dialog} className="native-dialog template-review-dialog" role="dialog" aria-modal="true" aria-labelledby="template-review-title">
      <h2 id="template-review-title">Review Personal Template</h2>
      <p>LighTex will copy the included files into its template library. The original project is not changed.</p>
      <label><span>Template name</span><input value={name} onChange={(event) => setName(event.target.value)} autoFocus /></label>
      <div className="review-columns">
        <ReviewList title={`Included · ${review.includedFiles.length}`} files={review.includedFiles} />
        <ReviewList title={`Excluded · ${review.excludedFiles.length}`} files={review.excludedFiles} muted />
      </div>
      <p className="review-note">Secrets, private keys, `.env`, Git data, caches, build output, and generated LaTeX files are excluded automatically. Included size: {formatBytes(review.totalSize)}.</p>
      {error && <p className="inline-error" role="alert">{error}</p>}
      <div className="dialog-actions"><button className="secondary-button" onClick={onClose} disabled={saving}>Cancel</button><button className="primary-button" onClick={() => void submit()} disabled={!name.trim() || saving}>{saving ? "Saving…" : "Create Template"}</button></div>
    </section>
  </div>;
}

function ReviewList({ title, files, muted = false }: { title: string; files: string[]; muted?: boolean }) {
  return <section className={muted ? "review-list muted" : "review-list"}><strong>{title}</strong><div>{files.length === 0 ? <small>None</small> : files.slice(0, 80).map((file) => <code key={file}>{file}</code>)}</div></section>;
}

function PersonalTemplatePreview({ template }: { template: PersonalTemplateManifestV2 }) {
  const [preview, setPreview] = useState<string | null>(null);
  useEffect(() => {
    if (!template.preview) return;
    void api.personalTemplatePreview(template.id).then((value) => setPreview(value ? `data:image/png;base64,${value}` : null));
  }, [template.id, template.preview]);
  return preview ? <span className="template-preview image"><img src={preview} alt="" /></span> : <TemplatePreview styleName="personal" />;
}

function TemplatePreview({ styleName }: { styleName: string }) {
  return <span className={`template-preview ${styleName}`} aria-hidden="true"><i /><b /><i /><i /><em /></span>;
}

const fileName = (path: string) => path.split("/").filter(Boolean).pop() ?? path;
const formatBytes = (bytes: number) => `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(bytes / (bytes >= 1_000_000 ? 1_000_000 : 1_000))} ${bytes >= 1_000_000 ? "MB" : "KB"}`;
