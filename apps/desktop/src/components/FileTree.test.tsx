import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import type { ProjectEntry } from "../types";
import { FileTree } from "./FileTree";

const entries: ProjectEntry[] = [{
  name: "chapters",
  relativePath: "chapters",
  isDirectory: true,
  children: [{
    name: "part-one",
    relativePath: "chapters/part-one",
    isDirectory: true,
    children: [{ name: "algebra.tex", relativePath: "chapters/part-one/algebra.tex", isDirectory: false, children: [] }],
  }],
}];

describe("FileTree build errors", () => {
  it("reveals a nested problem file and marks its ancestor folders", () => {
    const onOpen = vi.fn();
    const noop = vi.fn();
    render(<FileTree
      entries={entries}
      selectedPath={null}
      mainDocument={null}
      errorPaths={new Set(["chapters", "chapters/part-one", "chapters/part-one/algebra.tex"])}
      onOpen={onOpen}
      onCreateFile={noop}
      onCreateFolder={noop}
      onUpload={noop}
      onRename={noop}
      onDuplicate={noop}
      onTrash={noop}
      onSetMain={noop}
      onMove={noop}
      onReveal={noop}
    />);

    expect(screen.getByRole("img", { name: "Contains build errors in chapters" })).toBeInTheDocument();
    expect(screen.getByRole("img", { name: "Contains build errors in part-one" })).toBeInTheDocument();
    expect(screen.getByRole("img", { name: "Build error in algebra.tex" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "algebra.tex" }));
    expect(onOpen).toHaveBeenCalledWith("chapters/part-one/algebra.tex");
  });
});
