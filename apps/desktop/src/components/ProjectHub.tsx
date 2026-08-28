import { useEffect, useState } from "react";
import { ArrowLeft, FilePlus2, FolderOpen, LayoutTemplate, Settings, Trash2 } from "lucide-react";
import { ask, open } from "@tauri-apps/plugin-dialog";
import { desktopDir } from "@tauri-apps/api/path";
import { api, isDesktop } from "../api";
import { useAppStore } from "../store";
import type { PersonalTemplateManifestV2, TemplateReview } from "../types";
import { renderFirstPagePreview } from "../pdf";
import { useModalFocus } from "../useModalFocus";
import appIcon from "../assets/AppIcon128.png";
import articlePreview from "../assets/template-previews/article.png";
import mathematicsPreview from "../assets/template-previews/mathematics.png";
import textbookPreview from "../assets/template-previews/textbook.png";
import presentationPreview from "../assets/template-previews/presentation.png";
import { WindowDragRegion } from "./WindowDragRegion";

interface TemplateDefinition {
  id: string;
  name: string;
  summary: string;
  kind: string;
  preview: string;
}

const templates: TemplateDefinition[] = [
  { id: "article", name: "Article", summary: "Abstract, sections, figures, and references.", kind: "Paper", preview: articlePreview },
  { id: "mathematics", name: "Mathematics", summary: "Theorems, proofs, and aligned equations.", kind: "Math", preview: mathematicsPreview },
  { id: "textbook", name: "Textbook", summary: "Contents, chapters, exercises, and figures.", kind: "Book", preview: textbookPreview },
  { id: "presentation", name: "Presentation", summary: "A restrained Beamer deck for technical talks.", kind: "Slides", preview: presentationPreview },
];

export function ProjectHub() {
  const config = useAppStore((state) => state.config);
  const openProject = useAppStore((state) => state.openProjectPath);
  const updateConfig = useAppStore((state) => state.updateConfig);
  const [create, setCreate] = useState<{ template: string; title: string } | null>(null);
  const [personal, setPersonal] = useState<PersonalTemplateManifestV2[]>([]);
  const [review, setReview] = useState<TemplateReview | null>(null);
  const [hubError, setHubError] = useState<string | null>(null);
  const [screen, setScreen] = useState<"projects" | "templates">("projects");
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
      <div className="hub-toolbar">
        {screen === "templates" && <button className="icon-button project-back" onClick={() => setScreen("projects")} aria-label="Back to Projects" title="Projects"><ArrowLeft size={16} /></button>}
        <WindowDragRegion />
        <button className="icon-button" onClick={() => useAppStore.setState({ settingsOpen: true })} aria-label="Open Settings" title="Settings"><Settings size={16} /></button>
      </div>
      {screen === "projects" ? <ProjectsScreen config={config} openProject={openProject} chooseFolder={chooseFolder} clearRecent={clearRecent} onNewEmpty={() => setCreate({ template: "empty", title: "New Empty Project" })} onShowTemplates={() => setScreen("templates")} /> :
        <TemplatesScreen personal={personal} onReviewTemplate={reviewTemplate} onRemoveTemplate={removeTemplate} onCreate={(template, title) => setCreate({ template, title })} />}
      {create && <CreateProjectDialog template={create.template} title={create.title} onClose={() => setCreate(null)} onCreated={openProject} />}
      {review && <TemplateReviewDialog review={review} onClose={() => setReview(null)} onCreated={async () => { setReview(null); setPersonal(await api.listPersonalTemplates()); }} />}
      {hubError && <div className="error-toast" role="alert">{hubError}<button className="icon-button" onClick={() => setHubError(null)} aria-label="Dismiss error">×</button></div>}
    </main>
  );
}

function ProjectsScreen({ config, openProject, chooseFolder, clearRecent, onNewEmpty, onShowTemplates }: {
  config: ReturnType<typeof useAppStore.getState>["config"];
  openProject(path: string): Promise<void>;
  chooseFolder(): Promise<void>;
  clearRecent(): Promise<void>;
  onNewEmpty(): void;
  onShowTemplates(): void;
}) {
  return <div className="hub-content projects-content">
    <header className="hub-heading">
      <img src={appIcon} alt="" />
      <div><h1>LighTex</h1><p>A lightweight local LaTeX editor</p></div>
    </header>
    <div className="hub-overview">
      <section className="start-section" aria-labelledby="start-heading">
        <h2 id="start-heading">Start</h2>
        <div className="hub-actions">
          <button className="primary-button large" onClick={onNewEmpty}><FilePlus2 size={17} />New Empty Project</button>
          <button className="secondary-button large" onClick={() => void chooseFolder()}><FolderOpen size={17} />Open Project…</button>
          <button className="secondary-button large" onClick={onShowTemplates}><LayoutTemplate size={17} />New from Template</button>
        </div>
      </section>
      <section className="recent-section" aria-labelledby="recent-heading">
        <div className="section-heading"><h2 id="recent-heading">Recent Projects</h2>{config.recentProjects.length > 0 && <button onClick={() => void clearRecent()}>Clear</button>}</div>
        {config.recentProjects.length === 0 ? <div className="recent-empty"><FolderOpen size={18} /><span><strong>No recent projects</strong><small>Projects you open will appear here. Local files are never moved.</small></span></div> : (
          <div className="recent-list">{config.recentProjects.map((path) => <button key={path} title={path} onClick={() => void openProject(path)}><FolderOpen size={15} /><span><strong>{fileName(path)}</strong><small>{path}</small></span></button>)}</div>
        )}
      </section>
    </div>
  </div>;
}

function TemplatesScreen({ personal, onReviewTemplate, onRemoveTemplate, onCreate }: {
  personal: PersonalTemplateManifestV2[];
  onReviewTemplate(): Promise<void>;
  onRemoveTemplate(template: PersonalTemplateManifestV2): Promise<void>;
  onCreate(template: string, title: string): void;
}) {
  return <div className="hub-content templates-content">
    <header className="templates-heading"><h1>Templates</h1><p>Start a new project from a reusable layout.</p></header>
    <section className="templates-section" aria-labelledby="personal-templates-heading">
      <div className="section-heading"><h2 id="personal-templates-heading">Yours</h2></div>
      {personal.length === 0 ? <div className="personal-template-empty"><LayoutTemplate size={21} /><span><strong>No personal templates yet</strong><small>Save one of your projects here to reuse it later.</small></span><button className="secondary-button" onClick={() => void onReviewTemplate()}>Create Template</button></div> : <>
        <div className="personal-template-actions"><button className="secondary-button" onClick={() => void onReviewTemplate()}><FilePlus2 size={14} />Create Template</button></div>
        <div className="template-grid personal-grid">{personal.map((template) => <div className="template-card personal-template-card" key={template.id}>
          <button className="template-open" onClick={() => onCreate(`personal:${template.id}`, `New ${template.name}`)}><PersonalTemplatePreview template={template} /><span><strong>{template.name}</strong><small>{template.mainDocument ?? "Project template"}</small></span></button>
          <button className="icon-button template-delete" aria-label={`Remove ${template.name}`} onClick={() => void onRemoveTemplate(template)}><Trash2 size={13} /></button>
        </div>)}</div>
      </>}
      <div className="section-heading bundled"><h2>LighTex Templates</h2></div>
      <div className="template-grid">{templates.map((template) => <button className="template-card" key={template.id} onClick={() => onCreate(template.id, `New ${template.name}`)}><TemplatePreview kind={template.kind} preview={template.preview} name={template.name} /><span><strong>{template.name}</strong><small>{template.summary}</small></span></button>)}</div>
    </section>
  </div>;
}

function CreateProjectDialog({ template, title, onClose, onCreated }: { template: string; title: string; onClose(): void; onCreated(path: string): void }) {
  const [name, setName] = useState(template === "empty" ? "Untitled" : `My ${title.replace("New ", "")}`);
  const [parent, setParent] = useState("");
  const [error, setError] = useState<string | null>(null);
  const dialog = useModalFocus<HTMLFormElement>(onClose);
  useEffect(() => {
    if (!isDesktop()) return;
    let active = true;
    void desktopDir().then((path) => { if (active) setParent(path); }).catch(() => {});
    return () => { active = false; };
  }, []);
  const choose = async () => {
    const selected = await open({ directory: true, multiple: false, title: "Choose Project Location", defaultPath: parent || undefined });
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
  return preview ? <span className="template-preview image"><img src={preview} alt={`${template.name} first-page preview`} /></span> : <TemplatePreview kind="Yours" icon={<LayoutTemplate size={29} strokeWidth={1.55} />} name={template.name} />;
}

function TemplatePreview({ kind, name, preview, icon }: { kind: string; name: string; preview?: string; icon?: React.ReactNode }) {
  return preview
    ? <span className="template-preview image"><img src={preview} alt={`${name} first-page preview`} /><span className="template-kind">{kind}</span></span>
    : <span className="template-preview" aria-hidden="true"><span className="template-icon">{icon}</span><span className="template-kind">{kind}</span></span>;
}

const fileName = (path: string) => path.split("/").filter(Boolean).pop() ?? path;
const formatBytes = (bytes: number) => `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(bytes / (bytes >= 1_000_000 ? 1_000_000 : 1_000))} ${bytes >= 1_000_000 ? "MB" : "KB"}`;
