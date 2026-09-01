import { FileText } from "lucide-react";
import { useAppStore } from "../store";
import { outlineItemKey } from "../outlinePages";

export function OutlinePanel() {
  const preview = useAppStore((state) => state.versionPreview);
  const outline = preview?.outline ?? useAppStore.getState().outline;
  const outlinePages = preview?.outlinePages ?? useAppStore.getState().outlinePages;
  const openDocument = useAppStore((state) => state.openDocument);
  if (outline.length === 0) {
    return <div className="sidebar-empty"><FileText size={20} /><span>No headings in this document.</span></div>;
  }
  return (
    <nav className="outline-list" aria-label="Document outline">
      {outline.map((item) => (
        <button
          key={`${item.relativePath}:${item.line}:${item.title}`}
          style={{ paddingLeft: 9 + Math.max(0, item.level - 1) * 13 }}
          onClick={async () => {
            if (preview) {
              await useAppStore.getState().openVersionDocument(item.relativePath, item.line);
              window.dispatchEvent(new CustomEvent("lightex:source-sync", { detail: { path: item.relativePath, line: item.line, column: 1 } }));
            } else {
              await openDocument(item.relativePath, item.line);
              window.dispatchEvent(new CustomEvent("lightex:source-sync", { detail: { path: item.relativePath, line: item.line, column: 1 } }));
            }
          }}
          title={`${item.title} — PDF page ${outlinePages[outlineItemKey(item)] ?? "not compiled"}`}
        >
          <span>{item.title}</span>
          <small aria-label={outlinePages[outlineItemKey(item)] ? `PDF page ${outlinePages[outlineItemKey(item)]}` : "PDF page unavailable"}>{outlinePages[outlineItemKey(item)] ?? "—"}</small>
        </button>
      ))}
    </nav>
  );
}
