use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use ts_rs::TS;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, TS)]
#[ts(export)]
pub struct ProjectId(pub String);

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ProjectHandle {
    pub id: ProjectId,
    pub name: String,
    pub root_path: String,
    pub main_document: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ProjectEntry {
    pub name: String,
    pub relative_path: String,
    pub is_directory: bool,
    pub children: Vec<ProjectEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, TS)]
#[ts(export)]
pub struct ProjectVersionId(pub String);

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct VersionProjectRecord {
    pub schema_version: u8,
    pub id: String,
    pub last_known_path: String,
    pub root_identifier: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum ProjectVersionKind {
    Named,
    Recovery,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum VersionPreviewStatus {
    NotBuilt,
    Building,
    Ready,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum VersionFileKind {
    File,
    Symlink,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct VersionFileEntry {
    pub relative_path: String,
    pub kind: VersionFileKind,
    pub blob_sha256: Option<String>,
    #[ts(type = "number")]
    pub size: u64,
    pub unix_mode: Option<u32>,
    pub link_target: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ProjectVersionManifest {
    pub schema_version: u8,
    pub id: ProjectVersionId,
    pub project_record_id: String,
    pub name: String,
    pub created_at: String,
    pub kind: ProjectVersionKind,
    pub main_document: Option<String>,
    pub directories: Vec<String>,
    pub files: Vec<VersionFileEntry>,
    #[ts(type = "number")]
    pub total_size: u64,
    pub preview_status: VersionPreviewStatus,
    pub preview_error: Option<String>,
    pub preview_pdf_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ProjectVersionSummary {
    pub id: ProjectVersionId,
    pub name: String,
    pub created_at: String,
    pub kind: ProjectVersionKind,
    pub main_document: Option<String>,
    pub file_count: usize,
    #[ts(type = "number")]
    pub total_size: u64,
    pub preview_status: VersionPreviewStatus,
    pub preview_error: Option<String>,
}

impl From<&ProjectVersionManifest> for ProjectVersionSummary {
    fn from(value: &ProjectVersionManifest) -> Self {
        Self {
            id: value.id.clone(),
            name: value.name.clone(),
            created_at: value.created_at.clone(),
            kind: value.kind,
            main_document: value.main_document.clone(),
            file_count: value.files.len(),
            total_size: value.total_size,
            preview_status: value.preview_status,
            preview_error: value.preview_error.clone(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct VersionChangeSummary {
    pub added: Vec<String>,
    pub modified: Vec<String>,
    pub removed: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct VersionLineSummary {
    pub additions: usize,
    pub deletions: usize,
    pub changed_files: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum VersionDiffLineKind {
    Addition,
    Deletion,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct VersionDiffLine {
    pub kind: VersionDiffLineKind,
    pub text: String,
    pub old_line: Option<usize>,
    pub new_line: Option<usize>,
    /// One-based line in the saved document before which a deletion is rendered.
    /// `new_line_count + 1` places it after the final line.
    pub anchor_new_line: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct VersionFileDiff {
    pub relative_path: String,
    pub additions: usize,
    pub deletions: usize,
    pub binary: bool,
    pub lines: Vec<VersionDiffLine>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct VersionSnapshotReview {
    pub file_count: usize,
    #[ts(type = "number")]
    pub total_size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct VersionRestoreOutcome {
    pub recovery_version: ProjectVersionSummary,
    pub changed_paths: Vec<String>,
    pub main_document: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct VersionPreviewEvent {
    pub version_id: ProjectVersionId,
    pub status: VersionPreviewStatus,
    pub message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct DocumentRevision {
    #[ts(type = "number | null")]
    pub modification_unix_ms: Option<i64>,
    #[ts(type = "number")]
    pub file_size: u64,
    pub file_identifier: Option<String>,
    pub content_hash: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct DocumentSnapshot {
    pub relative_path: String,
    pub text: String,
    pub revision: DocumentRevision,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct OpenBuffer {
    pub relative_path: String,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(
    tag = "status",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
#[ts(export)]
pub enum SaveOutcome {
    Saved {
        revision: DocumentRevision,
    },
    Conflict {
        disk_revision: Option<DocumentRevision>,
    },
    Missing,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ProjectChangeEvent {
    pub paths: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct OutlineItem {
    pub relative_path: String,
    pub line: usize,
    pub title: String,
    pub level: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum CompletionKind {
    Command,
    Environment,
    Package,
    Label,
    Citation,
    Path,
    Class,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct CompletionItem {
    pub label: String,
    pub insert_text: String,
    pub detail: String,
    pub kind: CompletionKind,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ProjectCompletionIndex {
    pub labels: Vec<String>,
    pub citations: Vec<String>,
    pub packages: Vec<String>,
    pub classes: Vec<String>,
    pub input_paths: Vec<String>,
    pub image_paths: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct SearchQuery {
    pub text: String,
    pub case_sensitive: bool,
    pub whole_word: bool,
    pub uses_regular_expression: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct SearchResult {
    pub relative_path: String,
    pub line: usize,
    pub column: usize,
    pub preview: String,
    pub match_start: usize,
    pub match_length: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ReplacePreview {
    pub relative_path: String,
    pub replacements: usize,
    pub original_text: String,
    pub replacement_text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum LatexEngine {
    PdfLaTex,
    XeLaTex,
    LuaLaTex,
}

impl LatexEngine {
    pub fn executable(self) -> &'static str {
        match self {
            Self::PdfLaTex => "pdflatex",
            Self::XeLaTex => "xelatex",
            Self::LuaLaTex => "lualatex",
        }
    }

    pub fn latexmk_flag(self) -> &'static str {
        match self {
            Self::PdfLaTex => "-pdf",
            Self::XeLaTex => "-xelatex",
            Self::LuaLaTex => "-lualatex",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum BuildTool {
    Latexmk,
    DirectCompiler,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct BuildRequest {
    pub project_id: ProjectId,
    pub entry_file: String,
    pub engine: LatexEngine,
    pub tool: BuildTool,
    pub executable_path: String,
    pub search_directories: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum DiagnosticSeverity {
    Error,
    Warning,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct BuildDiagnostic {
    pub severity: DiagnosticSeverity,
    pub relative_path: Option<String>,
    pub line: Option<usize>,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct BuildDiagnosticGroup {
    pub primary: BuildDiagnostic,
    pub related: Vec<BuildDiagnostic>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(tag = "stage", rename_all = "camelCase")]
#[ts(export)]
pub enum BuildEvent {
    Started,
    Output { chunk: String },
    Finished { result: BuildResult },
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct BuildResult {
    pub succeeded: bool,
    pub log: String,
    pub preview_pdf_path: Option<String>,
    pub project_pdf_path: Option<String>,
    pub diagnostics: Vec<BuildDiagnosticGroup>,
    pub missing_package_file: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct SyncTeXPdfTarget {
    pub page: usize,
    pub x: Option<f64>,
    pub y_from_top: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct SyncTeXSourceTarget {
    pub relative_path: String,
    pub line: usize,
    pub column: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ToolExecutable {
    pub path: String,
    pub version: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ToolchainStatus {
    pub engines: BTreeMap<String, ToolExecutable>,
    pub latexmk: Option<ToolExecutable>,
    pub synctex: Option<ToolExecutable>,
    pub tlmgr: Option<ToolExecutable>,
}

impl ToolchainStatus {
    pub fn has_any_engine(&self) -> bool {
        !self.engines.is_empty()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum TeXProvider {
    System,
    Managed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum RuntimePlatform {
    MacOs,
    Linux,
}

impl RuntimePlatform {
    pub fn current() -> Self {
        if cfg!(target_os = "macos") {
            Self::MacOs
        } else {
            Self::Linux
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export)]
pub enum RuntimeArchitecture {
    Arm64,
    X86_64,
}

impl RuntimeArchitecture {
    pub fn current() -> Self {
        if cfg!(target_arch = "aarch64") {
            Self::Arm64
        } else {
            Self::X86_64
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum RuntimeVariant {
    Minimal,
    Standard,
    Full,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct RuntimeArchivePart {
    pub download_url: String,
    #[ts(type = "number")]
    pub compressed_size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct RuntimeAsset {
    pub variant: RuntimeVariant,
    pub platform: RuntimePlatform,
    pub architecture: RuntimeArchitecture,
    pub download_url: Option<String>,
    pub download_parts: Option<Vec<RuntimeArchivePart>>,
    #[ts(type = "number")]
    pub compressed_size: u64,
    #[ts(type = "number")]
    pub installed_size: u64,
    pub sha256: String,
    pub tools: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct RuntimeManifestV2 {
    pub schema_version: u8,
    pub runtime_version: String,
    pub tex_live_year: u16,
    pub assets: Vec<RuntimeAsset>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ManagedRuntimeRecordV2 {
    pub schema_version: u8,
    pub runtime_version: String,
    pub tex_live_year: u16,
    pub variant: RuntimeVariant,
    pub platform: RuntimePlatform,
    pub architecture: RuntimeArchitecture,
    pub root_path: String,
    pub tools: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct RuntimeEnvironment {
    pub platform: RuntimePlatform,
    pub architecture: RuntimeArchitecture,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct InstalledRuntime {
    pub record: ManagedRuntimeRecordV2,
    #[ts(type = "number")]
    pub installed_size: u64,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct StorageUsage {
    #[ts(type = "number")]
    pub runtime_downloads: u64,
    #[ts(type = "number")]
    pub runtime_staging: u64,
    #[ts(type = "number")]
    pub build_cache: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, TS)]
#[serde(
    tag = "stage",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
#[ts(export)]
pub enum RuntimeInstallEvent {
    Checking,
    Downloading {
        #[ts(type = "number")]
        received: u64,
        #[ts(type = "number")]
        total: u64,
        bytes_per_second: f64,
    },
    Verifying,
    Installing,
    Ready {
        record: ManagedRuntimeRecordV2,
    },
    Failed {
        message: String,
    },
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct TemplateReview {
    pub source_path: String,
    pub included_files: Vec<String>,
    pub excluded_files: Vec<String>,
    #[ts(type = "number")]
    pub total_size: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum BundledTemplateCategory {
    Essentials,
    Academic,
    Slides,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum TemplateCodeStyle {
    None,
    Strict,
    Colorful,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum TemplateCodeLanguage {
    Python,
    Sql,
    Cpp,
    JavaScript,
    Rust,
    Java,
    Shell,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum TemplateSectionNumbering {
    Hierarchical,
    PerChapter,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum TemplateTitlePage {
    Enabled,
    Disabled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub enum TemplateProjectStructure {
    SingleFile,
    Chapters,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct TemplateInstantiationOptions {
    pub code_style: Option<TemplateCodeStyle>,
    pub code_languages: Option<Vec<TemplateCodeLanguage>>,
    pub section_numbering: Option<TemplateSectionNumbering>,
    pub title_page: Option<TemplateTitlePage>,
    pub project_structure: Option<TemplateProjectStructure>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct BundledTemplateManifestV2 {
    pub schema_version: u8,
    pub id: String,
    pub name: String,
    pub description: String,
    pub category: BundledTemplateCategory,
    pub sort_order: u16,
    pub engine: LatexEngine,
    pub entry: String,
    pub preview: String,
    pub preview_variants: BTreeMap<String, String>,
    pub code_styles: Vec<TemplateCodeStyle>,
    pub code_languages: Vec<TemplateCodeLanguage>,
    pub default_code_style: Option<TemplateCodeStyle>,
    pub default_code_languages: Vec<TemplateCodeLanguage>,
    pub section_numberings: Vec<TemplateSectionNumbering>,
    pub default_section_numbering: Option<TemplateSectionNumbering>,
    pub title_pages: Vec<TemplateTitlePage>,
    pub default_title_page: Option<TemplateTitlePage>,
    pub project_structures: Vec<TemplateProjectStructure>,
    pub default_project_structure: Option<TemplateProjectStructure>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct PersonalTemplateManifestV2 {
    pub schema_version: u8,
    pub id: String,
    pub name: String,
    pub created_at: String,
    pub main_document: Option<String>,
    pub preview: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct AppUpdateInfo {
    pub current_version: String,
    pub latest_version: String,
    pub release_url: String,
    pub update_available: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct AppConfigV1 {
    pub schema_version: u8,
    pub recent_projects: Vec<String>,
    pub open_last_project: bool,
    pub autosave: bool,
    pub automatic_builds: bool,
    pub automatic_build_delay_seconds: u8,
    pub editor_font_size: f64,
    pub tab_width: u8,
    pub show_line_numbers: bool,
    pub word_wrap: bool,
    pub auto_close_brackets: bool,
    pub latex_engine: LatexEngine,
    pub build_tool: BuildTool,
    pub tex_provider: Option<TeXProvider>,
    pub managed_runtime_record_path: Option<String>,
    pub show_problems_on_failure: bool,
}

impl Default for AppConfigV1 {
    fn default() -> Self {
        Self {
            schema_version: 1,
            recent_projects: Vec::new(),
            open_last_project: false,
            autosave: true,
            automatic_builds: true,
            automatic_build_delay_seconds: 5,
            editor_font_size: 13.5,
            tab_width: 4,
            show_line_numbers: true,
            word_wrap: true,
            auto_close_brackets: true,
            latex_engine: LatexEngine::PdfLaTex,
            build_tool: BuildTool::Latexmk,
            tex_provider: None,
            managed_runtime_record_path: None,
            show_problems_on_failure: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ProjectSessionV1 {
    pub schema_version: u8,
    pub project_path: String,
    pub main_document: Option<String>,
    pub open_documents: Vec<String>,
    pub selected_document: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export)]
pub struct ProjectSessionV2 {
    pub schema_version: u8,
    pub project_path: String,
    pub main_document: Option<String>,
    pub open_documents: Vec<String>,
    pub selected_document: Option<String>,
    pub outline_expanded: bool,
    pub outline_height: u16,
}

impl From<ProjectSessionV1> for ProjectSessionV2 {
    fn from(session: ProjectSessionV1) -> Self {
        Self {
            schema_version: 2,
            project_path: session.project_path,
            main_document: session.main_document,
            open_documents: session.open_documents,
            selected_document: session.selected_document,
            outline_expanded: true,
            outline_height: 180,
        }
    }
}
