export type SymbolCategory = "Greek" | "Relations" | "Operators" | "Arrows" | "Sets" | "Calculus" | "Logic" | "Delimiters" | "Misc";

export interface LatexSymbol {
  glyph: string;
  latex: string;
  name: string;
  category: SymbolCategory;
  keywords?: string;
}

const greek = (glyph: string, latex: string, name: string): LatexSymbol => ({ glyph, latex, name, category: "Greek" });
const symbol = (glyph: string, latex: string, name: string, category: SymbolCategory, keywords?: string): LatexSymbol => ({ glyph, latex, name, category, keywords });

export const latexSymbols: LatexSymbol[] = [
  greek("α", "\\alpha", "alpha"), greek("β", "\\beta", "beta"), greek("γ", "\\gamma", "gamma"),
  greek("δ", "\\delta", "delta"), greek("ε", "\\epsilon", "epsilon"), greek("ϵ", "\\varepsilon", "variant epsilon"),
  greek("ζ", "\\zeta", "zeta"), greek("η", "\\eta", "eta"), greek("θ", "\\theta", "theta"),
  greek("ϑ", "\\vartheta", "variant theta"), greek("ι", "\\iota", "iota"), greek("κ", "\\kappa", "kappa"),
  greek("λ", "\\lambda", "lambda"), greek("μ", "\\mu", "mu"), greek("ν", "\\nu", "nu"),
  greek("ξ", "\\xi", "xi"), greek("π", "\\pi", "pi"), greek("ϖ", "\\varpi", "variant pi"),
  greek("ρ", "\\rho", "rho"), greek("ϱ", "\\varrho", "variant rho"), greek("σ", "\\sigma", "sigma"),
  greek("ς", "\\varsigma", "final sigma"), greek("τ", "\\tau", "tau"), greek("υ", "\\upsilon", "upsilon"),
  greek("φ", "\\phi", "phi"), greek("ϕ", "\\varphi", "variant phi"), greek("χ", "\\chi", "chi"),
  greek("ψ", "\\psi", "psi"), greek("ω", "\\omega", "omega"), greek("Γ", "\\Gamma", "capital gamma"),
  greek("Δ", "\\Delta", "capital delta"), greek("Θ", "\\Theta", "capital theta"), greek("Λ", "\\Lambda", "capital lambda"),
  greek("Ξ", "\\Xi", "capital xi"), greek("Π", "\\Pi", "capital pi"), greek("Σ", "\\Sigma", "capital sigma"),
  greek("Υ", "\\Upsilon", "capital upsilon"), greek("Φ", "\\Phi", "capital phi"), greek("Ψ", "\\Psi", "capital psi"),
  greek("Ω", "\\Omega", "capital omega"),

  symbol("≠", "\\neq", "not equal", "Relations", "inequality"), symbol("≈", "\\approx", "approximately equal", "Relations"),
  symbol("∼", "\\sim", "similar", "Relations"), symbol("≃", "\\simeq", "similar or equal", "Relations"),
  symbol("≡", "\\equiv", "equivalent", "Relations"), symbol("≤", "\\leq", "less than or equal", "Relations"),
  symbol("≥", "\\geq", "greater than or equal", "Relations"), symbol("≪", "\\ll", "much less than", "Relations"),
  symbol("≫", "\\gg", "much greater than", "Relations"), symbol("∝", "\\propto", "proportional to", "Relations"),
  symbol("∥", "\\parallel", "parallel", "Relations"), symbol("⊥", "\\perp", "perpendicular", "Relations"),
  symbol("∈", "\\in", "element of", "Relations", "belongs member"), symbol("∉", "\\notin", "not an element of", "Relations"),
  symbol("∋", "\\ni", "contains as member", "Relations"), symbol("⊂", "\\subset", "proper subset", "Relations"),
  symbol("⊆", "\\subseteq", "subset or equal", "Relations"), symbol("⊃", "\\supset", "proper superset", "Relations"),
  symbol("⊇", "\\supseteq", "superset or equal", "Relations"), symbol("≺", "\\prec", "precedes", "Relations"),
  symbol("≻", "\\succ", "succeeds", "Relations"),

  symbol("±", "\\pm", "plus or minus", "Operators"), symbol("∓", "\\mp", "minus or plus", "Operators"),
  symbol("×", "\\times", "multiplication", "Operators"), symbol("÷", "\\div", "division", "Operators"),
  symbol("⋅", "\\cdot", "centered dot", "Operators"), symbol("∗", "\\ast", "asterisk operator", "Operators"),
  symbol("⋆", "\\star", "star operator", "Operators"), symbol("∘", "\\circ", "composition", "Operators"),
  symbol("∙", "\\bullet", "bullet operator", "Operators"), symbol("⊕", "\\oplus", "direct sum", "Operators"),
  symbol("⊗", "\\otimes", "tensor product", "Operators"), symbol("⊙", "\\odot", "circled dot", "Operators"),
  symbol("∑", "\\sum", "summation", "Operators", "sigma total"), symbol("∏", "\\prod", "product", "Operators"),
  symbol("∐", "\\coprod", "coproduct", "Operators"), symbol("√", "\\sqrt{}", "square root", "Operators", "radical"),

  symbol("→", "\\to", "right arrow", "Arrows"), symbol("←", "\\leftarrow", "left arrow", "Arrows"),
  symbol("↔", "\\leftrightarrow", "left right arrow", "Arrows"), symbol("⇒", "\\Rightarrow", "double right arrow", "Arrows", "implies"),
  symbol("⇐", "\\Leftarrow", "double left arrow", "Arrows"), symbol("⇔", "\\Leftrightarrow", "double left right arrow", "Arrows", "iff"),
  symbol("↦", "\\mapsto", "maps to", "Arrows"), symbol("↪", "\\hookrightarrow", "hook right arrow", "Arrows"),
  symbol("↩", "\\hookleftarrow", "hook left arrow", "Arrows"), symbol("↑", "\\uparrow", "up arrow", "Arrows"),
  symbol("↓", "\\downarrow", "down arrow", "Arrows"), symbol("↕", "\\updownarrow", "up down arrow", "Arrows"),
  symbol("↗", "\\nearrow", "north east arrow", "Arrows"), symbol("↖", "\\nwarrow", "north west arrow", "Arrows"),
  symbol("↘", "\\searrow", "south east arrow", "Arrows"), symbol("↙", "\\swarrow", "south west arrow", "Arrows"),

  symbol("∅", "\\emptyset", "empty set", "Sets", "null set"), symbol("ℕ", "\\mathbb{N}", "natural numbers", "Sets"),
  symbol("ℤ", "\\mathbb{Z}", "integers", "Sets"), symbol("ℚ", "\\mathbb{Q}", "rational numbers", "Sets"),
  symbol("ℝ", "\\mathbb{R}", "real numbers", "Sets"), symbol("ℂ", "\\mathbb{C}", "complex numbers", "Sets"),
  symbol("∪", "\\cup", "union", "Sets"), symbol("∩", "\\cap", "intersection", "Sets"),
  symbol("∖", "\\setminus", "set difference", "Sets"), symbol("∁", "\\complement", "complement", "Sets"),
  symbol("℘", "\\mathcal{P}", "power set", "Sets"),

  symbol("∞", "\\infty", "infinity", "Calculus"), symbol("∂", "\\partial", "partial derivative", "Calculus"),
  symbol("∇", "\\nabla", "nabla gradient", "Calculus", "del"), symbol("∫", "\\int", "integral", "Calculus"),
  symbol("∬", "\\iint", "double integral", "Calculus"), symbol("∭", "\\iiint", "triple integral", "Calculus"),
  symbol("∮", "\\oint", "contour integral", "Calculus"), symbol("lim", "\\lim", "limit", "Calculus"),
  symbol("′", "\\prime", "prime derivative", "Calculus"), symbol("d", "\\mathrm{d}", "differential d", "Calculus"),

  symbol("∀", "\\forall", "for all", "Logic"), symbol("∃", "\\exists", "there exists", "Logic"),
  symbol("∄", "\\nexists", "does not exist", "Logic"), symbol("¬", "\\neg", "logical not", "Logic"),
  symbol("∧", "\\land", "logical and", "Logic"), symbol("∨", "\\lor", "logical or", "Logic"),
  symbol("∴", "\\therefore", "therefore", "Logic"), symbol("∵", "\\because", "because", "Logic"),
  symbol("⊤", "\\top", "true top", "Logic"), symbol("⊥", "\\bot", "false bottom", "Logic"),
  symbol("⊢", "\\vdash", "proves", "Logic"), symbol("⊨", "\\models", "models entails", "Logic"),

  symbol("⟨", "\\langle", "left angle bracket", "Delimiters"), symbol("⟩", "\\rangle", "right angle bracket", "Delimiters"),
  symbol("⌊", "\\lfloor", "left floor", "Delimiters"), symbol("⌋", "\\rfloor", "right floor", "Delimiters"),
  symbol("⌈", "\\lceil", "left ceiling", "Delimiters"), symbol("⌉", "\\rceil", "right ceiling", "Delimiters"),
  symbol("|", "\\vert", "vertical bar", "Delimiters"), symbol("‖", "\\Vert", "double vertical bar", "Delimiters"),
  symbol("{", "\\{", "left brace", "Delimiters"), symbol("}", "\\}", "right brace", "Delimiters"),

  symbol("ℵ", "\\aleph", "aleph", "Misc"), symbol("ℏ", "\\hbar", "reduced Planck constant", "Misc"),
  symbol("ℓ", "\\ell", "script ell", "Misc"), symbol("ℜ", "\\Re", "real part", "Misc"),
  symbol("ℑ", "\\Im", "imaginary part", "Misc"), symbol("°", "^{\\circ}", "degree", "Misc"),
  symbol("△", "\\triangle", "triangle", "Misc"), symbol("□", "\\square", "square", "Misc"),
  symbol("■", "\\blacksquare", "black square", "Misc"), symbol("…", "\\ldots", "low ellipsis", "Misc"),
  symbol("⋯", "\\cdots", "centered ellipsis", "Misc"), symbol("⋮", "\\vdots", "vertical ellipsis", "Misc"),
  symbol("⋱", "\\ddots", "diagonal ellipsis", "Misc"),
];

export const symbolCategories: Array<"All" | SymbolCategory> = ["All", "Greek", "Relations", "Operators", "Arrows", "Sets", "Calculus", "Logic", "Delimiters", "Misc"];

export function filterSymbols(query: string, category: "All" | SymbolCategory): LatexSymbol[] {
  const terms = query.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
  return latexSymbols.filter((item) => {
    if (category !== "All" && item.category !== category) return false;
    if (terms.length === 0) return true;
    const haystack = `${item.glyph} ${item.latex} ${item.name} ${item.category} ${item.keywords ?? ""}`.toLocaleLowerCase();
    return terms.every((term) => haystack.includes(term));
  });
}

export function createTableLatex(rows: number, columns: number): string {
  const safeRows = Math.max(1, Math.min(8, Math.round(rows)));
  const safeColumns = Math.max(1, Math.min(8, Math.round(columns)));
  const body = Array.from({ length: safeRows }, (_, row) =>
    `    ${Array.from({ length: safeColumns }, (_, column) => `Cell ${row + 1}.${column + 1}`).join(" & ")} \\\\`,
  ).join("\n");
  return `\\begin{table}[ht]\n  \\centering\n  \\begin{tabular}{${"c".repeat(safeColumns)}}\n    \\hline\n${body}\n    \\hline\n  \\end{tabular}\n  \\caption{Caption}\n  \\label{tab:example}\n\\end{table}`;
}
