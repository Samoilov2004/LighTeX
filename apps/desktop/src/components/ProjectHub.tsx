import { useEffect, useRef, useState } from "react";
import { ChevronLeft, ChevronRight, FilePlus2, Folder, FolderOpen, LayoutTemplate, Settings, Trash2 } from "lucide-react";
import { ask, open } from "@tauri-apps/plugin-dialog";
import { desktopDir } from "@tauri-apps/api/path";
import { api, isDesktop } from "../api";
import { fallbackBundledTemplatePreview, fallbackBundledTemplates } from "../bundledTemplates";
import { useAppStore } from "../store";
import type {
  BundledTemplateCategory,
  BundledTemplateManifestV2,
  PersonalTemplateManifestV2,
  TemplateCodeLanguage,
  TemplateCodeStyle,
  TemplateInstantiationOptions,
  TemplateReview,
} from "../types";
import { renderFirstPagePreview } from "../pdf";
import { useModalFocus } from "../useModalFocus";
import appIcon from "../assets/AppIcon128.png";
import { WindowDragRegion } from "./WindowDragRegion";

type HubScreen =
  | { kind: "projects" }
  | { kind: "templateDetail"; template: TemplateSelection };

type TemplateSelection =
  | { kind: "bundled"; template: BundledTemplateManifestV2 }
  | { kind: "personal"; template: PersonalTemplateManifestV2 };

interface TemplateDraft {
  name: string;
  parent: string;
  codeStyle: TemplateCodeStyle;
  codeLanguages: TemplateCodeLanguage[];
}

const categoryLabels: Record<BundledTemplateCategory, string> = {
  essentials: "Essentials",
  academic: "Academic",
  slides: "Slides",
};

const codeLanguageLabels: Record<TemplateCodeLanguage, string> = {
  python: "Python",
  sql: "SQL",
  cpp: "C/C++",
  javaScript: "JavaScript / TypeScript",
  rust: "Rust",
  java: "Java",
  shell: "Shell",
};

const previewCache = new Map<string, string>();

export function ProjectHub() {
  const config = useAppStore((state) => state.config);
  const openProject = useAppStore((state) => state.openProjectPath);
  const updateConfig = useAppStore((state) => state.updateConfig);
  const [createEmpty, setCreateEmpty] = useState(false);
  const [personal, setPersonal] = useState<PersonalTemplateManifestV2[]>([]);
  const [bundled, setBundled] = useState<BundledTemplateManifestV2[]>(fallbackBundledTemplates);
  const [review, setReview] = useState<TemplateReview | null>(null);
  const [hubError, setHubError] = useState<string | null>(null);
  const [screen, setScreen] = useState<HubScreen>({ kind: "projects" });
  const [desktop, setDesktop] = useState(isDesktop() ? "" : "/Users/Preview/Desktop");
  const [drafts, setDrafts] = useState<Record<string, TemplateDraft>>({});

  useEffect(() => {
    if (!isDesktop()) return;
    void api.listPersonalTemplates().then(setPersonal).catch((error) => setHubError(String(error)));
    void api.listBundledTemplates().then(setBundled).catch((error) => setHubError(String(error)));
    void desktopDir().then((path) => {
      setDesktop(path);
      setDrafts((current) => Object.fromEntries(
        Object.entries(current).map(([key, draft]) => [key, draft.parent ? draft : { ...draft, parent: path }]),
      ));
    }).catch(() => {});
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
    const confirmed = await ask("Move the personal template “" + template.name + "” to Trash? Projects already created from it are not affected.", {
      title: "Remove Personal Template",
      kind: "warning",
      okLabel: "Move to Trash",
      cancelLabel: "Cancel",
    });
    if (!confirmed) return;
    try {
      await api.removePersonalTemplate(template.id);
      setPersonal(await api.listPersonalTemplates());
      if (screen.kind === "templateDetail" && screen.template.kind === "personal" && screen.template.template.id === template.id) {
        const fallback = bundled.find((item) => item.id === "course-notes") ?? bundled[0];
        if (fallback) selectTemplate({ kind: "bundled", template: fallback });
        else setScreen({ kind: "projects" });
      }
    } catch (error) { setHubError(String(error)); }
  };

  const selectTemplate = (selection: TemplateSelection) => {
    const key = templateKey(selection);
    setDrafts((current) => current[key] ? current : {
      ...current,
      [key]: createDraft(selection, desktop),
    });
    setScreen({ kind: "templateDetail", template: selection });
  };

  const showTemplateBuilder = () => {
    const template = bundled.find((item) => item.id === "course-notes") ?? bundled[0];
    if (template) selectTemplate({ kind: "bundled", template });
    else if (personal[0]) selectTemplate({ kind: "personal", template: personal[0] });
    else setHubError("No templates are available.");
  };

  useEffect(() => {
    const menu = (event: Event) => {
      const action = (event as CustomEvent<string>).detail;
      if (action === "new-project") setCreateEmpty(true);
      if (action === "open-project") void chooseFolder();
    };
    window.addEventListener("lightex:menu-action", menu);
    return () => window.removeEventListener("lightex:menu-action", menu);
  }, []);

  const detailSelection = screen.kind === "templateDetail" ? screen.template : null;
  const detailKey = detailSelection ? templateKey(detailSelection) : null;
  const detailDraft = detailKey && detailSelection
    ? drafts[detailKey] ?? createDraft(detailSelection, desktop)
    : null;

  return (
    <main className={"hub-view " + (screen.kind === "templateDetail" ? "template-detail-view" : "")}>
      <div className="hub-toolbar">
        <WindowDragRegion />
        {screen.kind === "templateDetail" && <strong className="hub-toolbar-title">New from Template</strong>}
        <button className="icon-button" onClick={() => useAppStore.setState({ settingsOpen: true })} aria-label="Open Settings" title="Settings"><Settings size={16} /></button>
      </div>
      {screen.kind === "projects" && (
        <ProjectsScreen
          config={config}
          openProject={openProject}
          chooseFolder={chooseFolder}
          clearRecent={clearRecent}
          onNewEmpty={() => setCreateEmpty(true)}
          onShowTemplates={showTemplateBuilder}
        />
      )}
      {detailSelection && detailDraft && detailKey && (
        <TemplateDetailScreen
          selection={detailSelection}
          draft={detailDraft}
          bundled={bundled}
          personal={personal}
          onChange={(next) => setDrafts((current) => ({ ...current, [detailKey]: next }))}
          onBack={() => setScreen({ kind: "projects" })}
          onSelect={selectTemplate}
          onReviewTemplate={reviewTemplate}
          onRemoveTemplate={removeTemplate}
          onCreated={openProject}
          onError={setHubError}
        />
      )}
      {createEmpty && <CreateEmptyProjectDialog onClose={() => setCreateEmpty(false)} onCreated={openProject} />}
      {review && <TemplateReviewDialog review={review} onClose={() => setReview(null)} onCreated={async () => {
        setReview(null);
        setPersonal(await api.listPersonalTemplates());
      }} />}
      {hubError && <div className="error-toast" role="alert"><span>{hubError}</span><button className="icon-button" onClick={() => setHubError(null)} aria-label="Dismiss error">×</button></div>}
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

function TemplateDetailScreen({ selection, draft, bundled, personal, onChange, onBack, onSelect, onReviewTemplate, onRemoveTemplate, onCreated, onError }: {
  selection: TemplateSelection;
  draft: TemplateDraft;
  bundled: BundledTemplateManifestV2[];
  personal: PersonalTemplateManifestV2[];
  onChange(draft: TemplateDraft): void;
  onBack(): void;
  onSelect(selection: TemplateSelection): void;
  onReviewTemplate(): Promise<void>;
  onRemoveTemplate(template: PersonalTemplateManifestV2): Promise<void>;
  onCreated(path: string): Promise<void>;
  onError(error: string): void;
}) {
  const [creating, setCreating] = useState(false);
  const [previewMode, setPreviewMode] = useState<"readable" | "fullPage">("readable");
  const rail = useRef<HTMLDivElement>(null);
  const templateId = selection.template.id;
  const templateName = selection.template.name;
  const configurable = selection.kind === "bundled" && selection.template.codeStyles.length > 0;
  const codeStyle = configurable ? draft.codeStyle : null;
  const railSelections: TemplateSelection[] = [
    ...personal.map((template) => ({ kind: "personal" as const, template })),
    ...bundled.map((template) => ({ kind: "bundled" as const, template })),
  ];
  const fileSummary = selection.kind === "bundled" && selection.template.id === "course-notes"
    ? "main.tex · notes.sty · latexmkrc · Makefile"
    : selection.kind === "bundled"
      ? selection.template.entry
      : selection.template.mainDocument ?? "Project template";

  const chooseLocation = async () => {
    if (!isDesktop()) return;
    const selected = await open({ directory: true, multiple: false, title: "Choose Project Location", defaultPath: draft.parent || undefined });
    if (typeof selected === "string") onChange({ ...draft, parent: selected });
  };

  const submit = async () => {
    if (!draft.name.trim() || !draft.parent || creating) return;
    setCreating(true);
    try {
      let path: string;
      if (selection.kind === "personal") {
        path = await api.createProjectFromPersonalTemplate(selection.template.id, draft.parent, draft.name.trim());
      } else {
        const options: TemplateInstantiationOptions | null = configurable ? {
          codeStyle: draft.codeStyle,
          codeLanguages: draft.codeStyle === "none" ? [] : draft.codeLanguages,
        } : null;
        await useAppStore.getState().updateConfig({ latexEngine: selection.template.engine });
        path = await api.createProjectFromTemplate(draft.parent, draft.name.trim(), selection.template.id, options);
      }
      await onCreated(path);
    } catch (error) {
      onError(String(error));
      setCreating(false);
    }
  };

  return <div className="template-detail">
    <section className="template-detail-preview-column" aria-label={templateName + " preview and template selection"}>
      <div className="template-preview-mode" role="group" aria-label="Preview size">
        <button type="button" className={previewMode === "readable" ? "selected" : ""} aria-pressed={previewMode === "readable"} onClick={() => setPreviewMode("readable")}>Readable</button>
        <button type="button" className={previewMode === "fullPage" ? "selected" : ""} aria-pressed={previewMode === "fullPage"} onClick={() => setPreviewMode("fullPage")}>Full Page</button>
      </div>
      <div className={"template-document-preview " + previewMode}>
        <div className="template-document-page">
          {selection.kind === "bundled"
            ? <BundledTemplateImage template={selection.template} style={codeStyle} />
            : <PersonalTemplateImage template={selection.template} />}
        </div>
        <div className="template-preview-pager" aria-label="Template preview page">
          <button className="icon-button" disabled aria-label="Previous preview page"><ChevronLeft size={15} /></button>
          <span>1 / 1</span>
          <button className="icon-button" disabled aria-label="Next preview page"><ChevronRight size={15} /></button>
        </div>
      </div>
      <section className="template-rail" aria-label="Templates">
        <button type="button" className="template-rail-arrow previous" aria-label="Scroll templates left" onClick={() => rail.current?.scrollBy({ left: -300 })}><ChevronLeft size={17} /></button>
        <div ref={rail} className="template-rail-strip">{railSelections.map((item) => {
          const key = templateKey(item);
          const selected = key === templateKey(selection);
          const category = item.kind === "bundled" ? categoryLabels[item.template.category] : "Yours";
          return <div className={"template-rail-item " + (selected ? "selected" : "")} key={key}>
            <button type="button" className="template-rail-select" aria-pressed={selected} onClick={() => onSelect(item)}>
              <span className="template-rail-preview">{item.kind === "bundled"
                ? <BundledTemplateImage template={item.template} style={item.template.defaultCodeStyle} />
                : <PersonalTemplateImage template={item.template} />}</span>
              <strong>{item.template.name}</strong>
              <small>{category}</small>
            </button>
            {item.kind === "personal" && <button type="button" className="icon-button template-rail-remove" aria-label={"Remove " + item.template.name} onClick={() => void onRemoveTemplate(item.template)}><Trash2 size={12} /></button>}
          </div>;
        })}
          <button type="button" className="template-rail-create" onClick={() => void onReviewTemplate()}><FilePlus2 size={18} /><span>Save as Template…</span><small>Yours</small></button>
        </div>
        <button type="button" className="template-rail-arrow next" aria-label="Scroll templates right" onClick={() => rail.current?.scrollBy({ left: 300 })}><ChevronRight size={17} /></button>
      </section>
    </section>
    <form className="template-detail-form" onSubmit={(event) => { event.preventDefault(); void submit(); }}>
      <div className="template-form-scroll">
        <label className="template-form-field">
          <span>Project Name</span>
          <input value={draft.name} onChange={(event) => onChange({ ...draft, name: event.target.value })} autoFocus />
        </label>
        <div className="template-form-field">
          <span>Location</span>
          <div className="template-location">
            <span title={draft.parent}><Folder size={15} aria-hidden="true" />{draft.parent ? fileName(draft.parent) : "Choose a folder"}</span>
            <button type="button" className="secondary-button" onClick={() => void chooseLocation()}>Choose…</button>
          </div>
        </div>
        {configurable && <>
          <fieldset className="template-option-group code-style-options">
            <legend>Code Style</legend>
            <div>{selection.template.codeStyles.map((style) => (
              <label className={"code-style-option " + (draft.codeStyle === style ? "selected" : "")} key={style}>
                <input className="sr-only" type="radio" name="code-style" value={style} checked={draft.codeStyle === style} onChange={() => onChange({ ...draft, codeStyle: style })} />
                <CodeStyleSample style={style} />
                <span>{style === "none" ? "None" : style === "strict" ? "Strict" : "Colorful"}</span>
              </label>
            ))}</div>
          </fieldset>
          <fieldset className="template-option-group code-language-options" disabled={draft.codeStyle === "none"}>
            <legend>Code Languages</legend>
            <div>{selection.template.codeLanguages.map((language) => {
              const selected = draft.codeLanguages.includes(language);
              return <label className={selected ? "selected" : ""} key={language}>
                <input className="sr-only" type="checkbox" checked={selected} onChange={() => onChange({
                  ...draft,
                  codeLanguages: selected
                    ? draft.codeLanguages.filter((item) => item !== language)
                    : [...draft.codeLanguages, language],
                })} />
                {codeLanguageLabels[language]}
              </label>;
            })}</div>
          </fieldset>
        </>}
        <p className="template-file-summary">{fileSummary}</p>
      </div>
      <div className="template-detail-actions">
        <button type="button" className="secondary-button" onClick={onBack} disabled={creating}>Back</button>
        <button className="primary-button" disabled={!draft.name.trim() || !draft.parent || creating}>{creating ? "Creating…" : "Create Project"}</button>
      </div>
    </form>
  </div>;
}

function CodeStyleSample({ style }: { style: TemplateCodeStyle }) {
  return <span className={"code-style-sample " + style} aria-hidden="true">
    <code><b>def</b> add(a, b):</code>
    <code>  <b>return</b> a + b</code>
    <code className="sample-secondary">SELECT AVG(x)</code>
  </span>;
}

function BundledTemplateImage({ template, style }: { template: BundledTemplateManifestV2; style?: TemplateCodeStyle | null }) {
  const preview = useBundledPreview(template, style);
  return preview ? <img src={preview} alt={template.name + " first-page preview"} /> : <span className="template-preview-loading">Loading preview…</span>;
}

function useBundledPreview(template: BundledTemplateManifestV2, style?: TemplateCodeStyle | null) {
  const key = template.id + ":" + (style ?? "default");
  const fallback = fallbackBundledTemplatePreview(template.id, style);
  const [preview, setPreview] = useState<string | null>(() => previewCache.get(key) ?? fallback);
  useEffect(() => {
    const cached = previewCache.get(key);
    if (cached) {
      setPreview(cached);
      return;
    }
    setPreview(fallback);
    if (!isDesktop()) return;
    let active = true;
    void api.bundledTemplatePreview(template.id, style ?? null).then((value) => {
      if (!active) return;
      const source = "data:image/png;base64," + value;
      previewCache.set(key, source);
      setPreview(source);
    }).catch(() => {});
    return () => { active = false; };
  }, [fallback, key, style, template.id]);
  return preview;
}

function PersonalTemplateImage({ template }: { template: PersonalTemplateManifestV2 }) {
  const [preview, setPreview] = useState<string | null>(null);
  useEffect(() => {
    if (!template.preview || !isDesktop()) return;
    void api.personalTemplatePreview(template.id).then((value) => setPreview(value ? "data:image/png;base64," + value : null));
  }, [template.id, template.preview]);
  return preview
    ? <img src={preview} alt={template.name + " first-page preview"} />
    : <span className="personal-template-fallback"><LayoutTemplate size={34} strokeWidth={1.45} aria-hidden="true" /><small>Personal Template</small></span>;
}

function CreateEmptyProjectDialog({ onClose, onCreated }: { onClose(): void; onCreated(path: string): Promise<void> }) {
  const [name, setName] = useState("Untitled");
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
      const path = await api.createProject(parent, name.trim());
      onClose();
      await onCreated(path);
    } catch (reason) { setError(String(reason)); }
  };
  return <div className="modal-layer" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <form ref={dialog} className="native-dialog" role="dialog" aria-modal="true" aria-labelledby="create-project-title" onSubmit={(event) => { event.preventDefault(); void submit(); }}>
      <h2 id="create-project-title">New Empty Project</h2>
      <label><span>Name</span><input value={name} onChange={(event) => setName(event.target.value)} autoFocus /></label>
      <label><span>Location</span><div className="path-picker"><input value={parent} readOnly placeholder="Choose a folder" /><button type="button" className="secondary-button" onClick={() => void choose()}>Choose…</button></div></label>
      {error && <p className="inline-error" role="alert">{error}</p>}
      <div className="dialog-actions"><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button className="primary-button" disabled={!name.trim() || !parent}>Create</button></div>
    </form>
  </div>;
}

function TemplateReviewDialog({ review, onClose, onCreated }: { review: TemplateReview; onClose(): void; onCreated(): Promise<void> }) {
  const [name, setName] = useState(fileName(review.sourcePath) + " Template");
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
        <ReviewList title={"Included · " + review.includedFiles.length} files={review.includedFiles} />
        <ReviewList title={"Excluded · " + review.excludedFiles.length} files={review.excludedFiles} muted />
      </div>
      <p className="review-note">Secrets, private keys, .env, Git data, caches, build output, and generated LaTeX files are excluded automatically. Included size: {formatBytes(review.totalSize)}.</p>
      {error && <p className="inline-error" role="alert">{error}</p>}
      <div className="dialog-actions"><button className="secondary-button" onClick={onClose} disabled={saving}>Cancel</button><button className="primary-button" onClick={() => void submit()} disabled={!name.trim() || saving}>{saving ? "Saving…" : "Create Template"}</button></div>
    </section>
  </div>;
}

function ReviewList({ title, files, muted = false }: { title: string; files: string[]; muted?: boolean }) {
  return <section className={muted ? "review-list muted" : "review-list"}><strong>{title}</strong><div>{files.length === 0 ? <small>None</small> : files.slice(0, 80).map((file) => <code key={file}>{file}</code>)}</div></section>;
}

function createDraft(selection: TemplateSelection, parent: string): TemplateDraft {
  if (selection.kind === "personal") {
    return { name: selection.template.name, parent, codeStyle: "strict", codeLanguages: [] };
  }
  return {
    name: selection.template.name,
    parent,
    codeStyle: selection.template.defaultCodeStyle ?? "strict",
    codeLanguages: [...(selection.template.defaultCodeLanguages ?? [])],
  };
}

const templateKey = (selection: TemplateSelection) => selection.kind + ":" + selection.template.id;
const fileName = (path: string) => path.split("/").filter(Boolean).pop() ?? path;
const formatBytes = (bytes: number) => new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(bytes / (bytes >= 1_000_000 ? 1_000_000 : 1_000)) + " " + (bytes >= 1_000_000 ? "MB" : "KB");
