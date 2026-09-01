import { createRef } from "react";
import { act, render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { defaultConfig } from "../types";
import { SourceEditor, type SourceEditorHandle } from "./SourceEditor";

const emptyCompletion = {
  labels: [],
  citations: [],
  packages: [],
  classes: [],
  inputPaths: [],
  imagePaths: [],
};

describe("SourceEditor history", () => {
  it("undoes the last edit and restores history after switching tabs", () => {
    const firstRef = createRef<SourceEditorHandle>();
    const firstChange = vi.fn();
    const firstAvailability = vi.fn();
    const first = render(
      <SourceEditor
        ref={firstRef}
        path="main.tex"
        historyKey="project:main.tex"
        value="abc"
        config={defaultConfig}
        completion={emptyCompletion}
        onChange={firstChange}
        onUndoAvailabilityChange={firstAvailability}
      />,
    );

    act(() => window.dispatchEvent(new CustomEvent("lightex:insert", { detail: { text: "x" } })));
    expect(firstChange).toHaveBeenLastCalledWith("xabc");
    expect(firstAvailability).toHaveBeenLastCalledWith(true);
    first.unmount();

    const restoredRef = createRef<SourceEditorHandle>();
    const restoredChange = vi.fn();
    const restoredAvailability = vi.fn();
    render(
      <SourceEditor
        ref={restoredRef}
        path="main.tex"
        historyKey="project:main.tex"
        value="xabc"
        config={defaultConfig}
        completion={emptyCompletion}
        onChange={restoredChange}
        onUndoAvailabilityChange={restoredAvailability}
      />,
    );

    expect(restoredAvailability).toHaveBeenLastCalledWith(true);
    act(() => expect(restoredRef.current?.undo()).toBe(true));
    expect(restoredChange).toHaveBeenLastCalledWith("abc");
    expect(restoredAvailability).toHaveBeenLastCalledWith(false);
  });

  it("keeps saved-version documents read only", () => {
    const onChange = vi.fn();
    render(
      <SourceEditor
        path="main.tex"
        historyKey="version:main.tex"
        value="snapshot"
        config={defaultConfig}
        completion={emptyCompletion}
        onChange={onChange}
        readOnly
      />,
    );

    act(() => window.dispatchEvent(new CustomEvent("lightex:insert", { detail: { text: "changed" } })));
    expect(onChange).not.toHaveBeenCalled();
    expect(document.querySelector(".source-editor .cm-content")).toHaveAttribute("aria-readonly", "true");
  });

  it("shows added and removed rows in a saved-version preview", () => {
    const { container } = render(
      <SourceEditor
        path="main.tex"
        historyKey="version:diff:main.tex"
        value={"same\nnew value\nlast\n"}
        config={defaultConfig}
        completion={emptyCompletion}
        onChange={() => {}}
        readOnly
        diff={{
          relativePath: "main.tex",
          additions: 1,
          deletions: 1,
          binary: false,
          lines: [
            { kind: "deletion", text: "old value", oldLine: 2, newLine: null, anchorNewLine: 2 },
            { kind: "addition", text: "new value", oldLine: null, newLine: 2, anchorNewLine: 2 },
          ],
        }}
      />,
    );

    expect(container.querySelector(".cm-version-added-line")).toBeInTheDocument();
    expect(container.querySelector(".cm-version-deleted-row")).toHaveTextContent("old value");
    expect(container.querySelector(".cm-version-added-sign")).toHaveTextContent("+");
  });
});
