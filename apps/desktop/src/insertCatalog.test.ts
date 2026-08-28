import { describe, expect, it } from "vitest";
import { createTableLatex, filterSymbols, latexSymbols } from "./insertCatalog";

describe("insert catalog", () => {
  it("contains a broad searchable symbol catalog", () => {
    expect(latexSymbols.length).toBeGreaterThan(100);
    expect(filterSymbols("lambda", "All").some((item) => item.latex === "\\lambda")).toBe(true);
    expect(filterSymbols("arrow", "Arrows").length).toBeGreaterThan(5);
  });

  it("filters within the selected category", () => {
    const results = filterSymbols("subset", "Relations");
    expect(results.map((item) => item.latex)).toContain("\\subseteq");
    expect(results.every((item) => item.category === "Relations")).toBe(true);
  });

  it("creates the requested table dimensions", () => {
    const latex = createTableLatex(2, 3);
    expect(latex).toContain("\\begin{tabular}{ccc}");
    expect(latex).toContain("Cell 2.3");
    expect(latex.match(/\\\\/g)).toHaveLength(2);
  });

  it("clamps table dimensions to the supported picker", () => {
    const latex = createTableLatex(20, 0);
    expect(latex).toContain("\\begin{tabular}{c}");
    expect(latex).toContain("Cell 8.1");
    expect(latex).not.toContain("Cell 9.1");
  });
});
