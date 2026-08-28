import { create } from "zustand";
import { api, events, isDesktop } from "./api";
import type {
  AppConfigV1,
  BuildResult,
  EditorDocument,
  ManagedRuntimeRecordV2,
  OutlineItem,
  ProjectCompletionIndex,
  ProjectEntry,
  ProjectHandle,
  RuntimeInstallEvent,
  RuntimeEnvironment,
  RuntimeManifestV2,
  RuntimeVariant,
  ToolchainStatus,
} from "./types";
import { defaultConfig } from "./types";
import { findExistingProjectPdf } from "./projectFiles";

type AppPhase = "booting" | "setup" | "hub" | "project";
export type SidebarMode = "files" | "search";
export type BuildState = "idle" | "building" | "success" | "failure";
export type CloseDecision = "save" | "discard" | "cancel";
export interface CloseRequest {
  scope: "document" | "project" | "application";
  paths: string[];
}

const emptyToolchain: ToolchainStatus = {
  engines: {},
  latexmk: null,
  synctex: null,
  tlmgr: null,
};

const emptyCompletion: ProjectCompletionIndex = {
  labels: [],
  citations: [],
  packages: [],
  classes: [],
  inputPaths: [],
  imagePaths: [],
};

const saveTimers = new Map<string, number>();
let buildTimer: number | undefined;
let outlineTimer: number | undefined;
let stopProjectListener: (() => void) | undefined;
let closeResolver: ((decision: CloseDecision) => void) | undefined;

interface AppState {
  phase: AppPhase;
  config: AppConfigV1;
  systemToolchain: ToolchainStatus;
  activeToolchain: ToolchainStatus;
  installedRuntimes: ManagedRuntimeRecordV2[];
  activeRuntime: ManagedRuntimeRecordV2 | null;
  runtimeManifest: RuntimeManifestV2 | null;
  runtimeEnvironment: RuntimeEnvironment;
  runtimeEvent: RuntimeInstallEvent | null;
  runtimeError: string | null;
  project: ProjectHandle | null;
  entries: ProjectEntry[];
  documents: Record<string, EditorDocument>;
  tabs: string[];
  selectedPath: string | null;
  mainDocument: string | null;
  sidebarMode: SidebarMode;
  sidebarVisible: boolean;
  pdfVisible: boolean;
  settingsOpen: boolean;
  insertShelfOpen: boolean;
  problemsOpen: boolean;
  outline: OutlineItem[];
  outlineExpanded: boolean;
  outlineHeight: number;
  completion: ProjectCompletionIndex;
  buildState: BuildState;
  buildResult: BuildResult | null;
  pdfBase64: string | null;
  statusMessage: string;
  error: string | null;
  closeRequest: CloseRequest | null;
  initialize(): Promise<void>;
  chooseSystemTex(): Promise<void>;
  chooseManagedRuntime(record: ManagedRuntimeRecordV2): Promise<void>;
  installRuntime(variant: RuntimeVariant): Promise<void>;
  cancelRuntime(): Promise<void>;
  openProjectPath(path: string): Promise<void>;
  leaveProject(): Promise<boolean>;
  refreshProject(): Promise<void>;
  openDocument(path: string, line?: number): Promise<void>;
  selectDocument(path: string): void;
  closeDocument(path: string): Promise<boolean>;
  reorderTabs(active: string, over: string): void;
  moveTab(path: string, direction: -1 | 1): void;
  updateText(path: string, text: string): void;
  saveOne(path: string, overwriteConflict?: boolean): Promise<boolean>;
  saveAll(): Promise<boolean>;
  resolveConflict(path: string, action: "reload" | "keep" | "copy", copyPath?: string): Promise<void>;
  build(): Promise<void>;
  cancelBuild(): Promise<void>;
  setMainDocument(path: string): Promise<void>;
  remapEntryPaths(oldPath: string, newPath: string): void;
  updateConfig(patch: Partial<AppConfigV1>): Promise<void>;
  setSidebarMode(mode: SidebarMode): void;
  setOutlineDrawer(expanded: boolean, height?: number): void;
  setError(error: string | null): void;
  decideClose(decision: CloseDecision): void;
  prepareApplicationClose(): Promise<boolean>;
}

export const useAppStore = create<AppState>((set, get) => ({
  phase: "booting",
  config: defaultConfig,
  systemToolchain: emptyToolchain,
  activeToolchain: emptyToolchain,
  installedRuntimes: [],
  activeRuntime: null,
  runtimeManifest: null,
  runtimeEnvironment: { platform: "macOs", architecture: "x86_64" },
  runtimeEvent: null,
  runtimeError: null,
  project: null,
  entries: [],
  documents: {},
  tabs: [],
  selectedPath: null,
  mainDocument: null,
  sidebarMode: "files",
  sidebarVisible: true,
  pdfVisible: true,
  settingsOpen: false,
  insertShelfOpen: false,
  problemsOpen: false,
  outline: [],
  outlineExpanded: true,
  outlineHeight: 180,
  completion: emptyCompletion,
  buildState: "idle",
  buildResult: null,
  pdfBase64: null,
  statusMessage: "Ready",
  error: null,
  closeRequest: null,

  async initialize() {
    if (!isDesktop()) {
      const preview = new URLSearchParams(window.location.search).get("preview");
      if (preview === "workspace" || preview === "conflict" || preview === "problems") {
        const main = previewDocument("main.tex", "\\documentclass[11pt]{article}\n\\usepackage{amsmath,amssymb}\n\\title{Spectral Methods for Elliptic Operators}\n\\author{A. Researcher}\n\\begin{document}\n\\maketitle\n\\section{Introduction}\nLet $A$ be a self-adjoint operator on a Hilbert space.\n\\section{Main Result}\n\\begin{equation}\n  \\lambda_k \\sim C k^{2/n}.\n\\end{equation}\n\\subsection{Proof Strategy}\nWe combine compactness with the min-max principle.\n\\end{document}\n");
        const notes = previewDocument("sections/notes.tex", "\\section{Technical Notes}\nThe resolvent is compact.\n");
        if (preview === "conflict") main.externalChange = "modified";
        set({
          phase: "project",
          config: { ...defaultConfig, texProvider: "system" },
          project: { id: "preview-project", name: "SpectralArticle", rootPath: "/Preview/SpectralArticle", mainDocument: "main.tex" },
          entries: [
            { name: "sections", relativePath: "sections", isDirectory: true, children: [{ name: "notes.tex", relativePath: "sections/notes.tex", isDirectory: false, children: [] }] },
            { name: "figures", relativePath: "figures", isDirectory: true, children: [] },
            { name: "main.tex", relativePath: "main.tex", isDirectory: false, children: [] },
          ],
          documents: { "main.tex": main, "sections/notes.tex": notes },
          tabs: ["main.tex", "sections/notes.tex"],
          selectedPath: "main.tex",
          mainDocument: "main.tex",
          outline: [
            { relativePath: "main.tex", line: 7, title: "Introduction", level: 1 },
            { relativePath: "main.tex", line: 9, title: "Main Result", level: 1 },
            { relativePath: "main.tex", line: 13, title: "Proof Strategy", level: 2 },
          ],
          buildState: preview === "problems" ? "failure" : "idle",
          problemsOpen: preview === "problems",
          buildResult: preview === "problems" ? {
            succeeded: false,
            log: "main.tex:10: Undefined control sequence.\n",
            previewPdfPath: null,
            projectPdfPath: null,
            missingPackageFile: null,
            diagnostics: [{ primary: { severity: "error", relativePath: "main.tex", line: 10, message: "Undefined control sequence. Check the command spelling or required package." }, related: [{ severity: "error", relativePath: null, line: null, message: "Compilation stopped at the first error." }] }],
          } : null,
          statusMessage: "Browser preview",
        });
      } else if (preview === "setup") {
        set({
          phase: "setup",
          runtimeEnvironment: { platform: "macOs", architecture: "arm64" },
          runtimeManifest: { schemaVersion: 2, runtimeVersion: "2026.1", texLiveYear: 2026, assets: (["minimal", "standard", "full"] as RuntimeVariant[]).map((variant, index) => ({ variant, platform: "macOs", architecture: "arm64", downloadUrl: "https://example.invalid/runtime.zip", downloadParts: null, compressedSize: [680_000_000, 2_800_000_000, 7_200_000_000][index], installedSize: [1_100_000_000, 4_200_000_000, 9_000_000_000][index], sha256: "0".repeat(64), tools: {} })) },
          statusMessage: "Browser preview",
        });
      } else {
        set({ phase: "hub", config: defaultConfig, settingsOpen: preview === "settings", statusMessage: "Browser preview" });
      }
      return;
    }
    try {
      const [config, systemToolchain, installedRuntimes, runtimeEnvironment] = await Promise.all([
        api.loadConfig(),
        api.detectSystemTex(),
        api.installedRuntimes(),
        api.runtimeEnvironment(),
      ]);
      let activeToolchain = emptyToolchain;
      let activeRuntime: ManagedRuntimeRecordV2 | null = null;
      if (config.texProvider === "system" && Object.keys(systemToolchain.engines).length > 0) {
        activeToolchain = systemToolchain;
      } else if (config.texProvider === "managed" && config.managedRuntimeRecordPath) {
        activeRuntime = installedRuntimes.find((runtime) =>
          `${runtime.rootPath}/.lightex-runtime.json` === config.managedRuntimeRecordPath,
        ) ?? null;
        if (activeRuntime) activeToolchain = await api.runtimeToolchain(activeRuntime);
      }
      const setupComplete = Object.keys(activeToolchain.engines).length > 0;
      set({
        config,
        systemToolchain,
        activeToolchain,
        installedRuntimes,
        runtimeEnvironment,
        activeRuntime,
        phase: setupComplete ? "hub" : "setup",
      });
      api.runtimeManifest()
        .then((runtimeManifest) => set({ runtimeManifest, runtimeError: null }))
        .catch((error) => set({ runtimeError: String(error) }));
      const stopRuntime = await events.runtimeInstall((runtimeEvent) => set({ runtimeEvent }));
      window.addEventListener("beforeunload", stopRuntime, { once: true });
    } catch (error) {
      set({ phase: "setup", error: String(error), runtimeError: String(error) });
    }
  },

  async chooseSystemTex() {
    if (Object.keys(get().systemToolchain.engines).length === 0) return;
    const config = { ...get().config, texProvider: "system" as const, managedRuntimeRecordPath: null };
    await api.saveConfig(config);
    set({ config, activeToolchain: get().systemToolchain, activeRuntime: null, phase: "hub" });
  },

  async chooseManagedRuntime(record) {
    try {
      const activeToolchain = await api.runtimeToolchain(record);
      const config = {
        ...get().config,
        texProvider: "managed" as const,
        managedRuntimeRecordPath: `${record.rootPath}/.lightex-runtime.json`,
      };
      await api.saveConfig(config);
      set({ config, activeToolchain, activeRuntime: record, phase: "hub", runtimeError: null });
    } catch (error) {
      set({ runtimeError: String(error) });
    }
  },

  async installRuntime(variant) {
    const manifest = get().runtimeManifest;
    if (!manifest) return;
    set({ runtimeEvent: { stage: "checking" }, runtimeError: null });
    try {
      const record = await api.installRuntime(manifest, variant);
      set({ installedRuntimes: await api.installedRuntimes() });
      await get().chooseManagedRuntime(record);
    } catch (error) {
      const message = String(error);
      if (!message.toLowerCase().includes("cancel")) set({ runtimeError: message });
    }
  },

  async cancelRuntime() {
    await api.cancelRuntimeInstall();
  },

  async openProjectPath(path) {
    try {
      const current = get().project;
      if (current && !(await get().leaveProject())) return;
      const project = await api.openProject(path);
      const [entries, session] = await Promise.all([
        api.scanProject(project.id),
        api.loadSession(project.rootPath),
      ]);
      const mainDocument = session?.mainDocument ?? project.mainDocument;
      const existingPdf = findExistingProjectPdf(entries, mainDocument);
      set({
        phase: "project",
        project,
        entries,
        documents: {},
        tabs: [],
        selectedPath: null,
        mainDocument,
        outlineExpanded: session?.outlineExpanded ?? true,
        outlineHeight: Math.max(112, session?.outlineHeight ?? 180),
        buildResult: null,
        pdfBase64: null,
        buildState: "idle",
        error: null,
      });
      const config = {
        ...get().config,
        recentProjects: [project.rootPath, ...get().config.recentProjects.filter((item) => item !== project.rootPath)].slice(0, 12),
      };
      set({ config });
      await api.saveConfig(config);
      stopProjectListener?.();
      stopProjectListener = await events.projectChanged(() => void handleExternalProjectChange());
      const candidates = session?.openDocuments.filter((item) => hasEntry(entries, item)) ?? [];
      const initialTabs = candidates.length > 0 ? candidates : mainDocument ? [mainDocument] : [];
      for (const item of initialTabs) await get().openDocument(item);
      const selected = session?.selectedDocument;
      if (selected && get().documents[selected]) get().selectDocument(selected);
      if (existingPdf) {
        const absolutePdfPath = `${project.rootPath.replace(/\/+$/, "")}/${existingPdf}`;
        void api.readPreviewPdf(project.id, absolutePdfPath).then((pdfBase64) => {
          if (get().project?.id === project.id && !get().buildResult) {
            set({ pdfBase64, statusMessage: "Loaded existing PDF" });
          }
        }).catch((error) => {
          if (get().project?.id === project.id) set({ error: `Could not load ${existingPdf}: ${String(error)}` });
        });
      }
      void get().refreshProject();
    } catch (error) {
      set({ error: String(error) });
    }
  },

  async leaveProject() {
    const { project, documents } = get();
    if (!project) return true;
    const dirty = Object.values(documents).filter((document) => document.dirty);
    if (dirty.length > 0) {
      const decision = await requestCloseDecision("project", dirty.map((document) => document.relativePath));
      if (decision === "cancel") return false;
      if (decision === "save" && !(await get().saveAll())) return false;
    }
    await persistSession();
    stopProjectListener?.();
    stopProjectListener = undefined;
    await api.closeProject(project.id);
    set({ phase: "hub", project: null, entries: [], documents: {}, tabs: [], selectedPath: null });
    return true;
  },

  async refreshProject() {
    const project = get().project;
    if (!project) return;
    try {
      const [entries, completion] = await Promise.all([
        api.scanProject(project.id),
        api.completionIndex(project.id),
      ]);
      set({ entries, completion });
    } catch (error) {
      set({ error: String(error) });
    }
  },

  async openDocument(path, line) {
    const { project, documents, tabs } = get();
    if (!project) return;
    if (!documents[path]) {
      try {
        const snapshot = await api.openDocument(project.id, path);
        set({
          documents: {
            ...get().documents,
            [path]: { ...snapshot, dirty: false, externalChange: "none" },
          },
          tabs: tabs.includes(path) ? tabs : [...tabs, path],
        });
      } catch (error) {
        set({ error: String(error) });
        return;
      }
    }
    set({ selectedPath: path });
    await updateOutline(path);
    window.dispatchEvent(new CustomEvent("lightex:editor-jump", { detail: { path, line } }));
    void persistSession();
  },

  selectDocument(path) {
    if (!get().documents[path]) return;
    set({ selectedPath: path });
    void updateOutline(path);
    void persistSession();
  },

  async closeDocument(path) {
    const document = get().documents[path];
    if (!document) return true;
    if (document.dirty) {
      const decision = await requestCloseDecision("document", [path]);
      if (decision === "cancel") return false;
      if (decision === "save" && !(await get().saveOne(path))) return false;
    }
    const documents = { ...get().documents };
    delete documents[path];
    const tabs = get().tabs.filter((item) => item !== path);
    const oldIndex = get().tabs.indexOf(path);
    const selectedPath = get().selectedPath === path
      ? tabs[Math.min(oldIndex, tabs.length - 1)] ?? null
      : get().selectedPath;
    set({ documents, tabs, selectedPath });
    if (selectedPath) void updateOutline(selectedPath);
    void persistSession();
    return true;
  },

  reorderTabs(active, over) {
    const tabs = [...get().tabs];
    const source = tabs.indexOf(active);
    const destination = tabs.indexOf(over);
    if (source < 0 || destination < 0 || source === destination) return;
    tabs.splice(source, 1);
    tabs.splice(destination, 0, active);
    set({ tabs });
    void persistSession();
  },

  moveTab(path, direction) {
    const tabs = [...get().tabs];
    const source = tabs.indexOf(path);
    const destination = Math.max(0, Math.min(tabs.length - 1, source + direction));
    if (source < 0 || source === destination) return;
    tabs.splice(source, 1);
    tabs.splice(destination, 0, path);
    set({ tabs });
  },

  updateText(path, text) {
    const document = get().documents[path];
    if (!document || document.text === text) return;
    set({
      documents: { ...get().documents, [path]: { ...document, text, dirty: true } },
      statusMessage: "Edited",
    });
    window.clearTimeout(saveTimers.get(path));
    if (get().config.autosave && document.externalChange === "none") {
      saveTimers.set(path, window.setTimeout(() => void get().saveOne(path), 700));
    }
    window.clearTimeout(outlineTimer);
    outlineTimer = window.setTimeout(() => void updateOutline(path), 250);
    window.clearTimeout(buildTimer);
    if (get().config.automaticBuilds) {
      buildTimer = window.setTimeout(
        () => void get().build(),
        get().config.automaticBuildDelaySeconds * 1000,
      );
    }
  },

  async saveOne(path, overwriteConflict = false) {
    const project = get().project;
    const document = get().documents[path];
    if (!project || !document || (!document.dirty && !overwriteConflict)) return true;
    if (document.externalChange !== "none" && !overwriteConflict) return false;
    try {
      const result = await api.saveDocument(
        project.id,
        path,
        document.text,
        document.revision,
        overwriteConflict,
      );
      if (result.status === "saved") {
        set({
          documents: {
            ...get().documents,
            [path]: { ...document, revision: result.revision, dirty: false, externalChange: "none" },
          },
          statusMessage: `Saved ${path}`,
        });
        return true;
      }
      set({
        documents: {
          ...get().documents,
          [path]: { ...document, externalChange: result.status === "missing" ? "deleted" : "modified" },
        },
      });
      return false;
    } catch (error) {
      set({ error: `Could not save ${path}: ${String(error)}` });
      return false;
    }
  },

  async saveAll() {
    for (const path of get().tabs) {
      if (!(await get().saveOne(path))) return false;
    }
    return true;
  },

  async resolveConflict(path, action, copyPath) {
    const project = get().project;
    const document = get().documents[path];
    if (!project || !document) return;
    if (action === "keep") {
      await get().saveOne(path, true);
      return;
    }
    if (action === "copy") {
      if (!copyPath) return;
      try {
        await api.saveDocumentCopy(copyPath, document.text);
        if (document.externalChange === "deleted") {
          set({ documents: { ...get().documents, [path]: { ...document, dirty: false } } });
          await get().closeDocument(path);
          return;
        }
      } catch (error) {
        set({ error: `Could not save a copy: ${String(error)}` });
        return;
      }
    }
    try {
      const snapshot = await api.openDocument(project.id, path);
      set({ documents: { ...get().documents, [path]: { ...snapshot, dirty: false, externalChange: "none" } } });
    } catch (error) {
      set({ error: String(error) });
    }
  },

  async build() {
    const { project, mainDocument, activeToolchain, config } = get();
    if (!project || !mainDocument || get().buildState === "building") return;
    if (Object.values(get().documents).some((document) => document.externalChange !== "none")) {
      set({ error: "Resolve external file changes before compiling." });
      return;
    }
    if (!(await get().saveAll())) {
      set({ error: "Compilation stopped because a document could not be saved." });
      return;
    }
    const engineName = engineExecutable(config.latexEngine);
    const executable = config.buildTool === "latexmk"
      ? activeToolchain.latexmk
      : activeToolchain.engines[engineName];
    if (!executable) {
      set({ error: `The selected build tool is unavailable: ${config.buildTool === "latexmk" ? "latexmk" : engineName}` });
      return;
    }
    set({ buildState: "building", statusMessage: "Compiling…", error: null });
    try {
      const result = await api.build({
        projectId: project.id,
        entryFile: mainDocument,
        engine: config.latexEngine,
        tool: config.buildTool,
        executablePath: executable.path,
        searchDirectories: toolDirectories(activeToolchain),
      });
      let pdfBase64: string | null = null;
      if (result.previewPdfPath) pdfBase64 = await api.readPreviewPdf(project.id, result.previewPdfPath);
      set({
        buildResult: result,
        pdfBase64,
        buildState: result.succeeded ? "success" : "failure",
        statusMessage: result.succeeded ? "Build succeeded" : "Build failed",
        problemsOpen: !result.succeeded && config.showProblemsOnFailure,
      });
    } catch (error) {
      const message = String(error);
      if (message.toLowerCase().includes("cancel")) set({ buildState: "idle", statusMessage: "Build cancelled" });
      else set({ buildState: "failure", statusMessage: "Build failed", error: message, problemsOpen: true });
    }
  },

  async cancelBuild() {
    if (get().buildState !== "building") return;
    set({ statusMessage: "Cancelling build…" });
    await api.cancelBuild();
  },

  async setMainDocument(path) {
    set({ mainDocument: path });
    await persistSession();
  },

  remapEntryPaths(oldPath, newPath) {
    const remap = (value: string) => value === oldPath
      ? newPath
      : value.startsWith(`${oldPath}/`) ? `${newPath}${value.slice(oldPath.length)}` : value;
    const documents: Record<string, EditorDocument> = {};
    for (const [path, document] of Object.entries(get().documents)) {
      const next = remap(path);
      documents[next] = { ...document, relativePath: next };
    }
    set({
      documents,
      tabs: get().tabs.map(remap),
      selectedPath: get().selectedPath ? remap(get().selectedPath!) : null,
      mainDocument: get().mainDocument ? remap(get().mainDocument!) : null,
    });
    void persistSession();
  },

  async updateConfig(patch) {
    const config = { ...get().config, ...patch };
    set({ config });
    if (isDesktop()) await api.saveConfig(config);
  },

  setSidebarMode(sidebarMode) { set({ sidebarMode }); },
  setOutlineDrawer(outlineExpanded, height = get().outlineHeight) {
    set({ outlineExpanded, outlineHeight: Math.max(112, Math.round(height)) });
    void persistSession();
  },
  setError(error) { set({ error }); },
  decideClose(decision) {
    const resolver = closeResolver;
    closeResolver = undefined;
    set({ closeRequest: null });
    resolver?.(decision);
  },
  async prepareApplicationClose() {
    const dirty = Object.values(get().documents).filter((document) => document.dirty);
    if (dirty.length > 0) {
      const decision = await requestCloseDecision("application", dirty.map((document) => document.relativePath));
      if (decision === "cancel") return false;
      if (decision === "save" && !(await get().saveAll())) return false;
    }
    await persistSession();
    return true;
  },
}));

function requestCloseDecision(scope: CloseRequest["scope"], paths: string[]): Promise<CloseDecision> {
  if (closeResolver) {
    closeResolver("cancel");
  }
  useAppStore.setState({ closeRequest: { scope, paths } });
  return new Promise((resolve) => { closeResolver = resolve; });
}

async function updateOutline(path: string) {
  const document = useAppStore.getState().documents[path];
  if (!document) return;
  try {
    const outline = await api.outline(path, document.text);
    if (useAppStore.getState().selectedPath === path) useAppStore.setState({ outline });
  } catch {
    // The editor remains usable while a stale outline task is discarded.
  }
}

async function persistSession() {
  const state = useAppStore.getState();
  if (!state.project || !isDesktop()) return;
  await api.saveSession({
    schemaVersion: 2,
    projectPath: state.project.rootPath,
    mainDocument: state.mainDocument,
    openDocuments: state.tabs,
    selectedDocument: state.selectedPath,
    outlineExpanded: state.outlineExpanded,
    outlineHeight: Math.round(state.outlineHeight),
  });
}

async function handleExternalProjectChange() {
  const state = useAppStore.getState();
  const project = state.project;
  if (!project) return;
  await state.refreshProject();
  for (const path of state.tabs) {
    const current = useAppStore.getState().documents[path];
    if (!current) continue;
    try {
      const disk = await api.documentRevision(project.id, path);
      if (!disk) {
        const identifier = current.revision.fileIdentifier;
        const relocated = identifier ? await api.locateDocument(project.id, identifier) : null;
        if (relocated && relocated !== path) {
          useAppStore.getState().remapEntryPaths(path, relocated);
          const moved = useAppStore.getState().documents[relocated];
          const movedDisk = await api.documentRevision(project.id, relocated);
          if (moved && movedDisk && movedDisk.contentHash === moved.revision.contentHash) {
            useAppStore.setState({
              documents: { ...useAppStore.getState().documents, [relocated]: { ...moved, revision: movedDisk } },
            });
          }
          continue;
        }
        useAppStore.setState({
          documents: { ...useAppStore.getState().documents, [path]: { ...current, externalChange: "deleted" } },
        });
      } else if (disk.contentHash !== current.revision.contentHash) {
        if (current.dirty) {
          useAppStore.setState({
            documents: { ...useAppStore.getState().documents, [path]: { ...current, externalChange: "modified" } },
          });
        } else {
          const snapshot = await api.openDocument(project.id, path);
          useAppStore.setState({
            documents: { ...useAppStore.getState().documents, [path]: { ...snapshot, dirty: false, externalChange: "none" } },
          });
        }
      }
    } catch {
      // A later debounced file-system event retries the read.
    }
  }
}

function hasEntry(entries: ProjectEntry[], path: string): boolean {
  return entries.some((entry) => entry.relativePath === path || hasEntry(entry.children, path));
}

function engineExecutable(engine: AppConfigV1["latexEngine"]): string {
  if (engine === "xeLaTex") return "xelatex";
  if (engine === "luaLaTex") return "lualatex";
  return "pdflatex";
}

function toolDirectories(status: ToolchainStatus): string[] {
  const paths = [
    ...Object.values(status.engines).flatMap((tool) => tool ? [tool.path] : []),
    status.latexmk?.path,
    status.synctex?.path,
    status.tlmgr?.path,
  ].filter((path): path is string => Boolean(path));
  return Array.from(new Set(paths.map((path) => path.slice(0, path.lastIndexOf("/")))));
}

function previewDocument(relativePath: string, text: string): EditorDocument {
  return {
    relativePath,
    text,
    dirty: false,
    externalChange: "none",
    revision: { modificationUnixMs: 0, fileSize: text.length, fileIdentifier: relativePath, contentHash: relativePath },
  };
}
