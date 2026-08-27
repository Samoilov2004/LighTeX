import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";
import { ProjectHub } from "./ProjectHub";
import { defaultConfig } from "../types";
import { useAppStore } from "../store";

describe("ProjectHub", () => {
  beforeEach(() => useAppStore.setState({ config: defaultConfig, phase: "hub", settingsOpen: false }));

  it("keeps personal templates first and has no unnecessary template search", () => {
    render(<ProjectHub />);
    expect(screen.getByRole("heading", { name: "Yours" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "LighTex Templates" })).toBeInTheDocument();
    expect(screen.queryByPlaceholderText(/search templates/i)).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create Template" })).toBeEnabled();
  });

  it("opens the single Settings surface", () => {
    render(<ProjectHub />);
    fireEvent.click(screen.getByRole("button", { name: "Open Settings" }));
    expect(useAppStore.getState().settingsOpen).toBe(true);
  });
});
