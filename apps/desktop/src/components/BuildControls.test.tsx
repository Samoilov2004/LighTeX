import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { BuildControls } from "./BuildControls";

function setup(automaticBuilds = true) {
  const onAutomaticBuildsChange = vi.fn();
  const onDelayChange = vi.fn();
  const result = render(
    <BuildControls
      automaticBuilds={automaticBuilds}
      delaySeconds={5}
      buildState="idle"
      onAutomaticBuildsChange={onAutomaticBuildsChange}
      onDelayChange={onDelayChange}
      onBuild={() => {}}
      onCancel={() => {}}
    />,
  );
  return { ...result, onAutomaticBuildsChange, onDelayChange };
}

describe("BuildControls", () => {
  it("moves Auto Compile into a compact build-mode menu", () => {
    const { onAutomaticBuildsChange } = setup();
    expect(screen.queryByRole("checkbox")).not.toBeInTheDocument();
    const buildControls = screen.getByRole("group", { name: "Build controls" });
    expect(Array.from(buildControls.querySelectorAll("button")).map((button) => button.getAttribute("aria-label") ?? button.textContent)).toEqual([
      "Recompile",
      "Build mode",
    ]);
    fireEvent.click(screen.getByRole("button", { name: "Build mode" }));
    expect(screen.getByRole("menuitemradio", { name: "Auto Compile" })).toHaveAttribute("aria-checked", "true");
    fireEvent.click(screen.getByRole("menuitemradio", { name: "Manual" }));
    expect(onAutomaticBuildsChange).toHaveBeenCalledWith(false);
    expect(screen.queryByRole("menu", { name: "Build mode" })).not.toBeInTheDocument();
  });

  it("changes the Auto Compile delay from the nested menu", () => {
    const { onDelayChange } = setup();
    fireEvent.click(screen.getByRole("button", { name: "Build mode" }));
    fireEvent.click(screen.getByRole("menuitem", { name: /Delay/ }));
    fireEvent.click(screen.getByRole("menuitemradio", { name: "10 seconds" }));
    expect(onDelayChange).toHaveBeenCalledWith(10);
  });

  it("dismisses the menu with Escape and an outside click", () => {
    const first = setup();
    fireEvent.click(screen.getByRole("button", { name: "Build mode" }));
    fireEvent.keyDown(screen.getByRole("menu", { name: "Build mode" }), { key: "Escape" });
    expect(screen.queryByRole("menu", { name: "Build mode" })).not.toBeInTheDocument();
    first.unmount();

    setup();
    fireEvent.click(screen.getByRole("button", { name: "Build mode" }));
    fireEvent.pointerDown(document.body);
    expect(screen.queryByRole("menu", { name: "Build mode" })).not.toBeInTheDocument();
  });
});
