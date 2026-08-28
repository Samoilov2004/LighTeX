import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";
import { ProjectHub } from "./ProjectHub";
import { defaultConfig } from "../types";
import { useAppStore } from "../store";

describe("ProjectHub", () => {
  beforeEach(() => useAppStore.setState({ config: defaultConfig, phase: "hub", settingsOpen: false }));

  it("keeps templates off the Projects screen and opens the dedicated Templates screen", () => {
    render(<ProjectHub />);
    expect(screen.queryByRole("heading", { name: "Yours" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "New from Template" }));
    expect(screen.getByRole("heading", { name: "Templates" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Yours" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "LighTex Templates" })).toBeInTheDocument();
    expect(screen.queryByPlaceholderText(/search templates/i)).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create Template" })).toBeEnabled();
    fireEvent.click(screen.getByRole("button", { name: "Back to Projects" }));
    expect(screen.getByRole("heading", { name: "LighTex" })).toBeInTheDocument();
  });

  it("opens the single Settings surface", () => {
    render(<ProjectHub />);
    fireEvent.click(screen.getByRole("button", { name: "Open Settings" }));
    expect(useAppStore.getState().settingsOpen).toBe(true);
  });
});
