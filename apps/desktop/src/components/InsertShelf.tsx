import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { ChevronDown, FunctionSquare, Image, List, Search, Table2, X } from "lucide-react";
import { createTableLatex, filterSymbols, symbolCategories, type SymbolCategory } from "../insertCatalog";

type Category = "symbols" | "math" | "figures" | "tables";

export function InsertShelf({ onClose }: { onClose(): void }) {
  const [category, setCategory] = useState<Category>("symbols");
  const [query, setQuery] = useState("");
  const [symbolCategory, setSymbolCategory] = useState<"All" | SymbolCategory>("Greek");
  const deferredQuery = useDeferredValue(query);
  const filteredSymbols = useMemo(() => filterSymbols(deferredQuery, symbolCategory), [deferredQuery, symbolCategory]);
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
          <ShelfTab category="math" current={category} set={setCategory}><List size={14} /><span>Math</span></ShelfTab>
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
        {category === "math" && <div className="snippet-grid">{mathSnippets.map(([label, latex]) => <InsertButton key={label} label={label} latex={latex} wide />)}</div>}
        {category === "figures" && <div className="snippet-grid"><InsertButton label="Full-width figure" latex={figureSnippet("0.9")} wide /><InsertButton label="Half-width figure" latex={figureSnippet("0.48")} wide /><InsertButton label="Two side-by-side figures" latex={twoFiguresSnippet} wide /></div>}
        {category === "tables" && <TablePicker />}
      </div>
    </section>
  );
}

function ShelfTab({ category, current, set, children }: { category: Category; current: Category; set(value: Category): void; children: React.ReactNode }) {
  return <button role="tab" aria-selected={category === current} className={category === current ? "selected" : ""} onClick={() => set(category)}>{children}</button>;
}

function InsertButton({ label, latex, wide = false, title, command }: { label: string; latex: string; wide?: boolean; title?: string; command?: string }) {
  return <button className={wide ? "snippet-button" : "symbol-button"} title={title} aria-label={title ?? `Insert ${label}`} onClick={() => insertLatex(latex)}><strong>{label}</strong>{wide && <code>{latex.split("\n")[0]}</code>}{!wide && command && <small>{command.replace(/^\\/, "")}</small>}</button>;
}

function TablePicker() {
  const [rows, setRows] = useState(3);
  const [columns, setColumns] = useState(3);
  return <div className="table-picker">
    <div className="table-picker-copy"><strong>{rows} × {columns} table</strong><span>Choose up to eight rows and columns.</span><button className="primary-button compact" onClick={() => insertLatex(createTableLatex(rows, columns))}>Insert Table</button></div>
    <div className="table-size-grid" role="grid" aria-label="Table size">
      {Array.from({ length: 8 }, (_, row) => Array.from({ length: 8 }, (_, column) => {
        const selected = row < rows && column < columns;
        return <button key={`${row}-${column}`} role="gridcell" className={selected ? "selected" : ""} aria-label={`${row + 1} rows by ${column + 1} columns`} aria-selected={selected} onPointerEnter={() => { setRows(row + 1); setColumns(column + 1); }} onFocus={() => { setRows(row + 1); setColumns(column + 1); }} onClick={() => insertLatex(createTableLatex(row + 1, column + 1))} />;
      }))}
    </div>
  </div>;
}

const insertLatex = (text: string) => window.dispatchEvent(new CustomEvent("lightex:insert", { detail: { text } }));

const figureSnippet = (width: string) => `\\begin{figure}[ht]\n  \\centering\n  \\includegraphics[width=${width}\\textwidth]{image.pdf}\n  \\caption{Caption}\n  \\label{fig:example}\n\\end{figure}`;

const twoFiguresSnippet = "\\begin{figure}[ht]\n  \\centering\n  \\begin{minipage}{0.48\\textwidth}\n    \\includegraphics[width=\\linewidth]{first.pdf}\n    \\caption{First caption}\n  \\end{minipage}\\hfill\n  \\begin{minipage}{0.48\\textwidth}\n    \\includegraphics[width=\\linewidth]{second.pdf}\n    \\caption{Second caption}\n  \\end{minipage}\n\\end{figure}";

const mathSnippets: Array<[string, string]> = [
  ["Inline math", "$x$"],
  ["Display equation", "\\begin{equation}\n  E = mc^2\n\\end{equation}"],
  ["Aligned equations", "\\begin{align}\n  a &= b + c \\\\\n  d &= e + f\n\\end{align}"],
  ["Cases", "$f(x) = \\begin{cases}\n  x^2, & x \\ge 0, \\\\\n  -x, & x < 0.\n\\end{cases}$"],
  ["Matrix", "$\\begin{pmatrix}\n  a & b \\\\\n  c & d\n\\end{pmatrix}$"],
  ["Theorem", "\\begin{theorem}\n  Statement.\n\\end{theorem}"],
];
