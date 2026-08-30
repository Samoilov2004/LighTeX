import { describe, expect, it } from "vitest";
import { findOutlinePages, findOutlinePagesFromBookmarks, normalizeHeadingText } from "./outlinePages";

describe("outline PDF page mapping", () => {
  it("finds headings in extracted PDF text and preserves document order", () => {
    const outline = [
      { relativePath: "main.tex", line: 8, title: "Introduction", level: 2 },
      { relativePath: "main.tex", line: 24, title: "Energy--Norm Estimates", level: 2 },
      { relativePath: "main.tex", line: 37, title: "Proof Strategy", level: 3 },
    ];
    expect(findOutlinePages(outline, [
      "1 Introduction Some opening text",
      "2 Energy–Norm Estimates",
      "2.1 Proof Strategy Details",
    ])).toEqual({
      "main.tex:8:Introduction": 1,
      "main.tex:24:Energy--Norm Estimates": 2,
      "main.tex:37:Proof Strategy": 3,
    });
  });

  it("normalizes common LaTeX formatting in headings", () => {
    expect(normalizeHeadingText("The \\textbf{Main} $L^2$ Result")).toBe("the main l 2 result");
  });

  it("prefers actual heading occurrences over duplicates on a printed contents page", () => {
    const outline = [
      { relativePath: "main.tex", line: 8, title: "Introduction", level: 2 },
      { relativePath: "main.tex", line: 24, title: "Methods", level: 2 },
    ];
    expect(findOutlinePages(outline, ["Contents Introduction Methods", "1 Introduction", "2 Methods"])).toEqual({
      "main.tex:8:Introduction": 2,
      "main.tex:24:Methods": 3,
    });
  });

  it("maps nested PDF bookmarks to source headings", () => {
    const outline = [
      { relativePath: "main.tex", line: 8, title: "Introduction", level: 2 },
      { relativePath: "main.tex", line: 24, title: "Methods", level: 2 },
    ];
    expect(findOutlinePagesFromBookmarks(outline, [
      { title: "1 Introduction", page: 2 },
      { title: "2 Methods", page: 4 },
    ])).toEqual({
      "main.tex:8:Introduction": 2,
      "main.tex:24:Methods": 4,
    });
  });
});
