import { describe, expect, it } from "vitest";
import type { ProjectEntry } from "./types";
import { findExistingProjectPdf } from "./projectFiles";

const entries: ProjectEntry[] = [
  { name: "main.tex", relativePath: "main.tex", isDirectory: false, children: [] },
  { name: "main.pdf", relativePath: "main.pdf", isDirectory: false, children: [] },
  {
    name: "chapters",
    relativePath: "chapters",
    isDirectory: true,
    children: [
      { name: "article.tex", relativePath: "chapters/article.tex", isDirectory: false, children: [] },
      { name: "article.pdf", relativePath: "chapters/article.pdf", isDirectory: false, children: [] },
    ],
  },
];

describe("findExistingProjectPdf", () => {
  it("finds the PDF next to the main document", () => {
    expect(findExistingProjectPdf(entries, "main.tex")).toBe("main.pdf");
    expect(findExistingProjectPdf(entries, "chapters/article.tex")).toBe("chapters/article.pdf");
  });

  it("does not substitute an unrelated PDF", () => {
    expect(findExistingProjectPdf(entries, "missing.tex")).toBeNull();
    expect(findExistingProjectPdf(entries, null)).toBeNull();
  });
});
