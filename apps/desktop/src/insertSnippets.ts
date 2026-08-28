export type MathSnippetCategory = "Popular" | "Calculus" | "Linear Algebra" | "Structures";
export type SnippetTone = "blue" | "orange" | "green" | "red" | "violet" | "neutral";

export interface LatexSnippet {
  id: string;
  title: string;
  description: string;
  preview: string;
  latex: string;
  category?: Exclude<MathSnippetCategory, "Popular">;
  featured?: boolean;
  requires?: string;
  tone?: SnippetTone;
}

export interface StyledTableOptions {
  alignment: "left" | "center" | "right";
  headerRow: boolean;
  gridLines: boolean;
}

export const mathSnippetCategories: MathSnippetCategory[] = ["Popular", "Calculus", "Linear Algebra", "Structures"];

export const mathSnippets: LatexSnippet[] = [
  { id: "fraction", title: "Fraction", description: "Numerator over denominator", preview: "a ⁄ b", latex: "$\\frac{a}{b}$", category: "Structures", featured: true },
  { id: "root", title: "n-th Root", description: "Square or indexed root", preview: "ⁿ√x", latex: "$\\sqrt[n]{x}$", category: "Structures", featured: true },
  { id: "sum", title: "Finite Sum", description: "Indexed summation", preview: "Σ aₖ", latex: "$\\displaystyle \\sum_{k=1}^{n} a_k$", category: "Calculus", featured: true },
  { id: "integral", title: "Definite Integral", description: "Integral with limits", preview: "∫ₐᵇ f(x) dx", latex: "$\\displaystyle \\int_{a}^{b} f(x)\\,\\mathrm{d}x$", category: "Calculus", featured: true },
  { id: "limit", title: "Limit", description: "Function limit at a point", preview: "lim f(x)", latex: "$\\displaystyle \\lim_{x \\to 0} f(x)$", category: "Calculus", featured: true },
  { id: "matrix-2", title: "2 × 2 Matrix", description: "Parenthesized matrix", preview: "[ a  b ]\n[ c  d ]", latex: "$\\begin{pmatrix}\n  a & b \\\\\n  c & d\n\\end{pmatrix}$", category: "Linear Algebra", featured: true },
  { id: "cases", title: "Cases", description: "Piecewise definition", preview: "f(x) = { …", latex: "$f(x) = \\begin{cases}\n  x^2, & x \\ge 0, \\\\\n  -x, & x < 0.\n\\end{cases}$", category: "Structures", featured: true },
  { id: "aligned", title: "Aligned Equations", description: "Multiple aligned steps", preview: "a = b + c\nd = e + f", latex: "\\begin{align}\n  a &= b + c \\\\\n  d &= e + f\n\\end{align}", category: "Structures", featured: true },
  { id: "double-integral", title: "Double Integral", description: "Integral over a region", preview: "∬ᴰ f dA", latex: "$\\displaystyle \\iint_{D} f(x,y)\\,\\mathrm{d}A$", category: "Calculus" },
  { id: "derivative", title: "Derivative", description: "Ordinary derivative", preview: "d f ⁄ d x", latex: "$\\frac{\\mathrm{d}}{\\mathrm{d}x} f(x)$", category: "Calculus" },
  { id: "partial", title: "Partial Derivative", description: "Partial derivative in x", preview: "∂f ⁄ ∂x", latex: "$\\frac{\\partial f}{\\partial x}$", category: "Calculus" },
  { id: "series", title: "Infinite Series", description: "Power series expansion", preview: "Σₙ₌₀∞ aₙxⁿ", latex: "$\\displaystyle \\sum_{n=0}^{\\infty} a_n x^n$", category: "Calculus" },
  { id: "gradient", title: "Gradient", description: "Gradient vector", preview: "∇f(x)", latex: "$\\nabla f(x)$", category: "Calculus" },
  { id: "matrix-3", title: "3 × 3 Matrix", description: "Three-dimensional matrix", preview: "[ a  b  c ]\n[ d  e  f ]", latex: "$\\begin{pmatrix}\n  a & b & c \\\\\n  d & e & f \\\\\n  g & h & i\n\\end{pmatrix}$", category: "Linear Algebra" },
  { id: "determinant", title: "Determinant", description: "Matrix determinant", preview: "det(A)", latex: "$\\det(A) = \\begin{vmatrix}\n  a & b \\\\\n  c & d\n\\end{vmatrix}$", category: "Linear Algebra" },
  { id: "vector", title: "Vector", description: "Column vector", preview: "v⃗ = [x y z]ᵀ", latex: "$\\mathbf{v} = \\begin{pmatrix} x \\\\ y \\\\ z \\end{pmatrix}$", category: "Linear Algebra" },
  { id: "dot-product", title: "Dot Product", description: "Inner product of vectors", preview: "u · v", latex: "$\\mathbf{u} \\cdot \\mathbf{v} = \\sum_{i=1}^{n} u_i v_i$", category: "Linear Algebra" },
  { id: "linear-system", title: "Linear System", description: "System of equations", preview: "{ ax + by = c", latex: "$\\begin{cases}\n  ax + by = c, \\\\\n  dx + ey = f.\n\\end{cases}$", category: "Linear Algebra" },
  { id: "binomial", title: "Binomial", description: "Binomial coefficient", preview: "( n over k )", latex: "$\\binom{n}{k} = \\frac{n!}{k!(n-k)!}$", category: "Structures" },
  { id: "set-builder", title: "Set Builder", description: "Set defined by a condition", preview: "{ x ∈ ℝ | … }", latex: "$\\{x \\in \\mathbb{R} \\mid x > 0\\}$", category: "Structures" },
  { id: "expectation", title: "Expectation", description: "Expected value", preview: "E[X]", latex: "$\\mathbb{E}[X] = \\sum_x x\\,\\mathbb{P}(X=x)$", category: "Structures" },
  { id: "norm", title: "Vector Norm", description: "Euclidean norm", preview: "‖x‖₂", latex: "$\\lVert \\mathbf{x} \\rVert_2 = \\sqrt{\\sum_i x_i^2}$", category: "Structures" },
];

export function filterMathSnippets(category: MathSnippetCategory): LatexSnippet[] {
  return category === "Popular"
    ? mathSnippets.filter((snippet) => snippet.featured)
    : mathSnippets.filter((snippet) => snippet.category === category);
}

export const blockSnippets: LatexSnippet[] = [
  { id: "note", title: "Note", description: "A calm informational callout", preview: "Note", latex: colorBlock("Note", "blue!5!white", "blue!55!black"), requires: "tcolorbox", tone: "blue" },
  { id: "important", title: "Important", description: "Emphasize a key statement", preview: "Important", latex: colorBlock("Important", "orange!8!white", "orange!70!black"), requires: "tcolorbox", tone: "orange" },
  { id: "definition", title: "Definition", description: "Highlight a new concept", preview: "Definition", latex: colorBlock("Definition", "violet!5!white", "violet!60!black"), requires: "tcolorbox", tone: "violet" },
  { id: "warning", title: "Warning", description: "Call attention to a pitfall", preview: "Warning", latex: colorBlock("Warning", "red!5!white", "red!60!black"), requires: "tcolorbox", tone: "red" },
  { id: "result", title: "Result", description: "Present a conclusion or result", preview: "Result", latex: colorBlock("Result", "green!5!white", "green!50!black"), requires: "tcolorbox", tone: "green" },
  { id: "example", title: "Example", description: "Separate a worked example", preview: "Example", latex: colorBlock("Example", "gray!7!white", "gray!60!black"), requires: "tcolorbox", tone: "neutral" },
  { id: "quote", title: "Quotation", description: "Indented quotation with author", preview: "“ … ”", latex: "\\begin{quote}\n  \\itshape Your quotation here.\n  \\hfill --- Author\n\\end{quote}", tone: "neutral" },
  { id: "highlight", title: "Text Highlight", description: "Highlight a short phrase", preview: "Highlighted", latex: "% Requires \\usepackage{xcolor}\n\\colorbox{yellow!35}{Highlighted text}", requires: "xcolor", tone: "orange" },
];

export const figureSnippets: LatexSnippet[] = [
  { id: "figure-full", title: "Full-width Figure", description: "Centered at 90% text width", preview: "90%", latex: figureSnippet("0.9") },
  { id: "figure-half", title: "Half-width Figure", description: "Compact centered figure", preview: "48%", latex: figureSnippet("0.48") },
  { id: "figure-pair", title: "Side-by-side Figures", description: "Two figures in one row", preview: "▧  ▧", latex: twoFiguresSnippet() },
];

export function createStyledTableLatex(rows: number, columns: number, options: StyledTableOptions): string {
  const safeRows = Math.max(1, Math.min(8, Math.round(rows)));
  const safeColumns = Math.max(1, Math.min(8, Math.round(columns)));
  const alignment = options.alignment === "left" ? "l" : options.alignment === "right" ? "r" : "c";
  const columnSpec = options.gridLines
    ? "|" + Array.from({ length: safeColumns }, () => alignment).join("|") + "|"
    : alignment.repeat(safeColumns);
  const tableRows = Array.from({ length: safeRows }, (_, row) => {
    const cells = Array.from({ length: safeColumns }, (_, column) =>
      options.headerRow && row === 0 ? "\\textbf{Header " + (column + 1) + "}" : "Cell " + (row + 1) + "." + (column + 1),
    ).join(" & ");
    const line = "    " + cells + " \\\\";
    return options.gridLines ? line + "\n    \\hline" : line;
  }).join("\n");
  return [
    "\\begin{table}[ht]",
    "  \\centering",
    "  \\begin{tabular}{" + columnSpec + "}",
    "    \\hline",
    tableRows,
    options.gridLines ? "" : "    \\hline",
    "  \\end{tabular}",
    "  \\caption{Caption}",
    "  \\label{tab:example}",
    "\\end{table}",
  ].filter(Boolean).join("\n");
}

function colorBlock(title: string, background: string, frame: string): string {
  return [
    "% Requires \\usepackage[most]{tcolorbox}",
    "\\begin{tcolorbox}[",
    "  title=" + title + ",",
    "  colback=" + background + ",",
    "  colframe=" + frame + ",",
    "  boxrule=0.6pt,",
    "  arc=2mm",
    "]",
    "  Your text here.",
    "\\end{tcolorbox}",
  ].join("\n");
}

function figureSnippet(width: string): string {
  return [
    "\\begin{figure}[ht]",
    "  \\centering",
    "  \\includegraphics[width=" + width + "\\textwidth]{image.pdf}",
    "  \\caption{Caption}",
    "  \\label{fig:example}",
    "\\end{figure}",
  ].join("\n");
}

function twoFiguresSnippet(): string {
  return [
    "\\begin{figure}[ht]",
    "  \\centering",
    "  \\begin{minipage}{0.48\\textwidth}",
    "    \\includegraphics[width=\\linewidth]{first.pdf}",
    "    \\caption{First caption}",
    "  \\end{minipage}\\hfill",
    "  \\begin{minipage}{0.48\\textwidth}",
    "    \\includegraphics[width=\\linewidth]{second.pdf}",
    "    \\caption{Second caption}",
    "  \\end{minipage}",
    "\\end{figure}",
  ].join("\n");
}
