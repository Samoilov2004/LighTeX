import { ALargeSmall, Undo2 } from "lucide-react";

interface EditorQuickControlsProps {
  canUndo: boolean;
  fontSize: number;
  onUndo(): void;
  onFontSizeChange(fontSize: number): void;
}

const fontSizes = Array.from({ length: 23 }, (_, index) => 11 + index * 0.5);

export function EditorQuickControls({ canUndo, fontSize, onUndo, onFontSizeChange }: EditorQuickControlsProps) {
  return (
    <div className="editor-quick-controls" role="toolbar" aria-label="Editor controls">
      <button
        className="icon-button"
        type="button"
        disabled={!canUndo}
        onClick={onUndo}
        aria-label="Undo last edit"
        title="Undo last edit (⌘Z / Ctrl+Z)"
      >
        <Undo2 size={14} aria-hidden="true" />
      </button>
      <label className="editor-font-control" title="Editor font size">
        <ALargeSmall size={14} aria-hidden="true" />
        <span className="sr-only">Editor font size</span>
        <select
          value={fontSize}
          onChange={(event) => onFontSizeChange(Number(event.target.value))}
          aria-label="Editor font size"
        >
          {fontSizes.map((size) => <option key={size} value={size}>{size} pt</option>)}
        </select>
      </label>
    </div>
  );
}
