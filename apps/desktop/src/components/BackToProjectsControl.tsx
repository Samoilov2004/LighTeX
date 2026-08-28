import { ArrowLeft } from "lucide-react";

export function BackToProjectsControl({ onBack }: { onBack(): void }) {
  return (
    <button
      type="button"
      className="toolbar-button project-back-control"
      onClick={onBack}
      aria-label="Back to Projects"
      title="Back to Projects"
    >
      <ArrowLeft size={16} aria-hidden="true" />
      <span>Projects</span>
    </button>
  );
}
