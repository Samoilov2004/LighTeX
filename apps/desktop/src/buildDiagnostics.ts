import type { BuildDiagnostic, BuildResult, ProjectEntry } from "./types";

export interface BuildDiagnosticTarget {
  relativePath: string;
  line?: number;
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

export function diagnosticTargetKey(target: BuildDiagnosticTarget | null): string | null {
  return target ? `${target.relativePath}:${target.line ?? ""}` : null;
}

function diagnostics(result: BuildResult | null): BuildDiagnostic[] {
  return (result?.diagnostics ?? []).flatMap((group) => [group.primary, ...group.related]);
}

function hasEntry(entries: ProjectEntry[], path: string): boolean {
  return entries.some((entry) => entry.relativePath === path || hasEntry(entry.children, path));
}
