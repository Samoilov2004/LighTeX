import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { ChevronDown, FunctionSquare, Image, PanelsTopLeft, Search, Sigma, Table2, X } from "lucide-react";
import { filterSymbols, symbolCategories, type SymbolCategory } from "../insertCatalog";
import {
  blockSnippets,
  createStyledTableLatex,
  figureSnippets,
  filterMathSnippets,
  mathSnippetCategories,
  type LatexSnippet,
  type MathSnippetCategory,
} from "../insertSnippets";

type Category = "symbols" | "math" | "blocks" | "figures" | "tables";

export function InsertShelf({ onClose }: { onClose(): void }) {
  const [category, setCategory] = useState<Category>("symbols");
  const [query, setQuery] = useState("");
  const [symbolCategory, setSymbolCategory] = useState<"All" | SymbolCategory>("Greek");
  const [mathCategory, setMathCategory] = useState<MathSnippetCategory>("Popular");
  const deferredQuery = useDeferredValue(query);
  const filteredSymbols = useMemo(() => filterSymbols(deferredQuery, symbolCategory), [deferredQuery, symbolCategory]);
  const filteredMath = useMemo(() => filterMathSnippets(mathCategory), [mathCategory]);
  const resultsRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (resultsRef.current) resultsRef.current.scrollTop = 0;
  }, [deferredQuery, symbolCategory]);
  return (
    <section className="insert-shelf" aria-label="Insert LaTeX">
      <button className="shelf-handle" onClick={onClose} aria-label="Collapse insert shelf" title="Collapse"><ChevronDown size={14} /></button>
      <div className="shelf-toolbar">
        <div className="shelf-tabs" role="tablist" aria-label="Insert categories">
          <ShelfTab category="symbols" current={category} set={setCategory}><FunctionSquare size={14} /><span>Symbols</span></ShelfTab>
          <ShelfTab category="math" current={category} set={setCategory}><Sigma size={14} /><span>Math</span></ShelfTab>
          <ShelfTab category="blocks" current={category} set={setCategory}><PanelsTopLeft size={14} /><span>Blocks</span></ShelfTab>
          <ShelfTab category="figures" current={category} set={setCategory}><Image size={14} /><span>Figures</span></ShelfTab>
          <ShelfTab category="tables" current={category} set={setCategory}><Table2 size={14} /><span>Tables</span></ShelfTab>
        </div>
        {category === "symbols" && <label className="shelf-search"><Search size={13} aria-hidden="true" /><span className="sr-only">Search symbols</span><input value={query} onChange={(event) => { setQuery(event.target.value); if (event.target.value.trim()) setSymbolCategory("All"); }} placeholder="Search name or command" /></label>}
        <button className="icon-button shelf-close" onClick={onClose} aria-label="Close insert shelf" title="Close"><X size={14} /></button>
      </div>
      <div className="shelf-body">
        {category === "symbols" && <div className="symbol-browser">
          <div className="symbol-category-filter" role="toolbar" aria-label="Symbol categories">
            {symbolCategories.map((item) => <button key={item} className={item === symbolCategory ? "selected" : ""} aria-pressed={item === symbolCategory} onClick={() => setSymbolCategory(item)}>{item}</button>)}
          </div>
          <div ref={resultsRef} className="symbol-results" aria-live="polite">
            {filteredSymbols.length > 0 ? <div className="symbol-grid">{filteredSymbols.map((item) => <InsertButton key={`${item.category}-${item.latex}`} label={item.glyph} latex={item.latex} title={`${item.name} · ${item.latex}`} command={item.latex} />)}</div> : <div className="symbol-empty"><strong>No matching symbols</strong><span>Try a name such as “arrow”, “subset”, or a command such as “\\lambda”.</span></div>}
          </div>
        </div>}
        {category === "math" && <div className="snippet-browser">
          <div className="snippet-category-filter" role="toolbar" aria-label="Math categories">
            {mathSnippetCategories.map((item) => <button key={item} className={item === mathCategory ? "selected" : ""} aria-pressed={item === mathCategory} onClick={() => setMathCategory(item)}>{item}</button>)}
          </div>
          <div className="snippet-results"><div className="rich-snippet-grid">{filteredMath.map((snippet) => <SnippetCard key={snippet.id} snippet={snippet} kind="math" />)}</div></div>
        </div>}
        {category === "blocks" && <div className="snippet-results standalone"><div className="rich-snippet-grid">{blockSnippets.map((snippet) => <SnippetCard key={snippet.id} snippet={snippet} kind="block" />)}</div></div>}
        {category === "figures" && <div className="snippet-results standalone"><div className="rich-snippet-grid">{figureSnippets.map((snippet) => <SnippetCard key={snippet.id} snippet={snippet} kind="figure" />)}</div></div>}
        {category === "tables" && <TableBuilder />}
      </div>
    </section>
  );
}

function ShelfTab({ category, current, set, children }: { category: Category; current: Category; set(value: Category): void; children: React.ReactNode }) {
  const label = category.charAt(0).toUpperCase() + category.slice(1);
  return <button role="tab" aria-label={label} aria-selected={category === current} className={category === current ? "selected" : ""} onClick={() => set(category)}>{children}</button>;
}

function InsertButton({ label, latex, wide = false, title, command }: { label: string; latex: string; wide?: boolean; title?: string; command?: string }) {
  return <button className={wide ? "snippet-button" : "symbol-button"} title={title} aria-label={title ?? "Insert " + label} onClick={() => insertLatex(latex)}><strong>{label}</strong>{wide && <code>{latex.split("\n")[0]}</code>}{!wide && command && <small>{command.replace(/^\\/, "")}</small>}</button>;
}

function SnippetCard({ snippet, kind }: { snippet: LatexSnippet; kind: "math" | "block" | "figure" }) {
  const className = ["insert-snippet-card", kind, snippet.tone ? "tone-" + snippet.tone : ""].filter(Boolean).join(" ");
  return (
    <button className={className} aria-label={"Insert " + snippet.title} title={snippet.title + " — " + snippet.description} onClick={() => insertLatex(snippet.latex)}>
      <span className="snippet-preview" aria-hidden="true">{snippet.preview}</span>
      <span className="snippet-copy">
        <strong>{snippet.title}</strong>
        <small>{snippet.description}</small>
        {snippet.requires && <span className="snippet-requirement">{snippet.requires}</span>}
      </span>
    </button>
  );
}

function TableBuilder() {
  const [rows, setRows] = useState(3);
  const [columns, setColumns] = useState(3);
  const [alignment, setAlignment] = useState<"left" | "center" | "right">("center");
  const [headerRow, setHeaderRow] = useState(true);
  const [gridLines, setGridLines] = useState(false);
  const sizes = Array.from({ length: 8 }, (_, index) => index + 1);
  const gridRef = useRef<HTMLDivElement>(null);

  const selectSize = (nextRows: number, nextColumns: number, moveFocus = false) => {
    const clampedRows = Math.max(1, Math.min(8, nextRows));
    const clampedColumns = Math.max(1, Math.min(8, nextColumns));
    setRows(clampedRows);
    setColumns(clampedColumns);
    if (moveFocus) {
      gridRef.current
        ?.querySelector<HTMLButtonElement>(`[data-row="${clampedRows}"][data-column="${clampedColumns}"]`)
        ?.focus();
    }
  };

  const handleCellKeyDown = (event: React.KeyboardEvent<HTMLButtonElement>) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      insertTable(rows, columns);
      return;
    }
    const movement = {
      ArrowUp: [-1, 0],
      ArrowDown: [1, 0],
      ArrowLeft: [0, -1],
      ArrowRight: [0, 1],
    }[event.key];
    if (!movement) return;
    event.preventDefault();
    selectSize(rows + movement[0], columns + movement[1], true);
  };

  const insertTable = (selectedRows: number, selectedColumns: number) => {
    selectSize(selectedRows, selectedColumns);
    insertLatex(createStyledTableLatex(selectedRows, selectedColumns, { alignment, headerRow, gridLines }));
  };

  return (
    <div className="table-builder">
      <div className="table-builder-settings" aria-label="Table settings">
        <div className="table-builder-heading"><strong>Table style</strong><span>Applied when you choose a size</span></div>
        <div className="table-builder-controls">
          <label><span>Align</span><select value={alignment} onChange={(event) => setAlignment(event.target.value as "left" | "center" | "right")}><option value="left">Left</option><option value="center">Center</option><option value="right">Right</option></select></label>
          <label className="table-option"><input type="checkbox" checked={headerRow} onChange={(event) => setHeaderRow(event.target.checked)} /><span>Header</span></label>
          <label className="table-option"><input type="checkbox" checked={gridLines} onChange={(event) => setGridLines(event.target.checked)} /><span>Grid lines</span></label>
        </div>
      </div>
      <div className="table-size-panel">
        <div className="table-size-heading"><strong>{rows} × {columns}</strong><span>Click a cell to insert</span></div>
        <div ref={gridRef} className="table-size-grid" role="grid" aria-label="Table size" aria-rowcount={8} aria-colcount={8}>
          {sizes.map((row) => (
            <div className="table-size-row" role="row" key={row}>
              {sizes.map((column) => (
                <button
                  type="button"
                  role="gridcell"
                  key={column}
                  data-row={row}
                  data-column={column}
                  className={row <= rows && column <= columns ? "table-size-cell highlighted" : "table-size-cell"}
                  aria-label={`${row} rows by ${column} columns`}
                  aria-selected={row === rows && column === columns}
                  tabIndex={row === rows && column === columns ? 0 : -1}
                  onPointerEnter={() => selectSize(row, column)}
                  onFocus={() => selectSize(row, column)}
                  onKeyDown={handleCellKeyDown}
                  onClick={() => insertTable(row, column)}
                />
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

const insertLatex = (text: string) => window.dispatchEvent(new CustomEvent("lightex:insert", { detail: { text } }));
