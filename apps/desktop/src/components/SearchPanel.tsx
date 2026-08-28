import { useEffect, useRef, useState } from "react";
import { CaseSensitive, Regex, Replace, RotateCcw, WholeWord } from "lucide-react";
import { api } from "../api";
import { useAppStore } from "../store";
import { useModalFocus } from "../useModalFocus";
import type { ReplacePreview, SearchQuery, SearchResult } from "../types";

const initialQuery: SearchQuery = {
  text: "",
  caseSensitive: false,
  wholeWord: false,
  usesRegularExpression: false,
};

export function SearchPanel() {
  const project = useAppStore((state) => state.project);
  const documents = useAppStore((state) => state.documents);
  const openDocument = useAppStore((state) => state.openDocument);
  const updateText = useAppStore((state) => state.updateText);
  const refreshProject = useAppStore((state) => state.refreshProject);
  const setError = useAppStore((state) => state.setError);
  const [query, setQuery] = useState(initialQuery);
  const [replacement, setReplacement] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [busy, setBusy] = useState(false);
  const [lastReplace, setLastReplace] = useState<ReplacePreview[] | null>(null);
  const [pendingReplace, setPendingReplace] = useState<ReplacePreview[] | null>(null);
  const replaceDialog = useModalFocus<HTMLElement>(() => setPendingReplace(null), pendingReplace !== null);
  const generation = useRef(0);
  const buffers = Object.values(documents).map((document) => ({ relativePath: document.relativePath, text: document.text }));

  useEffect(() => {
    if (!project || !query.text) {
      setResults([]);
      return;
    }
    const current = ++generation.current;
    const timer = window.setTimeout(async () => {
      setBusy(true);
      try {
        const found = await api.search(project.id, query, buffers);
        if (generation.current === current) setResults(found);
      } catch (error) {
        setError(String(error));
      } finally {
        if (generation.current === current) setBusy(false);
      }
    }, 180);
    return () => window.clearTimeout(timer);
  }, [project?.id, query.text, query.caseSensitive, query.wholeWord, query.usesRegularExpression, documents]);

  const replaceAll = async () => {
    if (!project || !query.text) return;
    try {
      const preview = await api.replacePreview(project.id, query, replacement, buffers);
      const count = preview.reduce((sum, item) => sum + item.replacements, 0);
      if (count === 0) return;
      setPendingReplace(preview);
    } catch (error) {
      setError(String(error));
    }
  };

  const applyReplace = async () => {
    if (!project || !pendingReplace) return;
    try {
      const closed: ReplacePreview[] = [];
      for (const change of pendingReplace) {
        if (documents[change.relativePath]) updateText(change.relativePath, change.replacementText);
        else closed.push(change);
      }
      if (closed.length > 0) await api.applyReplacements(project.id, closed);
      setLastReplace(pendingReplace);
      setPendingReplace(null);
      await refreshProject();
      setResults(await api.search(project.id, query, Object.values(useAppStore.getState().documents).map((document) => ({ relativePath: document.relativePath, text: document.text }))));
    } catch (error) {
      setError(String(error));
    }
  };

  const undo = async () => {
    if (!project || !lastReplace) return;
    try {
      const closed: ReplacePreview[] = [];
      for (const change of lastReplace) {
        if (documents[change.relativePath]) updateText(change.relativePath, change.originalText);
        else closed.push(change);
      }
      if (closed.length > 0) await api.applyReplacements(project.id, closed, true);
      setLastReplace(null);
      await refreshProject();
    } catch (error) {
      setError(String(error));
    }
  };

  return (
    <div className="search-panel">
      <label className="search-field">
        <span className="sr-only">Search project</span>
        <input value={query.text} onChange={(event) => setQuery({ ...query, text: event.target.value })} placeholder="Search project" autoFocus />
      </label>
      <div className="search-options">
        <Toggle active={query.caseSensitive} label="Match case" onClick={() => setQuery({ ...query, caseSensitive: !query.caseSensitive })}><CaseSensitive size={14} /></Toggle>
        <Toggle active={query.wholeWord} label="Whole word" onClick={() => setQuery({ ...query, wholeWord: !query.wholeWord })}><WholeWord size={14} /></Toggle>
        <Toggle active={query.usesRegularExpression} label="Regular expression" onClick={() => setQuery({ ...query, usesRegularExpression: !query.usesRegularExpression })}><Regex size={14} /></Toggle>
      </div>
      <div className="replace-row">
        <input value={replacement} onChange={(event) => setReplacement(event.target.value)} placeholder="Replace with" aria-label="Replace with" />
        <button className="icon-button" onClick={replaceAll} disabled={!query.text} aria-label="Preview and replace all" title="Replace all"><Replace size={14} /></button>
        <button className="icon-button" onClick={undo} disabled={!lastReplace} aria-label="Undo last replace" title="Undo last replace"><RotateCcw size={14} /></button>
      </div>
      <div className="search-summary" aria-live="polite">{busy ? "Searching…" : `${results.length} result${results.length === 1 ? "" : "s"}`}</div>
      <div className="search-results">
        {groupResults(results).map(([file, items]) => (
          <section key={file} className="search-file-group">
            <h3>{file}</h3>
            {items.map((result) => (
              <button key={`${result.matchStart}-${result.matchLength}`} onClick={() => openDocument(file, result.line)}>
                <span className="result-location">{result.line}:{result.column}</span>
                <span>{result.preview || "Empty line"}</span>
              </button>
            ))}
          </section>
        ))}
      </div>
      {pendingReplace && <div className="modal-layer" role="presentation"><section ref={replaceDialog} className="native-dialog replace-preview-dialog" role="alertdialog" aria-modal="true" aria-labelledby="replace-preview-title"><h2 id="replace-preview-title">Review Project Replace</h2><p>{pendingReplace.reduce((sum, item) => sum + item.replacements, 0)} replacements across {pendingReplace.length} files. Open documents keep their unsaved state; closed files are saved atomically.</p><div className="replace-preview-list">{pendingReplace.map((item) => <div key={item.relativePath}><code>{item.relativePath}</code><span>{item.replacements}</span></div>)}</div><div className="dialog-actions"><button className="secondary-button" onClick={() => setPendingReplace(null)}>Cancel</button><button className="primary-button" onClick={() => void applyReplace()}>Replace All</button></div></section></div>}
    </div>
  );
}

function Toggle({ active, label, onClick, children }: { active: boolean; label: string; onClick(): void; children: React.ReactNode }) {
  return <button className={`icon-button ${active ? "pressed" : ""}`} aria-pressed={active} aria-label={label} title={label} onClick={onClick}>{children}</button>;
}

function groupResults(results: SearchResult[]): Array<[string, SearchResult[]]> {
  const groups = new Map<string, SearchResult[]>();
  for (const result of results) groups.set(result.relativePath, [...(groups.get(result.relativePath) ?? []), result]);
  return Array.from(groups.entries());
}
