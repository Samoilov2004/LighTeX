import { describe, expect, it } from "vitest";
import { blockSnippets, createStyledTableLatex, filterMathSnippets, mathSnippets } from "./insertSnippets";

describe("insert snippets", () => {
  it("provides a broad, categorized math catalog", () => {
    expect(mathSnippets.length).toBeGreaterThan(20);
    expect(filterMathSnippets("Popular").some((snippet) => snippet.id === "integral")).toBe(true);
    expect(filterMathSnippets("Calculus").every((snippet) => snippet.category === "Calculus")).toBe(true);
    expect(filterMathSnippets("Linear Algebra").some((snippet) => snippet.id === "matrix-3")).toBe(true);
  });

  it("keeps colored block dependencies visible in inserted LaTeX", () => {
    expect(blockSnippets.length).toBeGreaterThanOrEqual(8);
    expect(blockSnippets.find((snippet) => snippet.id === "warning")?.latex).toContain("tcolorbox");
    expect(blockSnippets.find((snippet) => snippet.id === "highlight")?.latex).toContain("xcolor");
  });

  it("creates headers, alignment, and grid lines from table options", () => {
    const latex = createStyledTableLatex(2, 3, { alignment: "right", headerRow: true, gridLines: true });
    expect(latex).toContain("\\begin{tabular}{|r|r|r|}");
    expect(latex).toContain("\\textbf{Header 3}");
    expect(latex).toContain("Cell 2.3");
    expect(latex.match(/\\\\/g)).toHaveLength(2);
  });
});
