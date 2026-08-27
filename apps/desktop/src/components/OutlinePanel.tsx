import { FileText } from "lucide-react";
import { useAppStore } from "../store";

export function OutlinePanel() {
  const outline = useAppStore((state) => state.outline);
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
          onClick={() => openDocument(item.relativePath, item.line)}
          title={`${item.relativePath}:${item.line}`}
        >
          <span>{item.title}</span>
          <small>{item.line}</small>
        </button>
      ))}
    </nav>
  );
}
