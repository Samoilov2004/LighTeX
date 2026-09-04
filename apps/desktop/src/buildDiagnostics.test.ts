import { describe, expect, it } from "vitest";
import type { BuildResult, ProjectEntry } from "./types";
import { buildErrorEntryPaths, buildFailurePresentation, diagnosticTargetKey, firstBuildDiagnosticTarget, hasInlineBuildError } from "./buildDiagnostics";

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

  it("distinguishes errors that can be highlighted from global build failures", () => {
    expect(hasInlineBuildError(result, entries)).toBe(true);
    expect(buildFailurePresentation(result, entries, "luaLaTex")).toBeNull();
  });

  it("explains an engine mismatch when no source line can be highlighted", () => {
    const unmapped: BuildResult = {
      ...result,
      diagnostics: [{
        primary: { severity: "error", relativePath: "styles/mathnotes.sty", line: null, message: "This template requires XeLaTeX." },
        related: [],
      }],
      log: "./styles/mathnotes.sty: Package mathnotes Error: This template requires XeLaT\neX.",
    };

    expect(buildFailurePresentation(unmapped, entries, "luaLaTex")).toEqual({
      title: "PDF could not be generated",
      detail: "This project requires XeLaTeX, but LuaLaTeX is selected.",
      location: "styles/mathnotes.sty",
      suggestedEngine: "xeLaTex",
      log: unmapped.log,
    });
  });

  it("always provides a useful fallback for an unknown compiler failure", () => {
    expect(buildFailurePresentation(null, entries, "pdfLaTex", "Process exited with code 1")).toMatchObject({
      title: "PDF could not be generated",
      detail: "Process exited with code 1",
      suggestedEngine: null,
    });
  });
});
