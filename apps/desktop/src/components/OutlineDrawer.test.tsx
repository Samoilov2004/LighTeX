import { fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { beforeEach, describe, expect, it } from "vitest";
import { useAppStore } from "../store";
import { OutlineDrawer } from "./OutlineDrawer";

function Harness({ initialExpanded = true, initialHeight = 180 }: { initialExpanded?: boolean; initialHeight?: number }) {
  const [drawer, setDrawer] = useState({ expanded: initialExpanded, height: initialHeight });
  return <OutlineDrawer expanded={drawer.expanded} height={drawer.height} onCommit={(expanded, height) => setDrawer({ expanded, height })} />;
}

describe("OutlineDrawer", () => {
  beforeEach(() => useAppStore.setState({ outline: [] }));

  it("opens and closes from the persistent Table of Contents header", () => {
    render(<Harness initialExpanded={false} />);
    const toggle = screen.getByRole("button", { name: "Table of Contents" });
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    fireEvent.click(toggle);
    expect(toggle).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByRole("separator", { name: "Resize Table of Contents" })).toBeInTheDocument();
    fireEvent.click(toggle);
    expect(toggle).toHaveAttribute("aria-expanded", "false");
  });

  it("supports keyboard resizing and snaps closed below the minimum", () => {
    render(<Harness initialHeight={112} />);
    const separator = screen.getByRole("separator", { name: "Resize Table of Contents" });
    fireEvent.keyDown(separator, { key: "ArrowUp" });
    expect(separator).toHaveAttribute("aria-valuenow", "128");
    fireEvent.keyDown(separator, { key: "ArrowDown", shiftKey: true });
    expect(screen.getByRole("button", { name: "Table of Contents" })).toHaveAttribute("aria-expanded", "false");
  });

  it("collapses when the upper divider is dragged below the snap threshold", () => {
    render(<Harness initialHeight={180} />);
    const separator = screen.getByRole("separator", { name: "Resize Table of Contents" });
    fireEvent.pointerDown(separator, { button: 0, pointerId: 1, clientY: 100 });
    fireEvent.pointerMove(window, { pointerId: 1, clientY: 230 });
    fireEvent.pointerUp(window, { pointerId: 1, clientY: 230 });
    expect(screen.getByRole("button", { name: "Table of Contents" })).toHaveAttribute("aria-expanded", "false");
  });

  it("can be pulled upward from its collapsed header", () => {
    render(<Harness initialExpanded={false} />);
    const toggle = screen.getByRole("button", { name: "Table of Contents" });
    fireEvent.pointerDown(toggle, { button: 0, pointerId: 1, clientY: 220 });
    fireEvent.pointerMove(window, { pointerId: 1, clientY: 100 });
    fireEvent.pointerUp(window, { pointerId: 1, clientY: 100 });
    expect(toggle).toHaveAttribute("aria-expanded", "true");
  });
});
