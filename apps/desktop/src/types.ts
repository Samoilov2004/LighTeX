// Cross-process models are generated from Rust by ts-rs. Keep frontend-only state below.
export type { AppConfigV1 } from "../../../crates/lightex-core/bindings/AppConfigV1";
export type { AppUpdateInfo } from "../../../crates/lightex-core/bindings/AppUpdateInfo";
export type { BuildDiagnostic } from "../../../crates/lightex-core/bindings/BuildDiagnostic";
export type { BuildDiagnosticGroup } from "../../../crates/lightex-core/bindings/BuildDiagnosticGroup";
export type { BuildRequest } from "../../../crates/lightex-core/bindings/BuildRequest";
export type { BuildResult } from "../../../crates/lightex-core/bindings/BuildResult";
export type { BuildTool } from "../../../crates/lightex-core/bindings/BuildTool";
export type { DocumentRevision } from "../../../crates/lightex-core/bindings/DocumentRevision";
export type { DocumentSnapshot } from "../../../crates/lightex-core/bindings/DocumentSnapshot";
export type { InstalledRuntime } from "../../../crates/lightex-core/bindings/InstalledRuntime";
export type { LatexEngine } from "../../../crates/lightex-core/bindings/LatexEngine";
export type { ManagedRuntimeRecordV2 } from "../../../crates/lightex-core/bindings/ManagedRuntimeRecordV2";
export type { OutlineItem } from "../../../crates/lightex-core/bindings/OutlineItem";
export type { PersonalTemplateManifestV2 } from "../../../crates/lightex-core/bindings/PersonalTemplateManifestV2";
export type { ProjectCompletionIndex } from "../../../crates/lightex-core/bindings/ProjectCompletionIndex";
export type { ProjectEntry } from "../../../crates/lightex-core/bindings/ProjectEntry";
export type { ProjectHandle } from "../../../crates/lightex-core/bindings/ProjectHandle";
export type { ProjectId } from "../../../crates/lightex-core/bindings/ProjectId";
export type { ProjectSessionV2 } from "../../../crates/lightex-core/bindings/ProjectSessionV2";
export type { ProjectVersionId } from "../../../crates/lightex-core/bindings/ProjectVersionId";
export type { ProjectVersionKind } from "../../../crates/lightex-core/bindings/ProjectVersionKind";
export type { ProjectVersionManifest } from "../../../crates/lightex-core/bindings/ProjectVersionManifest";
export type { ProjectVersionSummary } from "../../../crates/lightex-core/bindings/ProjectVersionSummary";
export type { ReplacePreview } from "../../../crates/lightex-core/bindings/ReplacePreview";
export type { RuntimeArchitecture } from "../../../crates/lightex-core/bindings/RuntimeArchitecture";
export type { RuntimeAsset } from "../../../crates/lightex-core/bindings/RuntimeAsset";
export type { RuntimeEnvironment } from "../../../crates/lightex-core/bindings/RuntimeEnvironment";
export type { RuntimeInstallEvent } from "../../../crates/lightex-core/bindings/RuntimeInstallEvent";
export type { RuntimeManifestV2 } from "../../../crates/lightex-core/bindings/RuntimeManifestV2";
export type { RuntimePlatform } from "../../../crates/lightex-core/bindings/RuntimePlatform";
export type { RuntimeVariant } from "../../../crates/lightex-core/bindings/RuntimeVariant";
export type { SaveOutcome } from "../../../crates/lightex-core/bindings/SaveOutcome";
export type { SearchQuery } from "../../../crates/lightex-core/bindings/SearchQuery";
export type { SearchResult } from "../../../crates/lightex-core/bindings/SearchResult";
export type { StorageUsage } from "../../../crates/lightex-core/bindings/StorageUsage";
export type { SyncTeXPdfTarget } from "../../../crates/lightex-core/bindings/SyncTeXPdfTarget";
export type { SyncTeXSourceTarget } from "../../../crates/lightex-core/bindings/SyncTeXSourceTarget";
export type { TeXProvider } from "../../../crates/lightex-core/bindings/TeXProvider";
export type { TemplateReview } from "../../../crates/lightex-core/bindings/TemplateReview";
export type { ToolExecutable } from "../../../crates/lightex-core/bindings/ToolExecutable";
export type { ToolchainStatus } from "../../../crates/lightex-core/bindings/ToolchainStatus";
export type { VersionChangeSummary } from "../../../crates/lightex-core/bindings/VersionChangeSummary";
export type { VersionDiffLine } from "../../../crates/lightex-core/bindings/VersionDiffLine";
export type { VersionDiffLineKind } from "../../../crates/lightex-core/bindings/VersionDiffLineKind";
export type { VersionFileDiff } from "../../../crates/lightex-core/bindings/VersionFileDiff";
export type { VersionFileEntry } from "../../../crates/lightex-core/bindings/VersionFileEntry";
export type { VersionFileKind } from "../../../crates/lightex-core/bindings/VersionFileKind";
export type { VersionLineSummary } from "../../../crates/lightex-core/bindings/VersionLineSummary";
export type { VersionPreviewEvent } from "../../../crates/lightex-core/bindings/VersionPreviewEvent";
export type { VersionPreviewStatus } from "../../../crates/lightex-core/bindings/VersionPreviewStatus";
export type { VersionProjectRecord } from "../../../crates/lightex-core/bindings/VersionProjectRecord";
export type { VersionRestoreOutcome } from "../../../crates/lightex-core/bindings/VersionRestoreOutcome";
export type { VersionSnapshotReview } from "../../../crates/lightex-core/bindings/VersionSnapshotReview";

import type { AppConfigV1 } from "../../../crates/lightex-core/bindings/AppConfigV1";
import type { DocumentSnapshot } from "../../../crates/lightex-core/bindings/DocumentSnapshot";

export interface EditorDocument extends DocumentSnapshot {
  dirty: boolean;
  externalChange: "none" | "modified" | "deleted";
}

export const defaultConfig: AppConfigV1 = {
  schemaVersion: 1,
  recentProjects: [],
  openLastProject: false,
  autosave: true,
  automaticBuilds: true,
  automaticBuildDelaySeconds: 5,
  editorFontSize: 13.5,
  tabWidth: 4,
  showLineNumbers: true,
  wordWrap: true,
  autoCloseBrackets: true,
  latexEngine: "pdfLaTex",
  buildTool: "latexmk",
  texProvider: null,
  managedRuntimeRecordPath: null,
  showProblemsOnFailure: true,
};
