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
});
