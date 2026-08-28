import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { InsertShelf } from "./InsertShelf";

describe("InsertShelf", () => {
  it("filters symbols by human name and LaTeX command", async () => {
    render(<InsertShelf onClose={vi.fn()} />);
    fireEvent.change(screen.getByPlaceholderText("Search name or command"), { target: { value: "subset" } });
    expect(await screen.findByRole("button", { name: "subset or equal · \\subseteq" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /alpha ·/i })).not.toBeInTheDocument();
  });

  it("inserts the table dimensions selected from the grid", () => {
    let inserted = "";
    window.addEventListener("lightex:insert", (event) => { inserted = (event as CustomEvent<{ text: string }>).detail.text; }, { once: true });
    render(<InsertShelf onClose={vi.fn()} />);
    fireEvent.click(screen.getByRole("tab", { name: "Tables" }));
    fireEvent.click(screen.getByRole("gridcell", { name: "2 rows by 4 columns" }));
    expect(inserted).toContain("\\begin{tabular}{cccc}");
    expect(inserted).toContain("Cell 2.4");
  });
});
