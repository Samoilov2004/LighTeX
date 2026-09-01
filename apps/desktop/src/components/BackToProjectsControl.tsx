import { ArrowLeft } from "lucide-react";

export function BackControl({ label, onBack }: { label: string; onBack(): void }) {
  const accessibleLabel = `Back to ${label}`;
  return (
    <button
      type="button"
      className="toolbar-button project-back-control"
      onClick={onBack}
      aria-label={accessibleLabel}
      title={accessibleLabel}
    >
      <ArrowLeft size={16} aria-hidden="true" />
      <span>{label}</span>
    </button>
  );
}

export function BackToProjectsControl({ onBack }: { onBack(): void }) {
  return <BackControl label="Projects" onBack={onBack} />;
}
