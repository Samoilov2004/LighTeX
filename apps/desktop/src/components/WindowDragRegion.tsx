interface WindowDragRegionProps {
  className?: string;
}

export function WindowDragRegion({ className = "" }: WindowDragRegionProps) {
  return (
    <div
      className={`window-drag-region ${className}`.trim()}
      data-tauri-drag-region
      aria-hidden="true"
    />
  );
}
