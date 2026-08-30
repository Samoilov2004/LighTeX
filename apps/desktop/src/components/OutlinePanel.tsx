import { FileText } from "lucide-react";
import { useAppStore } from "../store";
import { outlineItemKey } from "../outlinePages";

export function OutlinePanel() {
  const outline = useAppStore((state) => state.outline);
  const outlinePages = useAppStore((state) => state.outlinePages);
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
            await openDocument(item.relativePath, item.line);
            window.dispatchEvent(new CustomEvent("lightex:source-sync", { detail: { path: item.relativePath, line: item.line, column: 1 } }));
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
