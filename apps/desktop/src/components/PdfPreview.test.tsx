import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import type { BuildFailurePresentation } from "../buildDiagnostics";
import { PdfPreview } from "./PdfPreview";

const failure: BuildFailurePresentation = {
  title: "PDF could not be generated",
  detail: "This project requires XeLaTeX, but LuaLaTeX is selected.",
  location: "styles/mathnotes.sty",
  suggestedEngine: "xeLaTex",
  log: "! Package mathnotes Error: This template requires XeLaTeX.",
};

function renderPreview(onRecover = vi.fn()) {
  return render(<PdfPreview
    base64={null}
    failure={failure}
    target={null}
    outline={[]}
    onOutlinePages={() => {}}
    onInverse={() => {}}
    onRecover={onRecover}
  />);
}

describe("PDF build recovery", () => {
  it("shows a persistent explanation while keeping the log closed initially", () => {
    renderPreview();

    expect(screen.getByRole("alert")).toHaveTextContent("PDF could not be generated");
    expect(screen.getByText("Failed")).toBeInTheDocument();
    expect(screen.queryByRole("dialog", { name: "Build Log" })).not.toBeInTheDocument();
  });

  it("opens the floating log only after View Log and closes it with Escape", () => {
    renderPreview();
    const viewLog = screen.getByRole("button", { name: "View Log" });

    fireEvent.click(viewLog);
    expect(screen.getByRole("dialog", { name: "Build Log" })).toHaveTextContent("requires XeLaTeX");

    fireEvent.keyDown(window, { key: "Escape" });
    expect(screen.queryByRole("dialog", { name: "Build Log" })).not.toBeInTheDocument();
    expect(viewLog).toHaveFocus();
  });

  it("offers the detected engine switch as the primary recovery action", () => {
    const onRecover = vi.fn();
    renderPreview(onRecover);

    fireEvent.click(screen.getByRole("button", { name: "Switch to XeLaTeX & Recompile" }));
    expect(onRecover).toHaveBeenCalledWith("xeLaTex");
  });
});
