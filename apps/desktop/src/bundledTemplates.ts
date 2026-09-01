import type { BundledTemplateManifestV2, TemplateCodeStyle } from "./types";

import blankDocumentManifest from "../../../templates/blank-document/template.json";
import blankDocumentPreview from "../../../templates/blank-document/preview.png";
import homeworkManifest from "../../../templates/homework/template.json";
import homeworkPreview from "../../../templates/homework/preview.png";
import courseNotesManifest from "../../../templates/course-notes/template.json";
import courseNotesNonePreview from "../../../templates/course-notes/preview-none.png";
import courseNotesStrictPreview from "../../../templates/course-notes/preview-strict.png";
import courseNotesColorfulPreview from "../../../templates/course-notes/preview-colorful.png";
import scientificArticleManifest from "../../../templates/scientific-article/template.json";
import scientificArticlePreview from "../../../templates/scientific-article/preview.png";
import labReportManifest from "../../../templates/lab-report/template.json";
import labReportPreview from "../../../templates/lab-report/preview.png";
import simplePresentationManifest from "../../../templates/simple-presentation/template.json";
import simplePresentationPreview from "../../../templates/simple-presentation/preview.png";

const rawManifests = [
  blankDocumentManifest,
  homeworkManifest,
  courseNotesManifest,
  scientificArticleManifest,
  labReportManifest,
  simplePresentationManifest,
];

const manifests = rawManifests.map((manifest) => {
  const record = manifest as Record<string, unknown>;
  return {
    ...record,
    previewVariants: record.previewVariants ?? {},
    codeStyles: record.codeStyles ?? [],
    codeLanguages: record.codeLanguages ?? [],
    defaultCodeStyle: record.defaultCodeStyle ?? null,
    defaultCodeLanguages: record.defaultCodeLanguages ?? [],
  } as unknown as BundledTemplateManifestV2;
});

const previews: Record<string, Partial<Record<TemplateCodeStyle | "default", string>>> = {
  "blank-document": { default: blankDocumentPreview },
  homework: { default: homeworkPreview },
  "course-notes": {
    default: courseNotesStrictPreview,
    none: courseNotesNonePreview,
    strict: courseNotesStrictPreview,
    colorful: courseNotesColorfulPreview,
  },
  "scientific-article": { default: scientificArticlePreview },
  "lab-report": { default: labReportPreview },
  "simple-presentation": { default: simplePresentationPreview },
};

const categoryOrder = { essentials: 0, academic: 1, slides: 2 } as const;

export const fallbackBundledTemplates = [...manifests].sort((left, right) =>
  categoryOrder[left.category] - categoryOrder[right.category]
  || left.sortOrder - right.sortOrder
  || left.name.localeCompare(right.name)
);

export function fallbackBundledTemplatePreview(id: string, style?: TemplateCodeStyle | null) {
  const preview = previews[id];
  return (style && preview?.[style]) || preview?.default || null;
}
