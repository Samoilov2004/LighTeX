import { useMemo, useState } from "react";
import { Check, CheckCircle2, Download, RefreshCw, WifiOff, X } from "lucide-react";
import { useAppStore } from "../store";
import type { RuntimeAsset, RuntimeVariant } from "../types";
import appIcon from "../assets/AppIcon128.png";
import { WindowDragRegion } from "./WindowDragRegion";

export function RuntimeSetup() {
  const system = useAppStore((state) => state.systemToolchain);
  const manifest = useAppStore((state) => state.runtimeManifest);
  const runtimeEvent = useAppStore((state) => state.runtimeEvent);
  const runtimeError = useAppStore((state) => state.runtimeError);
  const environment = useAppStore((state) => state.runtimeEnvironment);
  const chooseSystem = useAppStore((state) => state.chooseSystemTex);
  const install = useAppStore((state) => state.installRuntime);
  const cancel = useAppStore((state) => state.cancelRuntime);
  const [variant, setVariant] = useState<RuntimeVariant>("standard");
  const hasSystem = Object.keys(system.engines).length > 0;
  const busy = runtimeEvent && ["checking", "downloading", "verifying", "installing"].includes(runtimeEvent.stage);
  const assets = useMemo(() => {
    return new Map((manifest?.assets ?? []).filter((asset) => asset.platform === environment.platform && asset.architecture === environment.architecture).map((asset) => [asset.variant, asset]));
  }, [manifest, environment]);

  return (
    <main className="setup-view">
      <WindowDragRegion className="setup-toolbar" />
      <div className="setup-content">
        <header>
          <img src={appIcon} alt="" className="setup-icon" />
          <div><h1>Set up LaTeX</h1><p>Choose the TeX installation LighTex will use to build your documents.</p></div>
        </header>
        {hasSystem && (
          <section className="existing-tex">
            <div><strong>System TeX is ready</strong><span>{Object.keys(system.engines).map(engineLabel).join(", ")}</span></div>
            <button className="primary-button" onClick={chooseSystem}><Check size={15} />Use Existing TeX</button>
          </section>
        )}
        <div className="setup-divider"><span>{hasSystem ? "Or install a managed runtime" : "Choose a managed runtime"}</span></div>
        <div className="runtime-cards">
          {(["minimal", "standard", "full"] as RuntimeVariant[]).map((item) => (
            <RuntimeCard key={item} variant={item} asset={assets.get(item)} selected={variant === item} onSelect={() => setVariant(item)} />
          ))}
        </div>
        {runtimeError && (
          <div className="runtime-error" role="alert"><WifiOff size={16} /><span>{runtimeError}</span><button className="secondary-button" onClick={() => window.location.reload()}><RefreshCw size={14} />Retry</button></div>
        )}
        {busy ? (
          <RuntimeProgress event={runtimeEvent!} onCancel={cancel} />
        ) : (
          <div className="setup-footer">
            <span><strong>{capitalize(variant)}</strong>{variant === "standard" ? " is recommended for textbooks and mathematics." : " can be changed later in Settings."}</span>
            <button className="primary-button" disabled={!assets.has(variant)} onClick={() => install(variant)}><Download size={15} />Install {capitalize(variant)}</button>
          </div>
        )}
      </div>
    </main>
  );
}

function RuntimeCard({ variant, asset, selected, onSelect }: { variant: RuntimeVariant; asset?: RuntimeAsset; selected: boolean; onSelect(): void }) {
  const summaries: Record<RuntimeVariant, string> = {
    minimal: "All three engines with the smallest practical package set.",
    standard: "Mathematics, figures, fonts, and bibliographies.",
    full: "Maximum offline compatibility with the complete package set.",
  };
  return (
    <button className={`runtime-card ${selected ? "selected" : ""}`} onClick={onSelect} aria-pressed={selected}>
      <span className="runtime-card-title"><strong>{capitalize(variant)}</strong>{variant === "standard" && <small>RECOMMENDED</small>}{selected && <CheckCircle2 className="runtime-card-check" size={16} />}</span>
      <span>{summaries[variant]}</span>
      <span className="runtime-size">{asset ? `${formatBytes(asset.compressedSize)} download · ${formatBytes(asset.installedSize)} installed` : "Catalog unavailable"}</span>
    </button>
  );
}

function RuntimeProgress({ event, onCancel }: { event: NonNullable<ReturnType<typeof useAppStore.getState>["runtimeEvent"]>; onCancel(): void }) {
  const fraction = event.stage === "downloading" && event.total > 0 ? event.received / event.total : event.stage === "verifying" ? 0.82 : event.stage === "installing" ? 0.92 : 0.04;
  const label = event.stage === "checking" ? "Checking runtime…" : event.stage === "downloading" ? "Downloading" : event.stage === "verifying" ? "Verifying" : "Installing";
  return (
    <div className="runtime-progress" aria-live="polite">
      <div><strong>{label}</strong>{event.stage === "downloading" && <span>{Math.round(fraction * 100)}% · {formatBytes(event.received)} of {formatBytes(event.total)} · {formatBytes(event.bytesPerSecond)}/s</span>}</div>
      <progress max={1} value={fraction} aria-label={label} />
      <button className="icon-button" onClick={onCancel} aria-label="Cancel runtime installation"><X size={15} /></button>
    </div>
  );
}

const capitalize = (value: string) => value[0].toUpperCase() + value.slice(1);
const formatBytes = (bytes: number) => {
  const large = bytes >= 1_000_000_000;
  return `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(bytes / (large ? 1_000_000_000 : 1_000_000))} ${large ? "GB" : "MB"}`;
};
const engineLabel = (value: string) => value === "pdflatex" ? "pdfLaTeX" : value === "xelatex" ? "XeLaTeX" : "LuaLaTeX";
