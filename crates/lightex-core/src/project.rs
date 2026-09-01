use std::{
    collections::{BTreeMap, HashMap, HashSet},
    fs,
    path::{Path, PathBuf},
    sync::RwLock,
};

use serde::Deserialize;
use uuid::Uuid;

use crate::{
    BundledTemplateCategory, BundledTemplateManifestV2, CoreError, CoreResult, LatexEngine,
    ProjectEntry, ProjectHandle, ProjectId, TemplateCodeLanguage, TemplateCodeStyle,
    TemplateInstantiationOptions,
    paths::{canonical_directory, safe_relative_path},
};

#[derive(Default)]
pub struct ProjectRegistry {
    projects: RwLock<HashMap<ProjectId, PathBuf>>,
}

impl ProjectRegistry {
    pub fn open(&self, path: impl AsRef<Path>) -> CoreResult<ProjectHandle> {
        let root = canonical_directory(path)?;
        let id = ProjectId(Uuid::new_v4().to_string());
        self.projects
            .write()
            .expect("project registry poisoned")
            .insert(id.clone(), root.clone());
        Ok(ProjectHandle {
            id,
            name: root
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("Project")
                .to_owned(),
            root_path: root.to_string_lossy().into_owned(),
            main_document: detect_main_document(&root),
        })
    }

    pub fn close(&self, id: &ProjectId) {
        self.projects
            .write()
            .expect("project registry poisoned")
            .remove(id);
    }

    pub fn root(&self, id: &ProjectId) -> CoreResult<PathBuf> {
        self.projects
            .read()
            .expect("project registry poisoned")
            .get(id)
            .cloned()
            .ok_or_else(|| CoreError::UnknownProject(id.0.clone()))
    }

    pub fn resolve(&self, id: &ProjectId, relative: impl AsRef<Path>) -> CoreResult<PathBuf> {
        safe_relative_path(&self.root(id)?, relative)
    }
}

pub fn scan(root: &Path) -> CoreResult<Vec<ProjectEntry>> {
    fn visit(root: &Path, directory: &Path) -> CoreResult<Vec<ProjectEntry>> {
        let mut entries = Vec::new();
        for item in fs::read_dir(directory)? {
            let item = item?;
            let path = item.path();
            let name = item.file_name().to_string_lossy().into_owned();
            if excluded_name(&name) {
                continue;
            }
            let is_directory = path.is_dir();
            if !is_directory && !is_visible_project_file(&path) {
                continue;
            }
            let relative = path
                .strip_prefix(root)
                .unwrap_or(&path)
                .to_string_lossy()
                .replace('\\', "/");
            entries.push(ProjectEntry {
                name,
                relative_path: relative,
                is_directory,
                children: if is_directory {
                    visit(root, &path)?
                } else {
                    Vec::new()
                },
            });
        }
        entries.sort_by(|a, b| {
            b.is_directory
                .cmp(&a.is_directory)
                .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
        });
        Ok(entries)
    }
    visit(root, root)
}

pub fn create_project(parent: &Path, name: &str) -> CoreResult<PathBuf> {
    let name = validated_name(name)?;
    let parent = canonical_directory(parent)?;
    let destination = parent.join(name);
    if destination.exists() {
        return Err(CoreError::DestinationExists(destination));
    }
    fs::create_dir(&destination)?;
    let source = "\\documentclass[11pt]{article}\n\\usepackage[T1]{fontenc}\n\\usepackage{amsmath,amssymb}\n\\title{Untitled Document}\n\\author{}\n\\date{}\n\n\\begin{document}\n\\maketitle\n\n\\section{Introduction}\nStart writing here.\n\n\\end{document}\n";
    fs::write(destination.join("main.tex"), source)?;
    Ok(destination)
}

pub fn create_project_from_template(
    parent: &Path,
    name: &str,
    templates_root: &Path,
    template: &str,
    options: Option<&TemplateInstantiationOptions>,
) -> CoreResult<PathBuf> {
    let template = validated_name(template)?;
    let templates_root = canonical_directory(templates_root)?;
    let (source, manifest) = bundled_template(&templates_root, template)?;
    let (code_style, code_languages) = normalize_template_options(&manifest, options)?;

    let name = validated_name(name)?;
    let parent = canonical_directory(parent)?;
    let destination = parent.join(name);
    if destination.exists() {
        return Err(CoreError::DestinationExists(destination));
    }
    let staging = parent.join(format!(".lightex-template-{}", Uuid::new_v4()));
    fs::create_dir(&staging)?;
    let operation = (|| -> CoreResult<()> {
        copy_bundled_template(&source, &staging)?;
        configure_bundled_template(&manifest, &staging, code_style, &code_languages)?;
        fs::rename(&staging, &destination)?;
        Ok(())
    })();
    if let Err(error) = operation {
        let _ = fs::remove_dir_all(&staging);
        return Err(error);
    }
    Ok(destination)
}

pub fn list_bundled_templates(templates_root: &Path) -> CoreResult<Vec<BundledTemplateManifestV2>> {
    let templates_root = canonical_directory(templates_root)?;
    let mut manifests = Vec::new();
    for entry in fs::read_dir(&templates_root)? {
        let entry = entry?;
        if !entry.file_type()?.is_dir() || !entry.path().join("template.json").is_file() {
            continue;
        }
        let id = entry.file_name().to_string_lossy().into_owned();
        let (_, manifest) = bundled_template(&templates_root, &id)?;
        manifests.push(manifest);
    }
    manifests.sort_by_key(|manifest| {
        (
            category_order(manifest.category),
            manifest.sort_order,
            manifest.name.to_lowercase(),
        )
    });
    Ok(manifests)
}

pub fn bundled_template_preview(
    templates_root: &Path,
    template: &str,
    style: Option<TemplateCodeStyle>,
) -> CoreResult<PathBuf> {
    let template = validated_name(template)?;
    let templates_root = canonical_directory(templates_root)?;
    let (source, manifest) = bundled_template(&templates_root, template)?;
    if style.is_some_and(|value| !manifest.code_styles.contains(&value)) {
        return Err(CoreError::Message(
            "This preview style is not available for the template.".into(),
        ));
    }
    let preview = style
        .and_then(|value| manifest.preview_variants.get(code_style_key(value)))
        .unwrap_or(&manifest.preview);
    let path = fs::canonicalize(source.join(preview))?;
    if !path.starts_with(&source) || !path.is_file() {
        return Err(CoreError::InvalidManifest(format!(
            "template preview is outside the template: {preview}"
        )));
    }
    Ok(path)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BundledTemplateManifestRaw {
    schema_version: u8,
    id: String,
    name: String,
    description: String,
    category: String,
    #[serde(default)]
    sort_order: Option<u16>,
    engine: String,
    entry: String,
    preview: String,
    #[serde(default)]
    preview_variants: BTreeMap<String, String>,
    #[serde(default)]
    code_styles: Vec<TemplateCodeStyle>,
    #[serde(default)]
    code_languages: Vec<TemplateCodeLanguage>,
    #[serde(default)]
    default_code_style: Option<TemplateCodeStyle>,
    #[serde(default)]
    default_code_languages: Vec<TemplateCodeLanguage>,
}

fn bundled_template(
    templates_root: &Path,
    template: &str,
) -> CoreResult<(PathBuf, BundledTemplateManifestV2)> {
    let source_candidate = templates_root.join(template);
    if !source_candidate.is_dir() {
        return Err(CoreError::Message(format!(
            "The bundled template does not exist: {template}"
        )));
    }
    let source = canonical_directory(&source_candidate)?;
    if !source.starts_with(templates_root) {
        return Err(CoreError::UnsafePath(source));
    }
    let raw: BundledTemplateManifestRaw =
        serde_json::from_slice(&fs::read(source.join("template.json"))?)?;
    if !matches!(raw.schema_version, 1 | 2) || raw.id != template {
        return Err(CoreError::InvalidManifest(format!(
            "template.json does not describe {template}"
        )));
    }
    let entry_path = fs::canonicalize(source.join(&raw.entry))?;
    if !entry_path.starts_with(&source) || !entry_path.is_file() {
        return Err(CoreError::InvalidManifest(format!(
            "template entry is outside the template: {}",
            raw.entry
        )));
    }
    let preview_path = fs::canonicalize(source.join(&raw.preview))?;
    if !preview_path.starts_with(&source) || !preview_path.is_file() {
        return Err(CoreError::InvalidManifest(format!(
            "template preview is outside the template: {}",
            raw.preview
        )));
    }
    for preview in raw.preview_variants.values() {
        let path = fs::canonicalize(source.join(preview))?;
        if !path.starts_with(&source) || !path.is_file() {
            return Err(CoreError::InvalidManifest(format!(
                "template preview is outside the template: {preview}"
            )));
        }
    }
    let category = parse_template_category(&raw.id, &raw.category)?;
    let engine = parse_template_engine(&raw.engine)?;
    let sort_order = raw
        .sort_order
        .unwrap_or_else(|| legacy_template_order(&raw.id));
    Ok((
        source,
        BundledTemplateManifestV2 {
            schema_version: 2,
            id: raw.id,
            name: raw.name,
            description: raw.description,
            category,
            sort_order,
            engine,
            entry: raw.entry,
            preview: raw.preview,
            preview_variants: raw.preview_variants,
            code_styles: raw.code_styles,
            code_languages: raw.code_languages,
            default_code_style: raw.default_code_style,
            default_code_languages: raw.default_code_languages,
        },
    ))
}

fn parse_template_category(id: &str, category: &str) -> CoreResult<BundledTemplateCategory> {
    match category {
        "essentials" => Ok(BundledTemplateCategory::Essentials),
        "academic" => Ok(BundledTemplateCategory::Academic),
        "slides" | "presentation" => Ok(BundledTemplateCategory::Slides),
        "general" => Ok(BundledTemplateCategory::Essentials),
        "education" if id == "lab-report" => Ok(BundledTemplateCategory::Academic),
        "education" => Ok(BundledTemplateCategory::Essentials),
        _ => Err(CoreError::InvalidManifest(format!(
            "unsupported template category: {category}"
        ))),
    }
}

fn parse_template_engine(engine: &str) -> CoreResult<LatexEngine> {
    match engine {
        "pdflatex" | "pdfLaTex" => Ok(LatexEngine::PdfLaTex),
        "xelatex" | "xeLaTex" => Ok(LatexEngine::XeLaTex),
        "lualatex" | "luaLaTex" => Ok(LatexEngine::LuaLaTex),
        _ => Err(CoreError::InvalidManifest(format!(
            "unsupported template engine: {engine}"
        ))),
    }
}

fn legacy_template_order(id: &str) -> u16 {
    match id {
        "blank-document" => 10,
        "homework" => 20,
        "math-notes" | "course-notes" => 30,
        "scientific-article" => 40,
        "lab-report" => 50,
        "simple-presentation" => 60,
        _ => 100,
    }
}

fn category_order(category: BundledTemplateCategory) -> u8 {
    match category {
        BundledTemplateCategory::Essentials => 0,
        BundledTemplateCategory::Academic => 1,
        BundledTemplateCategory::Slides => 2,
    }
}

fn normalize_template_options(
    manifest: &BundledTemplateManifestV2,
    options: Option<&TemplateInstantiationOptions>,
) -> CoreResult<(Option<TemplateCodeStyle>, Vec<TemplateCodeLanguage>)> {
    if manifest.code_styles.is_empty() {
        if options.is_some_and(|value| {
            value.code_style.is_some()
                || value
                    .code_languages
                    .as_ref()
                    .is_some_and(|languages| !languages.is_empty())
        }) {
            return Err(CoreError::Message(format!(
                "{} does not support code configuration.",
                manifest.name
            )));
        }
        return Ok((None, Vec::new()));
    }
    let style = options
        .and_then(|value| value.code_style)
        .or(manifest.default_code_style)
        .ok_or_else(|| {
            CoreError::InvalidManifest("configurable template has no default code style".into())
        })?;
    if !manifest.code_styles.contains(&style) {
        return Err(CoreError::Message(
            "Unsupported code style for this template.".into(),
        ));
    }
    let requested = options
        .and_then(|value| value.code_languages.clone())
        .unwrap_or_else(|| manifest.default_code_languages.clone());
    if requested
        .iter()
        .any(|language| !manifest.code_languages.contains(language))
    {
        return Err(CoreError::Message(
            "Unsupported code language for this template.".into(),
        ));
    }
    if style == TemplateCodeStyle::None {
        return Ok((Some(style), Vec::new()));
    }
    let requested: HashSet<_> = requested.into_iter().collect();
    let languages = manifest
        .code_languages
        .iter()
        .copied()
        .filter(|language| requested.contains(language))
        .collect();
    Ok((Some(style), languages))
}

fn configure_bundled_template(
    manifest: &BundledTemplateManifestV2,
    destination: &Path,
    code_style: Option<TemplateCodeStyle>,
    code_languages: &[TemplateCodeLanguage],
) -> CoreResult<()> {
    if manifest.id != "course-notes" {
        return Ok(());
    }
    let style = code_style.unwrap_or(TemplateCodeStyle::Strict);
    render_marker(
        &destination.join("notes.sty"),
        "% LighTex:CodeSupport",
        &code_support(style, code_languages),
    )?;
    render_marker(
        &destination.join("main.tex"),
        "% LighTex:CodeExample",
        &code_example(code_languages.first().copied()),
    )
}

fn render_marker(path: &Path, marker: &str, replacement: &str) -> CoreResult<()> {
    let source = fs::read_to_string(path)?;
    if !source.contains(marker) {
        return Err(CoreError::InvalidManifest(format!(
            "template marker is missing in {}: {marker}",
            path.display()
        )));
    }
    fs::write(path, source.replace(marker, replacement))?;
    Ok(())
}

fn code_style_key(style: TemplateCodeStyle) -> &'static str {
    match style {
        TemplateCodeStyle::None => "none",
        TemplateCodeStyle::Strict => "strict",
        TemplateCodeStyle::Colorful => "colorful",
    }
}

fn code_support(style: TemplateCodeStyle, languages: &[TemplateCodeLanguage]) -> String {
    if style == TemplateCodeStyle::None {
        return String::new();
    }
    let style_definition = match style {
        TemplateCodeStyle::None => unreachable!(),
        TemplateCodeStyle::Strict => STRICT_CODE_STYLE,
        TemplateCodeStyle::Colorful => COLORFUL_CODE_STYLE,
    };
    let mut output = format!("\\RequirePackage{{listings}}\n{style_definition}\n");
    for language in languages {
        output.push_str(language_environment(*language));
        output.push('\n');
    }
    output
}

fn language_environment(language: TemplateCodeLanguage) -> &'static str {
    match language {
        TemplateCodeLanguage::Python => {
            "\\lstnewenvironment{pythoncode}{\\lstset{style=lightexcode,language=Python}}{}"
        }
        TemplateCodeLanguage::Sql => {
            "\\lstnewenvironment{sqlcode}{\\lstset{style=lightexcode,language=SQL}}{}"
        }
        TemplateCodeLanguage::Cpp => {
            "\\lstnewenvironment{cppcode}{\\lstset{style=lightexcode,language={[ISO]C++}}}{}"
        }
        TemplateCodeLanguage::JavaScript => JAVASCRIPT_ENVIRONMENT,
        TemplateCodeLanguage::Rust => RUST_ENVIRONMENT,
        TemplateCodeLanguage::Java => {
            "\\lstnewenvironment{javacode}{\\lstset{style=lightexcode,language=Java}}{}"
        }
        TemplateCodeLanguage::Shell => {
            "\\lstnewenvironment{shellcode}{\\lstset{style=lightexcode,language=bash}}{}"
        }
    }
}

fn code_example(language: Option<TemplateCodeLanguage>) -> String {
    let Some(language) = language else {
        return String::new();
    };
    let (environment, source) = match language {
        TemplateCodeLanguage::Python => (
            "pythoncode",
            "values = [3, 5, 8, 13]\nmean = sum(values) / len(values)\nprint(mean)",
        ),
        TemplateCodeLanguage::Sql => (
            "sqlcode",
            "SELECT student_id, AVG(score) AS average_score\nFROM scores\nGROUP BY student_id\nORDER BY average_score DESC;",
        ),
        TemplateCodeLanguage::Cpp => (
            "cppcode",
            "std::vector<int> values{3, 5, 8, 13};\ndouble mean = std::accumulate(values.begin(), values.end(), 0.0) / values.size();",
        ),
        TemplateCodeLanguage::JavaScript => (
            "jscode",
            "const values = [3, 5, 8, 13];\nconst mean = values.reduce((sum, value) => sum + value, 0) / values.length;",
        ),
        TemplateCodeLanguage::Rust => (
            "rustcode",
            "let values = [3.0, 5.0, 8.0, 13.0];\nlet mean = values.iter().sum::<f64>() / values.len() as f64;",
        ),
        TemplateCodeLanguage::Java => (
            "javacode",
            "double[] values = {3, 5, 8, 13};\ndouble mean = Arrays.stream(values).average().orElse(0.0);",
        ),
        TemplateCodeLanguage::Shell => ("shellcode", "values=\"3 5 8 13\"\nprintf '%s\\n' $values"),
    };
    format!(
        "\\section{{A computational example}}\n\\begin{{{environment}}}\n{source}\n\\end{{{environment}}}"
    )
}

const STRICT_CODE_STYLE: &str = r#"\lstdefinestyle{lightexcode}{
  basicstyle=\ttfamily\small,
  backgroundcolor=\color{white},
  frame=single,
  rulecolor=\color{NotesLine},
  framesep=6pt,
  xleftmargin=2pt,
  xrightmargin=2pt,
  breaklines=true,
  showstringspaces=false,
  columns=fullflexible,
  keepspaces=true,
  keywordstyle=\bfseries\color{NotesInk},
  commentstyle=\itshape\color{NotesMuted},
  stringstyle=\color{NotesInk}
}"#;

const COLORFUL_CODE_STYLE: &str = r#"\lstdefinestyle{lightexcode}{
  basicstyle=\ttfamily\small,
  backgroundcolor=\color{CodeBackground},
  frame=single,
  rulecolor=\color{NotesLine},
  framesep=6pt,
  xleftmargin=2pt,
  xrightmargin=2pt,
  breaklines=true,
  showstringspaces=false,
  columns=fullflexible,
  keepspaces=true,
  keywordstyle=\bfseries\color{CodeBlue},
  commentstyle=\itshape\color{CodeGreen},
  stringstyle=\color{CodePurple}
}"#;

const JAVASCRIPT_ENVIRONMENT: &str = r#"\lstdefinelanguage{LighTexJavaScript}{
  keywords={async,await,break,case,class,const,continue,default,delete,do,else,export,extends,false,for,from,function,if,import,in,instanceof,let,new,null,of,return,static,super,switch,this,throw,true,try,typeof,undefined,var,while,yield},
  sensitive=true,
  morecomment=[l]{//},morecomment=[s]{/*}{*/},morestring=[b]',morestring=[b]"
}
\lstnewenvironment{jscode}{\lstset{style=lightexcode,language=LighTexJavaScript}}{}"#;

const RUST_ENVIRONMENT: &str = r#"\lstdefinelanguage{LighTexRust}{
  keywords={as,async,await,break,const,continue,crate,dyn,else,enum,extern,false,fn,for,if,impl,in,let,loop,match,mod,move,mut,pub,ref,return,self,Self,static,struct,super,trait,true,type,unsafe,use,where,while},
  sensitive=true,
  morecomment=[l]{//},morecomment=[s]{/*}{*/},morestring=[b]"
}
\lstnewenvironment{rustcode}{\lstset{style=lightexcode,language=LighTexRust}}{}"#;

fn copy_bundled_template(source: &Path, destination: &Path) -> CoreResult<()> {
    fn visit(root: &Path, directory: &Path, destination: &Path) -> CoreResult<()> {
        for entry in fs::read_dir(directory)? {
            let entry = entry?;
            let file_type = entry.file_type()?;
            if file_type.is_symlink() {
                continue;
            }
            let relative = entry.path().strip_prefix(root).unwrap().to_path_buf();
            if excluded_bundled_template_path(&relative) {
                continue;
            }
            let target = destination.join(&relative);
            if file_type.is_dir() {
                fs::create_dir_all(&target)?;
                visit(root, &entry.path(), destination)?;
            } else if file_type.is_file() {
                if let Some(parent) = target.parent() {
                    fs::create_dir_all(parent)?;
                }
                fs::copy(entry.path(), target)?;
            }
        }
        Ok(())
    }
    visit(source, source, destination)
}

fn excluded_bundled_template_path(relative: &Path) -> bool {
    if relative
        .components()
        .any(|component| component.as_os_str() == "build")
    {
        return true;
    }
    let name = relative.file_name().and_then(|value| value.to_str());
    if name == Some(".DS_Store") {
        return true;
    }
    relative
        .parent()
        .is_some_and(|parent| parent.as_os_str().is_empty())
        && (matches!(name, Some("template.json" | "main.pdf"))
            || name.is_some_and(|value| value.starts_with("preview") && value.ends_with(".png")))
}

pub fn create_file(root: &Path, parent: &str, name: &str) -> CoreResult<String> {
    let name = validated_name(name)?;
    let parent = safe_relative_path(root, parent)?;
    let path = parent.join(name);
    ensure_new_destination(&path)?;
    fs::write(
        &path,
        if path.extension().is_some_and(|ext| ext == "tex") {
            "% New LaTeX file\n"
        } else {
            ""
        },
    )?;
    Ok(path
        .strip_prefix(root)
        .unwrap()
        .to_string_lossy()
        .replace('\\', "/"))
}

pub fn create_folder(root: &Path, parent: &str, name: &str) -> CoreResult<String> {
    let name = validated_name(name)?;
    let parent = safe_relative_path(root, parent)?;
    let path = parent.join(name);
    ensure_new_destination(&path)?;
    fs::create_dir(&path)?;
    Ok(path
        .strip_prefix(root)
        .unwrap()
        .to_string_lossy()
        .replace('\\', "/"))
}

pub fn rename(root: &Path, relative: &str, new_name: &str) -> CoreResult<String> {
    let new_name = validated_name(new_name)?;
    let source = safe_relative_path(root, relative)?;
    let destination = source.parent().unwrap_or(root).join(new_name);
    ensure_new_destination(&destination)?;
    fs::rename(&source, &destination)?;
    Ok(destination
        .strip_prefix(root)
        .unwrap()
        .to_string_lossy()
        .replace('\\', "/"))
}

pub fn move_entry(root: &Path, relative: &str, destination_folder: &str) -> CoreResult<String> {
    let source = safe_relative_path(root, relative)?;
    let folder = safe_relative_path(root, destination_folder)?;
    if !folder.is_dir() {
        return Err(CoreError::InvalidProject(folder));
    }
    let destination = folder.join(
        source
            .file_name()
            .ok_or_else(|| CoreError::UnsafePath(source.clone()))?,
    );
    ensure_new_destination(&destination)?;
    fs::rename(&source, &destination)?;
    Ok(destination
        .strip_prefix(root)
        .unwrap()
        .to_string_lossy()
        .replace('\\', "/"))
}

pub fn duplicate(root: &Path, relative: &str) -> CoreResult<String> {
    let source = safe_relative_path(root, relative)?;
    let parent = source.parent().unwrap_or(root);
    let stem = source
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("copy");
    let extension = source.extension().and_then(|value| value.to_str());
    for number in 1..10_000 {
        let suffix = if number == 1 {
            " copy".to_owned()
        } else {
            format!(" copy {number}")
        };
        let file_name = match extension {
            Some(extension) => format!("{stem}{suffix}.{extension}"),
            None => format!("{stem}{suffix}"),
        };
        let destination = parent.join(file_name);
        if destination.exists() {
            continue;
        }
        if source.is_dir() {
            copy_directory(&source, &destination)?;
        } else {
            fs::copy(&source, &destination)?;
        }
        return Ok(destination
            .strip_prefix(root)
            .unwrap()
            .to_string_lossy()
            .replace('\\', "/"));
    }
    Err(CoreError::Message(
        "Could not choose a safe duplicate name.".into(),
    ))
}

pub fn move_to_trash(root: &Path, relative: &str) -> CoreResult<()> {
    let path = safe_relative_path(root, relative)?;
    trash::delete(&path).map_err(|error| CoreError::Message(error.to_string()))
}

pub fn copy_into(
    root: &Path,
    destination_folder: &str,
    sources: &[String],
) -> CoreResult<Vec<String>> {
    let folder = safe_relative_path(root, destination_folder)?;
    let mut skipped = Vec::new();
    for source in sources {
        let source = PathBuf::from(source);
        let Some(name) = source.file_name() else {
            continue;
        };
        let destination = folder.join(name);
        if destination.exists() {
            skipped.push(name.to_string_lossy().into_owned());
            continue;
        }
        if source.is_dir() {
            copy_directory(&source, &destination)?;
        } else {
            fs::copy(&source, &destination)?;
        }
    }
    Ok(skipped)
}

pub fn editable_files(root: &Path) -> Vec<PathBuf> {
    walkdir::WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_entry(|entry| !excluded_name(&entry.file_name().to_string_lossy()))
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file() && is_editable(&entry.path().to_path_buf()))
        .map(|entry| entry.into_path())
        .collect()
}

pub fn detect_main_document(root: &Path) -> Option<String> {
    let main = root.join("main.tex");
    if main.is_file() {
        return Some("main.tex".into());
    }
    editable_files(root)
        .into_iter()
        .filter(|path| path.extension().is_some_and(|ext| ext == "tex"))
        .find(|path| fs::read_to_string(path).is_ok_and(|text| text.contains("\\documentclass")))
        .or_else(|| {
            editable_files(root)
                .into_iter()
                .find(|path| path.extension().is_some_and(|ext| ext == "tex"))
        })
        .and_then(|path| {
            path.strip_prefix(root)
                .ok()
                .map(|value| value.to_string_lossy().replace('\\', "/"))
        })
}

pub fn locate_file_identifier(root: &Path, identifier: &str) -> Option<String> {
    editable_files(root).into_iter().find_map(|path| {
        let revision = crate::document::current_revision(&path).ok().flatten()?;
        (revision.file_identifier.as_deref() == Some(identifier))
            .then(|| {
                path.strip_prefix(root)
                    .ok()
                    .map(|value| value.to_string_lossy().replace('\\', "/"))
            })
            .flatten()
    })
}

fn copy_directory(source: &Path, destination: &Path) -> CoreResult<()> {
    fs::create_dir(destination)?;
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let target = destination.join(entry.file_name());
        if entry.path().is_dir() {
            copy_directory(&entry.path(), &target)?;
        } else {
            fs::copy(entry.path(), target)?;
        }
    }
    Ok(())
}

fn ensure_new_destination(path: &Path) -> CoreResult<()> {
    if path.exists() {
        Err(CoreError::DestinationExists(path.to_path_buf()))
    } else {
        Ok(())
    }
}

fn validated_name(name: &str) -> CoreResult<&str> {
    let trimmed = name.trim();
    if trimmed.is_empty()
        || trimmed == "."
        || trimmed == ".."
        || trimmed.contains('/')
        || trimmed.contains('\\')
    {
        Err(CoreError::Message(
            "Enter a name without path separators.".into(),
        ))
    } else {
        Ok(trimmed)
    }
}

fn excluded_name(name: &str) -> bool {
    matches!(
        name,
        ".git" | ".build" | "build" | "dist" | "node_modules" | ".cache"
    ) || name.starts_with(".lightex-")
}

fn is_editable(path: &PathBuf) -> bool {
    matches!(
        path.extension()
            .and_then(|value| value.to_str())
            .map(str::to_lowercase)
            .as_deref(),
        Some("tex" | "bib" | "sty" | "cls" | "txt" | "md" | "csv" | "json" | "yaml" | "yml")
    )
}

fn is_visible_project_file(path: &Path) -> bool {
    !matches!(
        path.extension()
            .and_then(|value| value.to_str())
            .map(str::to_lowercase)
            .as_deref(),
        Some("aux" | "log" | "out" | "toc" | "fls" | "fdb_latexmk" | "synctex")
    ) && !path
        .file_name()
        .and_then(|value| value.to_str())
        .is_some_and(|name| name.ends_with(".synctex.gz"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refuses_parent_traversal() {
        let root = tempfile::tempdir().unwrap();
        assert!(safe_relative_path(root.path(), "../secret").is_err());
    }

    #[test]
    fn creates_compilable_project_shape() {
        let parent = tempfile::tempdir().unwrap();
        let root = create_project(parent.path(), "Paper").unwrap();
        let source = fs::read_to_string(root.join("main.tex")).unwrap();
        assert!(source.contains("\\documentclass"));
        assert!(source.contains("\\maketitle"));
    }

    #[test]
    fn creates_project_from_bundled_template_without_generated_files() {
        let parent = tempfile::tempdir().unwrap();
        let templates = tempfile::tempdir().unwrap();
        let template = templates.path().join("math-notes");
        fs::create_dir_all(template.join("chapters")).unwrap();
        fs::create_dir_all(template.join("build")).unwrap();
        fs::write(
            template.join("template.json"),
            r#"{"schemaVersion":1,"id":"math-notes","name":"Notes","description":"Notes","category":"education","engine":"xelatex","entry":"main.tex","preview":"preview.png"}"#,
        )
        .unwrap();
        fs::write(template.join("main.tex"), "\\documentclass{book}").unwrap();
        fs::write(template.join("chapters/first.tex"), "\\chapter{First}").unwrap();
        fs::write(template.join("preview.png"), "preview").unwrap();
        fs::write(template.join("main.pdf"), "generated").unwrap();
        fs::write(template.join("build/main.aux"), "generated").unwrap();

        let root = create_project_from_template(
            parent.path(),
            "Notes",
            templates.path(),
            "math-notes",
            None,
        )
        .unwrap();

        assert!(root.join("main.tex").is_file());
        assert!(root.join("chapters/first.tex").is_file());
        assert!(!root.join("template.json").exists());
        assert!(!root.join("preview.png").exists());
        assert!(!root.join("main.pdf").exists());
        assert!(!root.join("build").exists());
    }

    #[test]
    fn unknown_bundled_template_does_not_create_a_project() {
        let parent = tempfile::tempdir().unwrap();
        let templates = tempfile::tempdir().unwrap();
        assert!(
            create_project_from_template(parent.path(), "Missing", templates.path(), "old", None)
                .is_err()
        );
        assert!(!parent.path().join("Missing").exists());
    }

    #[test]
    fn repository_bundled_templates_are_valid_and_copyable() {
        let parent = tempfile::tempdir().unwrap();
        let templates = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../templates");
        let ids = [
            "blank-document",
            "homework",
            "lab-report",
            "course-notes",
            "scientific-article",
            "simple-presentation",
        ];

        for id in ids {
            let root =
                create_project_from_template(parent.path(), id, &templates, id, None).unwrap();
            assert!(root.join("main.tex").is_file(), "missing main.tex for {id}");
            assert!(!root.join("template.json").exists());
            assert!(!root.join("preview.png").exists());
            assert!(!root.join("main.pdf").exists());
            assert!(!root.join("build").exists());
        }
    }

    #[test]
    fn repository_template_catalog_uses_the_expected_categories_and_order() {
        let templates = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../templates");
        let manifests = list_bundled_templates(&templates).unwrap();
        let ids: Vec<_> = manifests
            .iter()
            .map(|manifest| manifest.id.as_str())
            .collect();
        assert_eq!(
            ids,
            vec![
                "blank-document",
                "homework",
                "course-notes",
                "scientific-article",
                "lab-report",
                "simple-presentation",
            ]
        );
        assert_eq!(manifests[0].category, BundledTemplateCategory::Essentials);
        assert_eq!(manifests[3].category, BundledTemplateCategory::Academic);
        assert_eq!(manifests[5].category, BundledTemplateCategory::Slides);
        assert!(
            manifests
                .iter()
                .all(|manifest| manifest.schema_version == 2)
        );
    }

    #[test]
    fn course_notes_none_has_no_code_support_or_generated_assets() {
        let parent = tempfile::tempdir().unwrap();
        let templates = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../templates");
        let options = TemplateInstantiationOptions {
            code_style: Some(TemplateCodeStyle::None),
            code_languages: Some(vec![TemplateCodeLanguage::Python]),
        };
        let root = create_project_from_template(
            parent.path(),
            "None",
            &templates,
            "course-notes",
            Some(&options),
        )
        .unwrap();

        let files: Vec<_> = fs::read_dir(&root)
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(files.len(), 4);
        assert!(files.iter().all(|name| matches!(
            name.as_str(),
            "main.tex" | "notes.sty" | "latexmkrc" | "Makefile"
        )));
        let style = fs::read_to_string(root.join("notes.sty")).unwrap();
        let main = fs::read_to_string(root.join("main.tex")).unwrap();
        assert!(!style.contains("lstnewenvironment"));
        assert!(!main.contains("A computational example"));
        assert!(!root.join("chapters").exists());
        assert!(!root.join("template.json").exists());
        assert!(!root.join("preview-none.png").exists());
    }

    #[test]
    fn course_notes_generates_only_the_selected_code_environment() {
        let templates = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../templates");
        let cases = [
            (TemplateCodeLanguage::Python, "pythoncode"),
            (TemplateCodeLanguage::Sql, "sqlcode"),
            (TemplateCodeLanguage::Cpp, "cppcode"),
            (TemplateCodeLanguage::JavaScript, "jscode"),
            (TemplateCodeLanguage::Rust, "rustcode"),
            (TemplateCodeLanguage::Java, "javacode"),
            (TemplateCodeLanguage::Shell, "shellcode"),
        ];
        for (index, (language, environment)) in cases.into_iter().enumerate() {
            let parent = tempfile::tempdir().unwrap();
            let options = TemplateInstantiationOptions {
                code_style: Some(TemplateCodeStyle::Colorful),
                code_languages: Some(vec![language]),
            };
            let root = create_project_from_template(
                parent.path(),
                &format!("Language{index}"),
                &templates,
                "course-notes",
                Some(&options),
            )
            .unwrap();
            let style = fs::read_to_string(root.join("notes.sty")).unwrap();
            let main = fs::read_to_string(root.join("main.tex")).unwrap();
            assert!(style.contains(&format!("{{{environment}}}")));
            assert!(main.contains(&format!("\\begin{{{environment}}}")));
            assert!(style.contains("CodeBlue"));
            for (_, other) in cases {
                if other != environment {
                    assert!(!style.contains(&format!("{{{other}}}")));
                }
            }
        }
    }

    #[test]
    fn template_options_and_preview_variants_are_allowlisted() {
        let parent = tempfile::tempdir().unwrap();
        let templates = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../templates");
        let unsupported = TemplateInstantiationOptions {
            code_style: Some(TemplateCodeStyle::Colorful),
            code_languages: Some(vec![TemplateCodeLanguage::Rust]),
        };
        assert!(
            create_project_from_template(
                parent.path(),
                "Unsafe",
                &templates,
                "homework",
                Some(&unsupported),
            )
            .is_err()
        );
        assert!(!parent.path().join("Unsafe").exists());
        assert!(
            bundled_template_preview(&templates, "homework", Some(TemplateCodeStyle::Colorful),)
                .is_err()
        );
        let preview =
            bundled_template_preview(&templates, "course-notes", Some(TemplateCodeStyle::Strict))
                .unwrap();
        assert_eq!(preview.file_name().unwrap(), "preview-strict.png");
    }
}
