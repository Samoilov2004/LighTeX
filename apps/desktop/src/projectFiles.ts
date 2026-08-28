import type { ProjectEntry } from "./types";

export function findExistingProjectPdf(entries: ProjectEntry[], mainDocument: string | null): string | null {
  if (!mainDocument) return null;
  const dot = mainDocument.lastIndexOf(".");
  const relativePath = `${dot > mainDocument.lastIndexOf("/") ? mainDocument.slice(0, dot) : mainDocument}.pdf`;
  return containsFile(entries, relativePath) ? relativePath : null;
}

function containsFile(entries: ProjectEntry[], relativePath: string): boolean {
  return entries.some((entry) => (
    (!entry.isDirectory && entry.relativePath === relativePath)
    || containsFile(entry.children, relativePath)
  ));
}
