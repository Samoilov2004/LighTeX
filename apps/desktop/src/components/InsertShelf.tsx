import { useState } from "react";
import { ChevronDown, FunctionSquare, Image, List, Table2, X } from "lucide-react";

type Category = "symbols" | "math" | "figures" | "tables";

export function InsertShelf({ onClose }: { onClose(): void }) {
  const [category, setCategory] = useState<Category>("symbols");
  return (
    <section className="insert-shelf" aria-label="Insert LaTeX">
      <button className="shelf-handle" onClick={onClose} aria-label="Close insert shelf" title="Close"><ChevronDown size={14} /></button>
      <div className="shelf-sidebar" role="tablist" aria-label="Insert categories">
        <ShelfTab category="symbols" current={category} set={setCategory}><FunctionSquare size={15} />Symbols</ShelfTab>
        <ShelfTab category="math" current={category} set={setCategory}><List size={15} />Math</ShelfTab>
        <ShelfTab category="figures" current={category} set={setCategory}><Image size={15} />Figures</ShelfTab>
        <ShelfTab category="tables" current={category} set={setCategory}><Table2 size={15} />Tables</ShelfTab>
      </div>
      <div className="shelf-content">
        <div className="shelf-heading"><strong>{category[0].toUpperCase() + category.slice(1)}</strong><button className="icon-button" onClick={onClose} aria-label="Close insert shelf"><X size={14} /></button></div>
        {category === "symbols" && <div className="symbol-grid">{symbols.map(([label, latex]) => <InsertButton key={latex} label={label} latex={latex} />)}</div>}
        {category === "math" && <div className="snippet-grid">{mathSnippets.map(([label, latex]) => <InsertButton key={label} label={label} latex={latex} wide />)}</div>}
        {category === "figures" && <div className="snippet-grid"><InsertButton label="Figure" latex={"\\begin{figure}[ht]\n  \\centering\n  \\includegraphics[width=0.8\\textwidth]{image.pdf}\n  \\caption{Caption}\n  \\label{fig:example}\n\\end{figure}"} wide /></div>}
        {category === "tables" && <div className="snippet-grid"><InsertButton label="3-column table" latex={"\\begin{table}[ht]\n  \\centering\n  \\begin{tabular}{lll}\n    \\toprule\n    A & B & C \\\\\n    \\midrule\n    1 & 2 & 3 \\\\\n    \\bottomrule\n  \\end{tabular}\n  \\caption{Caption}\n\\end{table}"} wide /></div>}
      </div>
    </section>
  );
}

function ShelfTab({ category, current, set, children }: { category: Category; current: Category; set(value: Category): void; children: React.ReactNode }) {
  return <button role="tab" aria-selected={category === current} className={category === current ? "selected" : ""} onClick={() => set(category)}>{children}</button>;
}

function InsertButton({ label, latex, wide = false }: { label: string; latex: string; wide?: boolean }) {
  return <button className={wide ? "snippet-button" : "symbol-button"} onClick={() => window.dispatchEvent(new CustomEvent("lightex:insert", { detail: { text: latex } }))}><strong>{label}</strong>{wide && <code>{latex.split("\n")[0]}</code>}</button>;
}

const symbols: Array<[string, string]> = [
  ["α", "\\alpha"], ["β", "\\beta"], ["γ", "\\gamma"], ["δ", "\\delta"], ["ε", "\\varepsilon"],
  ["θ", "\\theta"], ["λ", "\\lambda"], ["μ", "\\mu"], ["π", "\\pi"], ["σ", "\\sigma"],
  ["φ", "\\varphi"], ["ω", "\\omega"], ["∞", "\\infty"], ["∂", "\\partial"], ["∇", "\\nabla"],
  ["∈", "\\in"], ["⊂", "\\subset"], ["∪", "\\cup"], ["∩", "\\cap"], ["→", "\\to"],
];

const mathSnippets: Array<[string, string]> = [
  ["Inline math", "$x$"],
  ["Display equation", "\\begin{equation}\n  E = mc^2\n\\end{equation}"],
  ["Aligned equations", "\\begin{align}\n  a &= b + c \\\\\n  d &= e + f\n\\end{align}"],
  ["Cases", "$f(x) = \\begin{cases}\n  x^2, & x \\ge 0, \\\\\n  -x, & x < 0.\n\\end{cases}$"],
  ["Matrix", "$\\begin{pmatrix}\n  a & b \\\\\n  c & d\n\\end{pmatrix}$"],
  ["Theorem", "\\begin{theorem}\n  Statement.\n\\end{theorem}"],
];
