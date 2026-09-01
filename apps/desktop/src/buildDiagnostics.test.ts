import { describe, expect, it } from "vitest";
import type { BuildResult, ProjectEntry } from "./types";
import { buildErrorEntryPaths, diagnosticTargetKey, firstBuildDiagnosticTarget } from "./buildDiagnostics";

const entries: ProjectEntry[] = [{
  name: "chapters",
  relativePath: "chapters",
  isDirectory: true,
  children: [{ name: "algebra.tex", relativePath: "chapters/algebra.tex", isDirectory: false, children: [] }],
}];

const result: BuildResult = {
  succeeded: false,
  log: "",
  previewPdfPath: null,
  projectPdfPath: null,
  missingPackageFile: null,
  diagnostics: [
    { primary: { severity: "error", relativePath: null, line: null, message: "Compiler stopped" }, related: [] },
    { primary: { severity: "error", relativePath: "chapters/algebra.tex", line: 42, message: "Undefined control sequence" }, related: [] },
    { primary: { severity: "warning", relativePath: "main.tex", line: 2, message: "Reference changed" }, related: [] },
  ],
};

describe("build diagnostics navigation", () => {
  it("selects the first navigable error in a nested project file", () => {
    const target = firstBuildDiagnosticTarget(result, entries);
    expect(target).toEqual({ relativePath: "chapters/algebra.tex", line: 42 });
    expect(diagnosticTargetKey(target)).toBe("chapters/algebra.tex:42");
  });

  it("marks the error file and each parent folder without marking warnings", () => {
    expect([...buildErrorEntryPaths(result)]).toEqual(["chapters/algebra.tex", "chapters"]);
  });
});
