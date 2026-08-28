import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { EditorQuickControls } from "./EditorQuickControls";

describe("EditorQuickControls", () => {
  it("exposes Undo state and changes the editor font size", () => {
    const undo = vi.fn();
    const changeFontSize = vi.fn();
    const { rerender } = render(<EditorQuickControls canUndo={false} fontSize={13.5} onUndo={undo} onFontSizeChange={changeFontSize} />);

    expect(screen.getByRole("button", { name: "Undo last edit" })).toBeDisabled();
    expect(screen.getByRole("combobox", { name: "Editor font size" })).toHaveValue("13.5");
    fireEvent.change(screen.getByRole("combobox", { name: "Editor font size" }), { target: { value: "16" } });
    expect(changeFontSize).toHaveBeenCalledWith(16);

    rerender(<EditorQuickControls canUndo fontSize={16} onUndo={undo} onFontSizeChange={changeFontSize} />);
    fireEvent.click(screen.getByRole("button", { name: "Undo last edit" }));
    expect(undo).toHaveBeenCalledOnce();
  });
});
