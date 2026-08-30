import type { OutlineItem } from "./types";

export const outlineItemKey = (item: Pick<OutlineItem, "relativePath" | "line" | "title">) => `${item.relativePath}:${item.line}:${item.title}`;

export interface PdfBookmarkPage {
  title: string;
  page: number;
}

export function findOutlinePagesFromBookmarks(outline: OutlineItem[], bookmarks: readonly PdfBookmarkPage[]): Record<string, number> {
  const normalizedBookmarks = bookmarks.map((bookmark) => ({ ...bookmark, normalizedTitle: normalizeHeadingText(bookmark.title) }));
  const result: Record<string, number> = {};
  let searchFrom = 0;
  for (const item of outline) {
    const title = normalizeHeadingText(item.title);
    if (title.length < 2) continue;
    let bookmarkIndex = normalizedBookmarks.findIndex((bookmark, index) => index >= searchFrom && titlesMatch(bookmark.normalizedTitle, title));
    if (bookmarkIndex < 0 && searchFrom > 0) bookmarkIndex = normalizedBookmarks.findIndex((bookmark) => titlesMatch(bookmark.normalizedTitle, title));
    if (bookmarkIndex < 0) continue;
    result[outlineItemKey(item)] = normalizedBookmarks[bookmarkIndex].page;
    searchFrom = bookmarkIndex;
  }
  return result;
}

export function findOutlinePages(outline: OutlineItem[], pageTexts: readonly string[]): Record<string, number> {
  const normalizedPages = pageTexts.map(normalizeHeadingText);
  const result: Record<string, number> = {};
  let searchFrom = 0;
  for (const item of outline) {
    const title = normalizeHeadingText(item.title);
    if (title.length < 2) continue;
    const laterMatches = normalizedPages.flatMap((page, index) => index >= searchFrom && page.includes(title) ? [index] : []);
    let pageIndex = laterMatches.length > 0 ? laterMatches[laterMatches.length - 1] : -1;
    if (pageIndex < 0 && searchFrom > 0) {
      for (let index = normalizedPages.length - 1; index >= 0; index -= 1) {
        if (normalizedPages[index].includes(title)) {
          pageIndex = index;
          break;
        }
      }
    }
    if (pageIndex < 0) continue;
    result[outlineItemKey(item)] = pageIndex + 1;
    searchFrom = pageIndex;
  }
  return result;
}

function titlesMatch(bookmark: string, heading: string): boolean {
  return bookmark === heading || bookmark.endsWith(` ${heading}`) || heading.endsWith(` ${bookmark}`);
}

export function normalizeHeadingText(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/\\(?:textbf|textit|texttt|emph|mathrm|mathbf|mathit|operatorname)\s*\{([^{}]*)\}/gu, "$1")
    .replace(/\\[a-zA-Z]+\*?/gu, " ")
    .replace(/[‐‑‒–—−-]+/gu, " ")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .toLocaleLowerCase();
}
