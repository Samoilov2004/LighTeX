import { useEffect, useRef, useState } from "react";
import { Check, ChevronDown, ChevronRight, Play, Square } from "lucide-react";
import type { BuildState } from "../store";

interface BuildControlsProps {
  automaticBuilds: boolean;
  delaySeconds: number;
  buildState: BuildState;
  disabled?: boolean;
  onAutomaticBuildsChange(enabled: boolean): void;
  onDelayChange(seconds: number): void;
  onBuild(): void;
  onCancel(): void;
}

const delayOptions = [2, 5, 10] as const;

export function BuildControls({
  automaticBuilds,
  delaySeconds,
  buildState,
  disabled = false,
  onAutomaticBuildsChange,
  onDelayChange,
  onBuild,
  onCancel,
}: BuildControlsProps) {
  const [open, setOpen] = useState(false);
  const [delayOpen, setDelayOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const disclosure = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const delayButton = useRef<HTMLButtonElement>(null);
  const selectedDelay = useRef<HTMLButtonElement>(null);
  const openedWithKeyboard = useRef(false);

  const close = (restoreFocus = false) => {
    setOpen(false);
    setDelayOpen(false);
    if (restoreFocus) window.requestAnimationFrame(() => disclosure.current?.focus());
  };

  useEffect(() => {
    if (!open) return;
    const dismiss = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) close();
    };
    const dismissForWindow = () => close();
    document.addEventListener("pointerdown", dismiss);
    window.addEventListener("blur", dismissForWindow);
    return () => {
      document.removeEventListener("pointerdown", dismiss);
      window.removeEventListener("blur", dismissForWindow);
    };
  }, [open]);

  useEffect(() => {
    if (!open || !openedWithKeyboard.current) return;
    openedWithKeyboard.current = false;
    window.requestAnimationFrame(() => {
      const selected = menu.current?.querySelector<HTMLButtonElement>("[role='menuitemradio'][aria-checked='true']");
      selected?.focus();
    });
  }, [open]);

  useEffect(() => {
    if (delayOpen) window.requestAnimationFrame(() => selectedDelay.current?.focus());
  }, [delayOpen]);

  const moveFocus = (container: HTMLElement | null, direction: 1 | -1) => {
    if (!container) return;
    const items = Array.from(container.querySelectorAll<HTMLButtonElement>(":scope > button:not(:disabled)"));
    const index = items.indexOf(document.activeElement as HTMLButtonElement);
    items[(index + direction + items.length) % items.length]?.focus();
  };

  const mainMenuKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (event.key === "Escape") {
      event.preventDefault();
      close(true);
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      moveFocus(menu.current, event.key === "ArrowDown" ? 1 : -1);
    } else if (event.key === "ArrowRight" && document.activeElement === delayButton.current) {
      event.preventDefault();
      setDelayOpen(true);
    }
  };

  const delayMenuKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (event.key === "Escape" || event.key === "ArrowLeft") {
      event.preventDefault();
      event.stopPropagation();
      setDelayOpen(false);
      window.requestAnimationFrame(() => delayButton.current?.focus());
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      event.stopPropagation();
      moveFocus(event.currentTarget, event.key === "ArrowDown" ? 1 : -1);
    }
  };

  return (
    <div className="project-toolbar-group build-controls" role="group" aria-label="Build controls" ref={root}>
      <button
        className="primary-button compact build-primary-button"
        disabled={disabled}
        onClick={buildState === "building" ? onCancel : onBuild}
      >
        {buildState === "building" ? <Square size={11} fill="currentColor" aria-hidden="true" /> : <Play size={13} fill="currentColor" aria-hidden="true" />}
        {buildState === "building" ? "Cancel" : "Recompile"}
      </button>
      <div className="build-mode-control">
        <button
          ref={disclosure}
          className={`build-mode-button ${open ? "pressed" : ""}`}
          disabled={disabled}
          onClick={(event) => {
            if (open) close();
            else {
              setOpen(true);
              event.currentTarget.blur();
            }
          }}
          onKeyDown={(event) => {
            if (!open && (event.key === "ArrowDown" || event.key === "Enter" || event.key === " ")) {
              event.preventDefault();
              openedWithKeyboard.current = true;
              setOpen(true);
            } else if (open && event.key === "ArrowDown") {
              event.preventDefault();
              const selected = menu.current?.querySelector<HTMLButtonElement>("[role='menuitemradio'][aria-checked='true']");
              selected?.focus();
            }
          }}
          aria-label="Build mode"
          aria-haspopup="menu"
          aria-expanded={open}
          title="Build mode"
        >
          <ChevronDown size={14} aria-hidden="true" />
        </button>
        {open && (
          <div
            ref={menu}
            className="popover-menu build-mode-menu"
            role="menu"
            aria-label="Build mode"
            onKeyDown={mainMenuKeyDown}
            onBlur={(event) => {
              if (!root.current?.contains(event.relatedTarget as Node | null)) close();
            }}
          >
            <button role="menuitemradio" aria-checked={!automaticBuilds} onClick={(event) => { onAutomaticBuildsChange(false); close(event.detail === 0); }}>
              <Check className="menu-check" size={14} aria-hidden="true" />
              <span>Manual</span>
            </button>
            <button role="menuitemradio" aria-checked={automaticBuilds} onClick={(event) => { onAutomaticBuildsChange(true); close(event.detail === 0); }}>
              <Check className="menu-check" size={14} aria-hidden="true" />
              <span>Auto Compile</span>
            </button>
            <div className="menu-separator" role="separator" />
            <button
              ref={delayButton}
              className="build-delay-row"
              role="menuitem"
              aria-haspopup="menu"
              aria-expanded={delayOpen}
              disabled={!automaticBuilds}
              onClick={() => setDelayOpen((value) => !value)}
            >
              <span>Delay</span>
              <small>{delaySeconds} sec</small>
              <ChevronRight size={13} aria-hidden="true" />
            </button>
            {delayOpen && automaticBuilds && (
              <div className="popover-menu build-delay-menu" role="menu" aria-label="Auto Compile delay" onKeyDown={delayMenuKeyDown}>
                {delayOptions.map((seconds) => (
                  <button
                    key={seconds}
                    ref={seconds === delaySeconds ? selectedDelay : undefined}
                    role="menuitemradio"
                    aria-checked={seconds === delaySeconds}
                    onClick={(event) => { onDelayChange(seconds); close(event.detail === 0); }}
                  >
                    <Check className="menu-check" size={14} aria-hidden="true" />
                    <span>{seconds} seconds</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
