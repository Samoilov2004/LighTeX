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

  it("offers useful categorized math snippets instead of empty equation wrappers", () => {
    render(<InsertShelf onClose={vi.fn()} />);
    fireEvent.click(screen.getByRole("tab", { name: "Math" }));
    expect(screen.getByRole("button", { name: "Insert Definite Integral" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Insert Finite Sum" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Insert 2 × 2 Matrix" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Insert Display equation" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Calculus" }));
    expect(screen.getByRole("button", { name: "Insert Partial Derivative" })).toBeInTheDocument();
  });

  it("renders math cards as structured formulas instead of unicode approximations", () => {
    render(<InsertShelf onClose={vi.fn()} />);
    fireEvent.click(screen.getByRole("tab", { name: "Math" }));
    expect(screen.getByRole("button", { name: "Insert Fraction" }).querySelector("mfrac")).not.toBeNull();
    expect(screen.getByRole("button", { name: "Insert 2 × 2 Matrix" }).querySelector("mtable")).not.toBeNull();
  });

  it("inserts styled text blocks with their package requirement", () => {
    let inserted = "";
    window.addEventListener("lightex:insert", (event) => { inserted = (event as CustomEvent<{ text: string }>).detail.text; }, { once: true });
    render(<InsertShelf onClose={vi.fn()} />);
    fireEvent.click(screen.getByRole("tab", { name: "Blocks" }));
    fireEvent.click(screen.getByRole("button", { name: "Insert Note" }));
    expect(inserted).toContain("\\usepackage[most]{tcolorbox}");
    expect(inserted).toContain("title=Note");
  });

  it("offers bulleted, numbered, and descriptive lists", () => {
    let inserted = "";
    window.addEventListener("lightex:insert", (event) => { inserted = (event as CustomEvent<{ text: string }>).detail.text; }, { once: true });
    render(<InsertShelf onClose={vi.fn()} />);
    fireEvent.click(screen.getByRole("tab", { name: "Blocks" }));
    fireEvent.click(screen.getByRole("button", { name: "Lists" }));
    expect(screen.getByRole("button", { name: "Insert Bulleted List" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Insert Numbered List" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Insert Description List" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Insert Numbered List" }));
    expect(inserted).toContain("\\begin{enumerate}");
  });

  it("inserts a code block that works without an extra package", () => {
    let inserted = "";
    window.addEventListener("lightex:insert", (event) => { inserted = (event as CustomEvent<{ text: string }>).detail.text; }, { once: true });
    render(<InsertShelf onClose={vi.fn()} />);
    fireEvent.click(screen.getByRole("tab", { name: "Blocks" }));
    fireEvent.click(screen.getByRole("button", { name: "Code" }));
    fireEvent.click(screen.getByRole("button", { name: "Insert Code Block" }));
    expect(inserted).toContain("\\begin{verbatim}");
    expect(screen.getByRole("button", { name: "Insert Highlighted Code" })).toHaveTextContent("listings");
  });

  it("inserts the chosen table size directly from the grid", () => {
    let inserted = "";
    window.addEventListener("lightex:insert", (event) => { inserted = (event as CustomEvent<{ text: string }>).detail.text; }, { once: true });
    render(<InsertShelf onClose={vi.fn()} />);
    fireEvent.click(screen.getByRole("tab", { name: "Tables" }));
    fireEvent.change(screen.getByLabelText("Align"), { target: { value: "left" } });
    fireEvent.click(screen.getByLabelText("Grid lines"));
    fireEvent.pointerEnter(screen.getByRole("gridcell", { name: "2 rows by 4 columns" }));
    expect(screen.getByText("2 × 4")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("gridcell", { name: "2 rows by 4 columns" }));
    expect(inserted).toContain("\\begin{tabular}{|l|l|l|l|}");
    expect(inserted).toContain("\\textbf{Header 4}");
    expect(inserted).toContain("Cell 2.4");
  });

  it("moves through table sizes with arrow keys and inserts with Enter", () => {
    let inserted = "";
    window.addEventListener("lightex:insert", (event) => { inserted = (event as CustomEvent<{ text: string }>).detail.text; }, { once: true });
    render(<InsertShelf onClose={vi.fn()} />);
    fireEvent.click(screen.getByRole("tab", { name: "Tables" }));
    const initialCell = screen.getByRole("gridcell", { name: "3 rows by 3 columns" });
    initialCell.focus();
    fireEvent.keyDown(initialCell, { key: "ArrowRight" });
    const nextCell = screen.getByRole("gridcell", { name: "3 rows by 4 columns" });
    expect(nextCell).toHaveFocus();
    fireEvent.keyDown(nextCell, { key: "Enter" });
    expect(inserted).toContain("\\begin{tabular}{cccc}");
    expect(inserted).toContain("Cell 3.4");
  });
});
