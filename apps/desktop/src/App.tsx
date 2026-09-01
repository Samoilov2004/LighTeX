import { useEffect, useRef } from "react";
import { AlertCircle, CheckCircle2, Undo2, X } from "lucide-react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { events, isDesktop } from "./api";
import { useAppStore } from "./store";
import { ProjectHub } from "./components/ProjectHub";
import { RuntimeSetup } from "./components/RuntimeSetup";
import { SettingsPanel } from "./components/SettingsPanel";
import { Workspace } from "./components/Workspace";
import { useModalFocus } from "./useModalFocus";

export default function App() {
  const phase = useAppStore((state) => state.phase);
  const initialize = useAppStore((state) => state.initialize);
  const settingsOpen = useAppStore((state) => state.settingsOpen);
  const error = useAppStore((state) => state.error);
  const closeRequest = useAppStore((state) => state.closeRequest);
  const notice = useAppStore((state) => state.notice);
  const undoVersion = useAppStore((state) => state.undoVersion);
  const initialized = useRef(false);
  useEffect(() => {
    if (!notice) return;
    const timer = window.setTimeout(() => useAppStore.setState({ notice: null }), undoVersion ? 8_000 : 4_000);
    return () => window.clearTimeout(timer);
  }, [notice, undoVersion?.id]);
  useEffect(() => {
    if (initialized.current) return;
    initialized.current = true;
    document.documentElement.dataset.platform = navigator.platform.toLowerCase().includes("mac") ? "macos" : "linux";
    void initialize();
  }, []);
  useEffect(() => {
    const macOS = navigator.platform.toLowerCase().includes("mac");
    document.documentElement.dataset.fullscreen = "false";
    if (!isDesktop() || !macOS) return;
    const appWindow = getCurrentWindow();
    let active = true;
    let revision = 0;
    let unlisten: (() => void) | undefined;
    const updateFullscreen = async () => {
      const request = ++revision;
      try {
        const fullscreen = await appWindow.isFullscreen();
        if (active && request === revision) document.documentElement.dataset.fullscreen = String(fullscreen);
      } catch {
        // Keep the regular titlebar spacing when the window state is unavailable.
      }
    };
    const onResize = () => { void updateFullscreen(); };
    window.addEventListener("resize", onResize);
    void appWindow.onResized(onResize).then((value) => { unlisten = value; }).catch(() => undefined);
    void updateFullscreen();
    return () => {
      active = false;
      revision += 1;
      window.removeEventListener("resize", onResize);
      unlisten?.();
    };
  }, []);
  useEffect(() => {
    if (!isDesktop()) return;
    let unlisten: (() => void) | undefined;
    void events.menuAction((action) => {
      if (action === "settings") useAppStore.setState({ settingsOpen: true });
      window.dispatchEvent(new CustomEvent("lightex:menu-action", { detail: action }));
    }).then((value) => { unlisten = value; });
    return () => unlisten?.();
  }, []);
  useEffect(() => {
    const settingsShortcut = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        if (useAppStore.getState().closeRequest) useAppStore.getState().decideClose("cancel");
        else if (useAppStore.getState().settingsOpen) useAppStore.setState({ settingsOpen: false });
      }
      const command = navigator.platform.toLowerCase().includes("mac") ? event.metaKey : event.ctrlKey;
      if (command && event.key === ",") {
        event.preventDefault();
        useAppStore.setState({ settingsOpen: true });
      }
    };
    window.addEventListener("keydown", settingsShortcut);
    return () => window.removeEventListener("keydown", settingsShortcut);
  }, []);
  useEffect(() => {
    if (!isDesktop()) return;
    const appWindow = getCurrentWindow();
    let closing = false;
    let stopped = false;
    let unlisten: (() => void) | undefined;
    void appWindow.onCloseRequested(async (event) => {
      event.preventDefault();
      if (closing) return;
      closing = true;
      try {
        const canClose = await useAppStore.getState().prepareApplicationClose();
        if (canClose && !stopped) await appWindow.destroy();
      } catch (error) {
        useAppStore.getState().setError(`Could not close LighTex: ${String(error)}`);
      } finally {
        if (!stopped) closing = false;
      }
    }).then((value) => { unlisten = value; });
    return () => { stopped = true; unlisten?.(); };
  }, []);
  return (
    <div className="app-shell">
      {phase === "booting" && <div className="boot-view" aria-live="polite"><div className="spinner" /><span>Starting LighTex…</span></div>}
      {phase === "setup" && <RuntimeSetup />}
      {phase === "hub" && <ProjectHub />}
      {phase === "project" && <Workspace />}
      {settingsOpen && phase !== "setup" && <SettingsPanel onClose={() => useAppStore.setState({ settingsOpen: false })} />}
      {closeRequest && <UnsavedChangesDialog />}
      {notice && <div className="success-toast" role="status"><CheckCircle2 size={16} aria-hidden="true" /><span>{notice}</span>{undoVersion && <button className="toast-action" onClick={() => void useAppStore.getState().undoLastRestore()}><Undo2 size={13} />Undo</button>}<button className="icon-button" onClick={() => useAppStore.setState({ notice: null })} aria-label="Dismiss notification"><X size={14} /></button></div>}
      {error && <div className="error-toast" role="alert"><AlertCircle size={16} /><span>{error}</span><button className="icon-button" onClick={() => useAppStore.getState().setError(null)} aria-label="Dismiss error"><X size={14} /></button></div>}
    </div>
  );
}

function UnsavedChangesDialog() {
  const request = useAppStore((state) => state.closeRequest)!;
  const decide = useAppStore((state) => state.decideClose);
  const multiple = request.paths.length > 1;
  const title = request.scope === "application" ? "Save changes before quitting?" : request.scope === "project" ? "Save changes before closing the project?" : `Save changes to ${request.paths[0]}?`;
  const dialog = useModalFocus<HTMLElement>(() => decide("cancel"));
  return (
    <div className="modal-layer close-layer" role="presentation">
      <section ref={dialog} className="native-dialog unsaved-dialog" role="alertdialog" aria-modal="true" aria-labelledby="unsaved-title" aria-describedby="unsaved-description">
        <h2 id="unsaved-title">{title}</h2>
        <p id="unsaved-description">Unsaved edits will be lost if you choose Don’t Save.</p>
        {multiple && <ul className="dirty-file-list">{request.paths.map((path) => <li key={path}>{path}</li>)}</ul>}
        <div className="dialog-actions split-actions">
          <button className="danger-text-button" onClick={() => decide("discard")}>Don’t Save</button>
          <span />
          <button className="secondary-button" onClick={() => decide("cancel")} autoFocus>Cancel</button>
          <button className="primary-button" onClick={() => decide("save")}>{multiple ? "Save All" : "Save"}</button>
        </div>
      </section>
    </div>
  );
}
