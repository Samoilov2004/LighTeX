import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";
import { useAppStore } from "../store";
import type { ProjectVersionSummary } from "../types";
import { SaveVersionDialog, VersionsPanel } from "./VersionsPanel";

const versions: ProjectVersionSummary[] = [
  {
    id: "named-version",
    name: "Complete first draft",
    createdAt: "2026-08-31T18:15:00Z",
    kind: "named",
    mainDocument: "main.tex",
    fileCount: 14,
    totalSize: 24_000,
    previewStatus: "ready",
    previewError: null,
  },
  {
    id: "recovery-version",
    name: "Before restoring “Complete first draft”",
    createdAt: "2026-08-31T19:30:00Z",
    kind: "recovery",
    mainDocument: "main.tex",
    fileCount: 15,
    totalSize: 25_000,
    previewStatus: "failed",
    previewError: "Missing package",
  },
];

describe("VersionsPanel", () => {
  beforeEach(() => useAppStore.setState({ versions, versionsOpen: true, project: null, versionOperation: null }));

  it("separates named snapshots from automatic recovery snapshots", () => {
    render(<VersionsPanel />);
    expect(screen.getByRole("heading", { name: "Saved" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Recovery" })).toBeInTheDocument();
    expect(screen.getByText("Complete first draft")).toBeInTheDocument();
    expect(screen.getByText("PDF ready")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Retry PDF preview/ })).toBeInTheDocument();
  });

  it("closes with Escape and with a click outside the drawer", () => {
    const first = render(<VersionsPanel />);
    fireEvent.keyDown(window, { key: "Escape" });
    expect(useAppStore.getState().versionsOpen).toBe(false);
    first.unmount();

    useAppStore.setState({ versionsOpen: true });
    const second = render(<VersionsPanel />);
    fireEvent.mouseDown(second.container.querySelector(".versions-layer")!);
    expect(useAppStore.getState().versionsOpen).toBe(false);
  });

  it("requires a non-empty version name", () => {
    render(<SaveVersionDialog onClose={() => {}} />);
    const save = screen.getByRole("button", { name: "Save Version" });
    expect(save).toBeDisabled();
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "  Chapter one complete  " } });
    expect(save).toBeEnabled();
  });
});
