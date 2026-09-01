import { fireEvent, render, screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";
import { ProjectHub } from "./ProjectHub";
import { defaultConfig } from "../types";
import { useAppStore } from "../store";

describe("ProjectHub", () => {
  beforeEach(() => useAppStore.setState({ config: defaultConfig, phase: "hub", settingsOpen: false }));

  it("opens one template builder instead of a separate gallery", () => {
    render(<ProjectHub />);
    expect(screen.queryByRole("heading", { name: "Yours" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "New from Template" }));
    expect(screen.getByText("New from Template")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Templates" })).not.toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Yours" })).not.toBeInTheDocument();
    expect(screen.queryByPlaceholderText(/search templates/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/document language/i)).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Save as Template/i })).toBeEnabled();
    const rail = screen.getByRole("region", { name: "Templates" });
    expect(within(rail).getByRole("button", { name: /Blank Document/i })).toBeInTheDocument();
    expect(within(rail).getByRole("button", { name: /Homework Assignment/i })).toBeInTheDocument();
    expect(within(rail).getByRole("button", { name: /Laboratory Report/i })).toBeInTheDocument();
    expect(within(rail).getByRole("button", { name: /Course Notes/i })).toHaveAttribute("aria-pressed", "true");
    expect(screen.queryByText(/Mathematical Notes/i)).not.toBeInTheDocument();
    expect(within(rail).getByRole("button", { name: /Scientific Article/i })).toBeInTheDocument();
    expect(within(rail).getByRole("button", { name: /Simple Presentation/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Readable" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("button", { name: "Full Page" })).toHaveAttribute("aria-pressed", "false");
    const back = screen.getByRole("button", { name: "Back" });
    fireEvent.click(back);
    expect(screen.getByRole("heading", { name: "LighTex" })).toBeInTheDocument();
  });

  it("opens Course Notes details and keeps its configurable draft while browsing templates", () => {
    render(<ProjectHub />);
    fireEvent.click(screen.getByRole("button", { name: "New from Template" }));

    expect(screen.getByText("New from Template")).toBeInTheDocument();
    expect(screen.queryByText(/document language/i)).not.toBeInTheDocument();
    expect(screen.getByDisplayValue("Course Notes")).toBeInTheDocument();
    expect(screen.getByText("Desktop")).toBeInTheDocument();

    const strict = screen.getByRole("radio", { name: "Strict" });
    const colorful = screen.getByRole("radio", { name: "Colorful" });
    const python = screen.getByRole("checkbox", { name: "Python" });
    const sql = screen.getByRole("checkbox", { name: "SQL" });
    expect(strict).toBeChecked();
    expect(python).toBeChecked();
    expect(sql).toBeChecked();

    fireEvent.click(colorful);
    fireEvent.click(sql);
    expect(screen.getAllByAltText("Course Notes first-page preview")[0]).toHaveAttribute("src", expect.stringContaining("preview-colorful.png"));

    const templates = screen.getByRole("region", { name: "Templates" });
    fireEvent.click(within(templates).getByRole("button", { name: /Homework Assignment/i }));
    expect(screen.getByDisplayValue("Homework Assignment")).toBeInTheDocument();
    fireEvent.click(within(screen.getByRole("region", { name: "Templates" })).getByRole("button", { name: /Course Notes/i }));
    expect(screen.getByRole("radio", { name: "Colorful" })).toBeChecked();
    expect(screen.getByRole("checkbox", { name: "SQL" })).not.toBeChecked();

    fireEvent.click(screen.getByRole("radio", { name: "None" }));
    expect(screen.getByRole("checkbox", { name: "Python" })).toBeDisabled();
    expect(screen.getByRole("checkbox", { name: "SQL" })).toBeDisabled();
    expect(screen.getAllByAltText("Course Notes first-page preview")[0]).toHaveAttribute("src", expect.stringContaining("preview-none.png"));

    fireEvent.click(screen.getByRole("button", { name: "Full Page" }));
    expect(screen.getByRole("button", { name: "Full Page" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("button", { name: "Readable" })).toHaveAttribute("aria-pressed", "false");
  });

  it("opens the single Settings surface", () => {
    render(<ProjectHub />);
    fireEvent.click(screen.getByRole("button", { name: "Open Settings" }));
    expect(useAppStore.getState().settingsOpen).toBe(true);
  });
});
