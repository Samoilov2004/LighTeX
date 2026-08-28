import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { EditorTabs } from "./EditorTabs";

const editorDocument = (path: string, dirty = false) => ({
  relativePath: path,
  text: "",
  dirty,
  externalChange: "none" as const,
  revision: { modificationUnixMs: 0, fileSize: 0, fileIdentifier: path, contentHash: path },
});

describe("EditorTabs", () => {
  it("exposes selection, dirty state and keyboard reorder alternatives", () => {
    const move = vi.fn();
    render(<EditorTabs tabs={["main.tex", "notes.tex", "proof.tex"]} selectedPath="main.tex" documents={{ "main.tex": editorDocument("main.tex"), "notes.tex": editorDocument("notes.tex", true), "proof.tex": editorDocument("proof.tex") }} onSelect={() => {}} onClose={() => {}} onReorder={() => {}} onMove={move} onFileDrop={() => {}} />);
    expect(screen.getByRole("tab", { name: /main\.tex/i })).toHaveAttribute("aria-selected", "true");
    fireEvent.contextMenu(screen.getByText("notes.tex"));
    fireEvent.click(screen.getByRole("menuitem", { name: "Move Tab Left" }));
    expect(move).toHaveBeenCalledWith("notes.tex", -1);
    expect(screen.getAllByLabelText("Unsaved changes").length).toBeGreaterThan(0);
  });

  it("dismisses the overflow menu and restores focus with Escape", async () => {
    const select = vi.fn();
    render(<EditorTabs tabs={["main.tex", "notes.tex", "proof.tex"]} selectedPath="notes.tex" documents={{ "main.tex": editorDocument("main.tex"), "notes.tex": editorDocument("notes.tex", true), "proof.tex": editorDocument("proof.tex") }} onSelect={select} onClose={() => {}} onReorder={() => {}} onMove={() => {}} onFileDrop={() => {}} />);
    const trigger = screen.getByRole("button", { name: "All open files" });

    fireEvent.click(trigger);
    await waitFor(() => expect(screen.getByRole("menuitem", { name: /notes\.tex/i })).toHaveFocus());
    fireEvent.keyDown(screen.getByRole("menu"), { key: "ArrowDown" });
    expect(screen.getByRole("menuitem", { name: /proof\.tex/i })).toHaveFocus();
    fireEvent.keyDown(window, { key: "Escape" });
    expect(screen.queryByRole("menu")).not.toBeInTheDocument();
    expect(trigger).toHaveFocus();

    fireEvent.click(trigger);
    await screen.findByRole("menu");
    fireEvent.pointerDown(document.body);
    expect(screen.queryByRole("menu")).not.toBeInTheDocument();

    fireEvent.click(trigger);
    await screen.findByRole("menu");
    fireEvent.click(screen.getByRole("menuitem", { name: /main\.tex/i }));
    expect(select).toHaveBeenCalledWith("main.tex");
    expect(screen.queryByRole("menu")).not.toBeInTheDocument();
  });
});
