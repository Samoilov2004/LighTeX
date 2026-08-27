import { useEffect, useRef, useState } from "react";
import { Check, Download, ExternalLink, FolderOpen, HardDrive, Trash2, X } from "lucide-react";
import { ask } from "@tauri-apps/plugin-dialog";
import { openUrl } from "@tauri-apps/plugin-opener";
import { api, isDesktop } from "../api";
import { useAppStore } from "../store";
import type { AppUpdateInfo, LatexEngine, BuildTool, InstalledRuntime, StorageUsage } from "../types";

type SettingsTab = "general" | "editor" | "latex";

export function SettingsPanel({ onClose }: { onClose(): void }) {
  const [tab, setTab] = useState<SettingsTab>("general");
  const config = useAppStore((state) => state.config);
  const update = useAppStore((state) => state.updateConfig);
  const system = useAppStore((state) => state.systemToolchain);
  const installed = useAppStore((state) => state.installedRuntimes);
  const chooseSystem = useAppStore((state) => state.chooseSystemTex);
  const chooseManaged = useAppStore((state) => state.chooseManagedRuntime);
  const installRuntime = useAppStore((state) => state.installRuntime);
  const manifest = useAppStore((state) => state.runtimeManifest);
  const [inventory, setInventory] = useState<InstalledRuntime[]>([]);
  const [usage, setUsage] = useState<StorageUsage | null>(null);
  const [updateInfo, setUpdateInfo] = useState<AppUpdateInfo | null>(null);
  const [activity, setActivity] = useState<string | null>(null);
  const panel = useRef<HTMLElement>(null);
  const refreshStorage = async () => {
    const [nextInventory, nextUsage] = await Promise.all([
      api.runtimeInventory(config.managedRuntimeRecordPath),
      api.storageUsage(),
    ]);
    setInventory(nextInventory);
    setUsage(nextUsage);
  };
  useEffect(() => {
    const key = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [onClose]);
  useEffect(() => { panel.current?.querySelector<HTMLElement>("button")?.focus(); }, []);
  useEffect(() => { if (isDesktop()) void refreshStorage().catch((error) => setActivity(String(error))); }, [config.managedRuntimeRecordPath, installed.length]);
  const checkUpdates = async () => {
    setActivity("Checking GitHub Releases…");
    try {
      const result = await api.checkForUpdates();
      setUpdateInfo(result);
      setActivity(result.updateAvailable ? `LighTex ${result.latestVersion} is available.` : "LighTex is up to date.");
    } catch (error) { setActivity(`Update check failed: ${String(error)}`); }
  };
  const removeRuntime = async (item: InstalledRuntime) => {
    if (item.active) return;
    const confirmed = await ask(`Move the ${capitalize(item.record.variant)} runtime ${item.record.runtimeVersion} (${formatBytes(item.installedSize)}) to Trash?`, { title: "Remove Managed Runtime", kind: "warning", okLabel: "Move to Trash", cancelLabel: "Cancel" });
    if (!confirmed) return;
    try { await api.removeRuntime(item.record, config.managedRuntimeRecordPath); await refreshStorage(); }
    catch (error) { setActivity(String(error)); }
  };
  const cleanStorage = async (kind: "runtime" | "build") => {
    if (!usage) return;
    const bytes = kind === "runtime" ? usage.runtimeDownloads + usage.runtimeStaging : usage.buildCache;
    const confirmed = await ask(`Clear ${formatBytes(bytes)} of ${kind === "runtime" ? "runtime downloads and unfinished installations" : "LaTeX build cache"}? Project source files are never removed.`, { title: "Clear LighTex Storage", kind: "warning", okLabel: "Clear", cancelLabel: "Cancel" });
    if (!confirmed) return;
    try {
      const cleared = await api.clearStorage(kind === "runtime", kind === "runtime", kind === "build");
      setActivity(`Cleared ${formatBytes(cleared.runtimeDownloads + cleared.runtimeStaging + cleared.buildCache)}.`);
      await refreshStorage();
    } catch (error) { setActivity(String(error)); }
  };
  return (
    <div className="settings-layer" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <aside ref={panel} className="settings-panel" role="dialog" aria-modal="true" aria-label="Settings" onKeyDown={(event) => {
        if (event.key !== "Tab") return;
        const focusable = Array.from(event.currentTarget.querySelectorAll<HTMLElement>("button:not(:disabled), input:not(:disabled), select:not(:disabled), [tabindex]:not([tabindex='-1'])"));
        if (focusable.length === 0) return;
        const current = focusable.indexOf(document.activeElement as HTMLElement);
        const next = event.shiftKey ? (current <= 0 ? focusable.length - 1 : current - 1) : (current === focusable.length - 1 ? 0 : current + 1);
        if (current === -1 || next !== current + (event.shiftKey ? -1 : 1)) { event.preventDefault(); focusable[next].focus(); }
      }}>
        <div className="settings-header"><h2>Settings</h2><button className="icon-button" onClick={onClose} aria-label="Close Settings"><X size={16} /></button></div>
        <div className="settings-tabs" role="tablist">
          {(["general", "editor", "latex"] as SettingsTab[]).map((item) => <button key={item} role="tab" aria-selected={tab === item} className={tab === item ? "selected" : ""} onClick={() => setTab(item)}>{item === "latex" ? "LaTeX" : item[0].toUpperCase() + item.slice(1)}</button>)}
        </div>
        <div className="settings-body">
          {tab === "general" && <>
            <SettingsSection title="Projects">
              <CheckRow label="Open the last project at launch" checked={config.openLastProject} onChange={(value) => update({ openLastProject: value })} />
              <CheckRow label="Save documents automatically" checked={config.autosave} onChange={(value) => update({ autosave: value })} />
              <button className="settings-action" onClick={async () => {
                const confirmed = await ask("Remove every project from Recent Projects? The folders and files will remain on your computer.", { title: "Clear Recent Projects", kind: "warning", okLabel: "Clear", cancelLabel: "Cancel" });
                if (confirmed) await update({ recentProjects: [] });
              }}><Trash2 size={14} />Clear Recent Projects</button>
            </SettingsSection>
            <SettingsSection title="Updates"><p>LighTex checks GitHub Releases only when you ask. It never downloads or runs an update automatically.</p><button className="settings-action" onClick={() => void checkUpdates()}><FolderOpen size={14} />Check for Updates</button>{updateInfo?.updateAvailable && <button className="settings-action" onClick={() => void openUrl(updateInfo.releaseUrl)}><ExternalLink size={14} />Open LighTex {updateInfo.latestVersion} Release</button>}</SettingsSection>
          </>}
          {tab === "editor" && <>
            <SettingsSection title="Text">
              <label className="settings-field"><span>Font size</span><input type="range" min="11" max="22" step="0.5" value={config.editorFontSize} onChange={(event) => update({ editorFontSize: Number(event.target.value) })} /><output>{config.editorFontSize} pt</output></label>
              <label className="settings-field"><span>Tab width</span><select value={config.tabWidth} onChange={(event) => update({ tabWidth: Number(event.target.value) })}><option value="2">2 spaces</option><option value="4">4 spaces</option><option value="8">8 spaces</option></select></label>
              <CheckRow label="Show line numbers" checked={config.showLineNumbers} onChange={(value) => update({ showLineNumbers: value })} />
              <CheckRow label="Wrap long lines" checked={config.wordWrap} onChange={(value) => update({ wordWrap: value })} />
              <CheckRow label="Automatically close brackets" checked={config.autoCloseBrackets} onChange={(value) => update({ autoCloseBrackets: value })} />
            </SettingsSection>
          </>}
          {tab === "latex" && <>
            <SettingsSection title="Build">
              <label className="settings-field"><span>Engine</span><select value={config.latexEngine} onChange={(event) => update({ latexEngine: event.target.value as LatexEngine })}>{(["pdfLaTex", "xeLaTex", "luaLaTex"] as LatexEngine[]).map((engine) => <option key={engine} value={engine} disabled={!system.engines[enginePath(engine)] && !useAppStore.getState().activeToolchain.engines[enginePath(engine)]}>{engineLabel(engine)}</option>)}</select></label>
              <label className="settings-field"><span>Build tool</span><select value={config.buildTool} onChange={(event) => update({ buildTool: event.target.value as BuildTool })}><option value="latexmk">latexmk</option><option value="directCompiler">Direct compiler</option></select></label>
              <CheckRow label="Auto Compile" checked={config.automaticBuilds} onChange={(value) => update({ automaticBuilds: value })} />
              <label className="settings-field"><span>Compile after</span><select value={config.automaticBuildDelaySeconds} onChange={(event) => update({ automaticBuildDelaySeconds: Number(event.target.value) })}>{[2, 5, 10].map((seconds) => <option key={seconds} value={seconds}>{seconds} seconds</option>)}</select></label>
              <CheckRow label="Show Problems when a build fails" checked={config.showProblemsOnFailure} onChange={(value) => update({ showProblemsOnFailure: value })} />
            </SettingsSection>
            <SettingsSection title="TeX source">
              {Object.keys(system.engines).length > 0 && <button className={`runtime-row ${config.texProvider === "system" ? "active" : ""}`} onClick={chooseSystem}><HardDrive size={16} /><span><strong>System TeX</strong><small>{Object.keys(system.engines).map(engineLabelFromPath).join(", ")}</small></span>{config.texProvider === "system" && <Check size={15} />}</button>}
              {inventory.map((item) => <div key={item.record.rootPath} className={`runtime-row-container ${item.active ? "active" : ""}`}><button className="runtime-row" onClick={() => chooseManaged(item.record)}><HardDrive size={16} /><span><strong>{capitalize(item.record.variant)} Runtime</strong><small>TeX Live {item.record.texLiveYear} · {item.record.architecture} · {formatBytes(item.installedSize)}</small><small title={item.record.rootPath}>{item.record.rootPath}</small></span>{item.active && <Check size={15} />}</button>{!item.active && <button className="icon-button runtime-remove" onClick={() => void removeRuntime(item)} aria-label={`Remove ${item.record.variant} runtime`}><Trash2 size={13} /></button>}</div>)}
              {manifest && !installed.some((runtime) => runtime.runtimeVersion === manifest.runtimeVersion) && <button className="settings-action" onClick={() => void installRuntime("standard")}><Download size={14} />Install Standard Runtime {manifest.runtimeVersion}</button>}
            </SettingsSection>
            <SettingsSection title="Storage">
              <button className="settings-action" onClick={() => void cleanStorage("runtime")} disabled={!usage || usage.runtimeDownloads + usage.runtimeStaging === 0}><Trash2 size={14} />Clear Runtime Downloads · {formatBytes((usage?.runtimeDownloads ?? 0) + (usage?.runtimeStaging ?? 0))}</button>
              <button className="settings-action" onClick={() => void cleanStorage("build")} disabled={!usage || usage.buildCache === 0}><Trash2 size={14} />Clear Build Cache · {formatBytes(usage?.buildCache ?? 0)}</button>
            </SettingsSection>
          </>}
          {activity && <p className="settings-activity" aria-live="polite">{activity}</p>}
        </div>
      </aside>
    </div>
  );
}

function SettingsSection({ title, children }: { title: string; children: React.ReactNode }) { return <section className="settings-section"><h3>{title}</h3><div>{children}</div></section>; }
function CheckRow({ label, checked, onChange }: { label: string; checked: boolean; onChange(value: boolean): void }) { return <label className="check-row"><input type="checkbox" checked={checked} onChange={(event) => onChange(event.target.checked)} /><span>{label}</span></label>; }
const enginePath = (engine: LatexEngine) => engine === "xeLaTex" ? "xelatex" : engine === "luaLaTex" ? "lualatex" : "pdflatex";
const engineLabel = (engine: LatexEngine) => engine === "xeLaTex" ? "XeLaTeX" : engine === "luaLaTex" ? "LuaLaTeX" : "pdfLaTeX";
const engineLabelFromPath = (engine: string) => engine === "xelatex" ? "XeLaTeX" : engine === "lualatex" ? "LuaLaTeX" : "pdfLaTeX";
const capitalize = (value: string) => value[0].toUpperCase() + value.slice(1);
const formatBytes = (bytes: number) => {
  if (bytes < 1_000) return `${bytes} B`;
  const units = ["KB", "MB", "GB"];
  let value = bytes / 1_000;
  let unit = 0;
  while (value >= 1_000 && unit < units.length - 1) { value /= 1_000; unit += 1; }
  return `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(value)} ${units[unit]}`;
};
