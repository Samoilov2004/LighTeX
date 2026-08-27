use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

use chrono::Utc;
use serde::Deserialize;
use uuid::Uuid;

use crate::{
    CoreError, CoreResult, PersonalTemplateManifestV2, TemplateReview, paths,
    project::detect_main_document,
};

const MANIFEST_NAME: &str = "template.json";
const PAYLOAD_NAME: &str = "payload";

pub fn review(source: &Path) -> CoreResult<TemplateReview> {
    let source = source
        .canonicalize()
        .map_err(|_| CoreError::InvalidProject(source.to_path_buf()))?;
    if !source.is_dir() {
        return Err(CoreError::InvalidProject(source));
    }
    let mut included_files = Vec::new();
    let mut excluded_files = Vec::new();
    let mut total_size = 0_u64;
    for entry in walkdir::WalkDir::new(&source)
        .follow_links(false)
        .into_iter()
        .filter_map(Result::ok)
    {
        if entry.path() == source || entry.file_type().is_dir() {
            continue;
        }
        let relative = entry
            .path()
            .strip_prefix(&source)
            .unwrap()
            .to_string_lossy()
            .replace('\\', "/");
        if should_exclude(&relative, entry.path()) || entry.file_type().is_symlink() {
            excluded_files.push(relative);
        } else {
            total_size =
                total_size.saturating_add(entry.metadata().map(|value| value.len()).unwrap_or(0));
            included_files.push(relative);
        }
    }
    included_files.sort();
    excluded_files.sort();
    Ok(TemplateReview {
        source_path: source.to_string_lossy().into_owned(),
        included_files,
        excluded_files,
        total_size,
    })
}

pub fn create(
    name: &str,
    review: &TemplateReview,
    preview_png: Option<&[u8]>,
) -> CoreResult<PersonalTemplateManifestV2> {
    let name = validated_name(name)?;
    let source = PathBuf::from(&review.source_path).canonicalize()?;
    let current = self::review(&source)?;
    if current.included_files != review.included_files
        || current.excluded_files != review.excluded_files
    {
        return Err(CoreError::Message(
            "The project changed after template review. Review it again before saving.".into(),
        ));
    }
    let id = Uuid::new_v4().to_string();
    let templates = templates_directory()?;
    let staging = templates.join(format!(".staging-{id}"));
    let destination = templates.join(&id);
    let operation = (|| -> CoreResult<PersonalTemplateManifestV2> {
        let payload = staging.join(PAYLOAD_NAME);
        fs::create_dir_all(&payload)?;
        for relative in &review.included_files {
            let source_file = crate::paths::safe_relative_path(&source, relative)?;
            let destination_file = payload.join(relative);
            if let Some(parent) = destination_file.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(source_file, destination_file)?;
        }
        let preview = match preview_png {
            Some(bytes) if bytes.starts_with(b"\x89PNG\r\n\x1a\n") => {
                fs::write(staging.join("preview.png"), bytes)?;
                Some("preview.png".to_owned())
            }
            _ => None,
        };
        let manifest = PersonalTemplateManifestV2 {
            schema_version: 2,
            id: id.clone(),
            name: name.to_owned(),
            created_at: Utc::now().to_rfc3339(),
            main_document: detect_main_document(&payload),
            preview,
        };
        write_json(&staging.join(MANIFEST_NAME), &manifest)?;
        fs::rename(&staging, destination)?;
        Ok(manifest)
    })();
    if operation.is_err() {
        let _ = fs::remove_dir_all(staging);
    }
    operation
}

pub fn preview_pdf_source(review: &TemplateReview) -> CoreResult<Option<PathBuf>> {
    let source = PathBuf::from(&review.source_path).canonicalize()?;
    let current = self::review(&source)?;
    if current.included_files != review.included_files
        || current.excluded_files != review.excluded_files
    {
        return Err(CoreError::Message(
            "The project changed after template review. Review it again before saving.".into(),
        ));
    }
    let Some(main) = detect_main_document(&source) else {
        return Ok(None);
    };
    let pdf = crate::paths::safe_relative_path(&source, Path::new(&main).with_extension("pdf"))?;
    Ok(pdf.is_file().then_some(pdf))
}

pub fn list() -> CoreResult<Vec<PersonalTemplateManifestV2>> {
    let root = templates_directory()?;
    let mut templates = Vec::new();
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        if !entry.path().is_dir() || entry.file_name().to_string_lossy().starts_with('.') {
            continue;
        }
        if let Ok(manifest) = read_manifest(&entry.path()) {
            templates.push(manifest);
        }
    }
    templates.sort_by(|left, right| right.created_at.cmp(&left.created_at));
    Ok(templates)
}

pub fn instantiate(id: &str, parent: &Path, name: &str) -> CoreResult<PathBuf> {
    let name = validated_name(name)?;
    let parent = parent
        .canonicalize()
        .map_err(|_| CoreError::InvalidProject(parent.to_path_buf()))?;
    if !parent.is_dir() {
        return Err(CoreError::InvalidProject(parent));
    }
    if id.contains('/') || id.contains('\\') || id == "." || id == ".." {
        return Err(CoreError::Message("Invalid template identifier.".into()));
    }
    let template_root = templates_directory()?.join(id);
    let _manifest = read_manifest(&template_root)?;
    let payload = template_root.join(PAYLOAD_NAME);
    let destination = parent.join(name);
    if destination.exists() {
        return Err(CoreError::DestinationExists(destination));
    }
    copy_directory(&payload, &destination)?;
    Ok(destination)
}

pub fn remove(id: &str) -> CoreResult<()> {
    if id.contains('/') || id.contains('\\') || id == "." || id == ".." {
        return Err(CoreError::Message("Invalid template identifier.".into()));
    }
    let path = templates_directory()?.join(id);
    let _ = read_manifest(&path)?;
    trash::delete(path).map_err(|error| CoreError::Message(error.to_string()))
}

pub fn preview_path(id: &str) -> CoreResult<Option<PathBuf>> {
    let root = templates_directory()?.join(id);
    let manifest = read_manifest(&root)?;
    Ok(manifest
        .preview
        .map(|relative| root.join(relative))
        .filter(|path| path.is_file()))
}

fn templates_directory() -> CoreResult<PathBuf> {
    let path = paths::data_directory()?.join("Templates");
    fs::create_dir_all(&path)?;
    Ok(path)
}

fn read_manifest(root: &Path) -> CoreResult<PersonalTemplateManifestV2> {
    let bytes = fs::read(root.join(MANIFEST_NAME))?;
    let value: serde_json::Value = serde_json::from_slice(&bytes)?;
    match value
        .get("schemaVersion")
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(1)
    {
        2 => Ok(serde_json::from_value(value)?),
        1 => {
            #[derive(Deserialize)]
            #[serde(rename_all = "camelCase")]
            struct V1 {
                name: String,
                #[serde(default)]
                main_document: Option<String>,
                #[serde(default)]
                created_at: String,
            }
            let old: V1 = serde_json::from_value(value)?;
            Ok(PersonalTemplateManifestV2 {
                schema_version: 2,
                id: root
                    .file_name()
                    .and_then(|value| value.to_str())
                    .unwrap_or("legacy")
                    .to_owned(),
                name: old.name,
                created_at: if old.created_at.is_empty() {
                    "1970-01-01T00:00:00Z".into()
                } else {
                    old.created_at
                },
                main_document: old.main_document,
                preview: root
                    .join("preview.png")
                    .is_file()
                    .then(|| "preview.png".to_owned()),
            })
        }
        _ => Err(CoreError::Message(
            "Unsupported personal template manifest.".into(),
        )),
    }
}

fn should_exclude(relative: &str, path: &Path) -> bool {
    let lower = relative.to_ascii_lowercase();
    let components: Vec<_> = lower.split('/').collect();
    if components.iter().any(|value| {
        matches!(
            *value,
            ".git" | "build" | ".build" | "dist" | "node_modules" | ".cache" | "cache"
        )
    }) {
        return true;
    }
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if name == ".env"
        || name.starts_with(".env.")
        || name.contains("credential")
        || name == "secrets.json"
    {
        return true;
    }
    if [".synctex.gz", ".run.xml", ".fdb_latexmk"]
        .iter()
        .any(|suffix| name.ends_with(suffix))
    {
        return true;
    }
    if path
        .extension()
        .is_some_and(|value| value.to_string_lossy().eq_ignore_ascii_case("pdf"))
        && path.with_extension("tex").is_file()
    {
        return true;
    }
    if matches!(
        path.extension()
            .and_then(|value| value.to_str())
            .map(str::to_ascii_lowercase)
            .as_deref(),
        Some("key" | "pem" | "p12" | "pfx" | "mobileprovision")
    ) {
        return true;
    }
    matches!(
        path.extension()
            .and_then(|value| value.to_str())
            .map(str::to_ascii_lowercase)
            .as_deref(),
        Some(
            "aux"
                | "bbl"
                | "bcf"
                | "blg"
                | "fls"
                | "lof"
                | "log"
                | "lot"
                | "nav"
                | "out"
                | "snm"
                | "synctex"
                | "toc"
                | "vrb"
        )
    )
}

fn copy_directory(source: &Path, destination: &Path) -> CoreResult<()> {
    fs::create_dir(destination)?;
    for entry in walkdir::WalkDir::new(source)
        .follow_links(false)
        .into_iter()
        .filter_map(Result::ok)
    {
        if entry.path() == source {
            continue;
        }
        let relative = entry.path().strip_prefix(source).unwrap();
        let target = destination.join(relative);
        if entry.file_type().is_dir() {
            fs::create_dir_all(target)?;
        } else if entry.file_type().is_file() {
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(entry.path(), target)?;
        }
    }
    Ok(())
}

fn write_json(path: &Path, value: &impl serde::Serialize) -> CoreResult<()> {
    let parent = path
        .parent()
        .ok_or_else(|| CoreError::UnsafePath(path.to_path_buf()))?;
    fs::create_dir_all(parent)?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(&serde_json::to_vec_pretty(value)?)?;
    temporary.write_all(b"\n")?;
    temporary.as_file().sync_all()?;
    temporary
        .persist(path)
        .map_err(|error| CoreError::Io(error.error))?;
    Ok(())
}

fn validated_name(name: &str) -> CoreResult<&str> {
    let name = name.trim();
    if name.is_empty() || name.contains('/') || name.contains('\\') || name == "." || name == ".." {
        Err(CoreError::Message(
            "Enter a template name without path separators.".into(),
        ))
    } else {
        Ok(name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn review_excludes_credentials_and_generated_files() {
        let root = tempfile::tempdir().unwrap();
        fs::write(root.path().join("main.tex"), "\\documentclass{article}").unwrap();
        fs::write(root.path().join(".env"), "SECRET=1").unwrap();
        fs::write(root.path().join("private.pem"), "secret").unwrap();
        fs::write(root.path().join("main.aux"), "generated").unwrap();
        let review = review(root.path()).unwrap();
        assert_eq!(review.included_files, vec!["main.tex"]);
        assert_eq!(review.excluded_files.len(), 3);
    }
}
