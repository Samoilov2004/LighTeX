import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { EditorTabs } from "./EditorTabs";

const document = (path: string, dirty = false) => ({
  relativePath: path,
  text: "",
  dirty,
  externalChange: "none" as const,
  revision: { modificationUnixMs: 0, fileSize: 0, fileIdentifier: path, contentHash: path },
});

describe("EditorTabs", () => {
  it("exposes selection, dirty state and keyboard reorder alternatives", () => {
    const move = vi.fn();
    render(<EditorTabs tabs={["main.tex", "notes.tex", "proof.tex"]} selectedPath="main.tex" documents={{ "main.tex": document("main.tex"), "notes.tex": document("notes.tex", true), "proof.tex": document("proof.tex") }} onSelect={() => {}} onClose={() => {}} onReorder={() => {}} onMove={move} onFileDrop={() => {}} />);
    expect(screen.getByRole("tab", { name: /main\.tex/i })).toHaveAttribute("aria-selected", "true");
    fireEvent.contextMenu(screen.getByText("notes.tex"));
    fireEvent.click(screen.getByRole("menuitem", { name: "Move Tab Left" }));
    expect(move).toHaveBeenCalledWith("notes.tex", -1);
    expect(screen.getAllByLabelText("Unsaved changes").length).toBeGreaterThan(0);
  });
});
