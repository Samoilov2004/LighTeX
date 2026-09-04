import type { BuildDiagnostic, BuildResult, LatexEngine, ProjectEntry } from "./types";

export interface BuildDiagnosticTarget {
  relativePath: string;
  line?: number;
}

export interface BuildFailurePresentation {
  title: string;
  detail: string;
  location: string | null;
  suggestedEngine: LatexEngine | null;
  log: string;
}

export function firstBuildDiagnosticTarget(result: BuildResult | null, entries: ProjectEntry[]): BuildDiagnosticTarget | null {
  for (const diagnostic of diagnostics(result)) {
    if (diagnostic.severity !== "error" || !diagnostic.relativePath || !hasEntry(entries, diagnostic.relativePath)) continue;
    return {
      relativePath: diagnostic.relativePath,
      line: diagnostic.line ?? undefined,
    };
  }
  return null;
}

export function buildErrorEntryPaths(result: BuildResult | null): ReadonlySet<string> {
  const paths = new Set<string>();
  for (const diagnostic of diagnostics(result)) {
    if (diagnostic.severity !== "error" || !diagnostic.relativePath) continue;
    const parts = diagnostic.relativePath.split("/").filter(Boolean);
    for (let length = parts.length; length > 0; length -= 1) {
      paths.add(parts.slice(0, length).join("/"));
    }
  }
  return paths;
}

export function hasInlineBuildError(result: BuildResult | null, entries: ProjectEntry[]): boolean {
  return diagnostics(result).some((diagnostic) => diagnostic.severity === "error"
    && Boolean(diagnostic.relativePath)
    && Boolean(diagnostic.line && diagnostic.line > 0)
    && hasEntry(entries, diagnostic.relativePath!));
}

export function buildFailurePresentation(
  result: BuildResult | null,
  entries: ProjectEntry[],
  selectedEngine: LatexEngine,
  fallbackMessage: string | null = null,
): BuildFailurePresentation | null {
  if (result?.succeeded || hasInlineBuildError(result, entries)) return null;
  const allDiagnostics = diagnostics(result);
  const firstError = allDiagnostics.find((diagnostic) => diagnostic.severity === "error");
  const searchableLog = [firstError?.message, result?.log, fallbackMessage].filter(Boolean).join("\n");
  const requiredEngine = requiredLatexEngine(searchableLog);
  const selectedName = latexEngineName(selectedEngine);
  const requiredName = requiredEngine ? latexEngineName(requiredEngine) : null;
  const detail = requiredEngine && requiredEngine !== selectedEngine
    ? `This project requires ${requiredName}, but ${selectedName} is selected.`
    : usefulDiagnosticMessage(firstError?.message)
      ?? usefulDiagnosticMessage(fallbackMessage)
      ?? "The compiler stopped before LighTex could identify a source line.";
  const location = firstError?.relativePath
    ? `${firstError.relativePath}${firstError.line ? `:${firstError.line}` : ""}`
    : null;
  const log = result?.log?.trim() || fallbackMessage?.trim() || "The compiler did not return a build log.";
  return {
    title: "PDF could not be generated",
    detail,
    location,
    suggestedEngine: requiredEngine !== selectedEngine ? requiredEngine : null,
    log,
  };
}

export function diagnosticTargetKey(target: BuildDiagnosticTarget | null): string | null {
  return target ? `${target.relativePath}:${target.line ?? ""}` : null;
}

function diagnostics(result: BuildResult | null): BuildDiagnostic[] {
  return (result?.diagnostics ?? []).flatMap((group) => [group.primary, ...group.related]);
}

function requiredLatexEngine(message: string): LatexEngine | null {
  const compact = message.replace(/\s+/g, "");
  if (/requiresXeLaTeX|requiresXeTeX|useXeLaTeX/i.test(compact)) return "xeLaTex";
  if (/requiresLuaLaTeX|requiresLuaTeX|useLuaLaTeX/i.test(compact)) return "luaLaTex";
  if (/requirespdfLaTeX|usepdfLaTeX/i.test(compact)) return "pdfLaTex";
  return null;
}

function latexEngineName(engine: LatexEngine): string {
  if (engine === "xeLaTex") return "XeLaTeX";
  if (engine === "luaLaTex") return "LuaLaTeX";
  return "pdfLaTeX";
}

function usefulDiagnosticMessage(message: string | null | undefined): string | null {
  if (!message) return null;
  const compact = message.replace(/^(?:Package\s+\S+\s+Error:\s*)/i, "").trim();
  if (!compact || /^(?:Emergency stop|Fatal error occurred|Compilation stopped)/i.test(compact)) return null;
  return compact;
}

function hasEntry(entries: ProjectEntry[], path: string): boolean {
  return entries.some((entry) => entry.relativePath === path || hasEntry(entry.children, path));
}
