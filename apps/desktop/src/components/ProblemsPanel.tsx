import { useState } from "react";
import { AlertTriangle, ChevronDown, ChevronRight, FileWarning, PackagePlus, XCircle } from "lucide-react";
import { api } from "../api";
import { useAppStore } from "../store";

export function ProblemsPanel() {
  const result = useAppStore((state) => state.buildResult);
  const activeRuntime = useAppStore((state) => state.activeRuntime);
  const openDocument = useAppStore((state) => state.openDocument);
  const setError = useAppStore((state) => state.setError);
  const [tab, setTab] = useState<"problems" | "log">("problems");
  const [installing, setInstalling] = useState(false);
  return (
    <section className="problems-panel" aria-label="Build output">
      <div className="problems-tabs" role="tablist">
        <button role="tab" aria-selected={tab === "problems"} className={tab === "problems" ? "selected" : ""} onClick={() => setTab("problems")}>Problems <span>{result?.diagnostics.length ?? 0}</span></button>
        <button role="tab" aria-selected={tab === "log"} className={tab === "log" ? "selected" : ""} onClick={() => setTab("log")}>Log</button>
        <div className="toolbar-spacer" />
        <button className="icon-button" onClick={() => useAppStore.setState({ problemsOpen: false })} aria-label="Close Problems"><ChevronDown size={15} /></button>
      </div>
      {tab === "log" ? <pre className="build-log">{result?.log || "No build output."}</pre> : (
        <div className="diagnostics-list">
          {result?.missingPackageFile && activeRuntime && <button className="missing-package" disabled={installing} onClick={async () => {
            setInstalling(true);
            try {
              await api.installMissingPackage(activeRuntime, result.missingPackageFile!);
              await useAppStore.getState().build();
            } catch (error) { setError(String(error)); }
            finally { setInstalling(false); }
          }}><PackagePlus size={16} /><span><strong>{result.missingPackageFile} is missing</strong><small>{installing ? "Installing…" : "Install the TeX Live package and compile again"}</small></span></button>}
          {(result?.diagnostics ?? []).map((group, index) => <DiagnosticGroup key={`${group.primary.message}-${index}`} group={group} onOpen={(path, line) => openDocument(path, line)} />)}
          {!result?.diagnostics.length && <div className="sidebar-empty"><FileWarning size={20} /><span>No build problems.</span></div>}
        </div>
      )}
    </section>
  );
}

function DiagnosticGroup({ group, onOpen }: { group: NonNullable<ReturnType<typeof useAppStore.getState>["buildResult"]>["diagnostics"][number]; onOpen(path: string, line?: number): void }) {
  const [expanded, setExpanded] = useState(false);
  const Icon = group.primary.severity === "error" ? XCircle : AlertTriangle;
  const content = <><Icon size={15} className={group.primary.severity} aria-hidden="true" /><span><strong>{group.primary.message}</strong>{group.primary.relativePath && <small>{group.primary.relativePath}{group.primary.line ? `:${group.primary.line}` : ""}</small>}</span>{group.related.length > 0 && (expanded ? <ChevronDown size={13} /> : <ChevronRight size={13} />)}</>;
  return (
    <div className="diagnostic-group">
      {group.primary.relativePath ? <button className="diagnostic-primary" onClick={() => onOpen(group.primary.relativePath!, group.primary.line ?? undefined)}>{content}</button> : <div className="diagnostic-primary">{content}</div>}
      {group.related.length > 0 && <button className="related-toggle" onClick={() => setExpanded(!expanded)}>{expanded ? "Hide" : "Show"} {group.related.length} compiler message{group.related.length === 1 ? "" : "s"}</button>}
      {expanded && <div className="related-list">{group.related.map((item, index) => <div key={index}>{item.message}</div>)}</div>}
    </div>
  );
}
