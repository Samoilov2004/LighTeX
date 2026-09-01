use std::{
    collections::{BTreeMap, BTreeSet, HashMap, HashSet},
    fs,
    io::Write,
    path::{Component, Path, PathBuf},
};

use chrono::Utc;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;
use walkdir::{DirEntry, WalkDir};

use crate::{
    CoreError, CoreResult, OpenBuffer, ProjectEntry, ProjectVersionId, ProjectVersionKind,
    ProjectVersionManifest, ProjectVersionSummary, VersionChangeSummary, VersionDiffLine,
    VersionDiffLineKind, VersionFileDiff, VersionFileEntry, VersionFileKind, VersionLineSummary,
    VersionPreviewStatus, VersionProjectRecord, VersionRestoreOutcome, VersionSnapshotReview,
    paths,
};

const SCHEMA_VERSION: u8 = 1;
const RECOVERY_LIMIT: usize = 10;

#[cfg(test)]
thread_local! {
    static TEST_VERSIONS_ROOT: std::cell::RefCell<Option<PathBuf>> = const { std::cell::RefCell::new(None) };
}

#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct VersionCatalog {
    schema_version: u8,
    projects: Vec<VersionProjectRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RestoreJournal {
    schema_version: u8,
    project_path: String,
    stage_path: String,
    moved_paths: Vec<String>,
    installed_paths: Vec<String>,
    #[serde(default)]
    created_directories: Vec<String>,
}

#[derive(Debug, Default)]
struct TreeNode {
    is_directory: bool,
    children: BTreeMap<String, TreeNode>,
}

pub fn versions_root() -> CoreResult<PathBuf> {
    #[cfg(test)]
    let root = match TEST_VERSIONS_ROOT.with(|value| value.borrow().clone()) {
        Some(root) => root,
        None => paths::data_directory()?.join("Versions"),
    };
    #[cfg(not(test))]
    let root = paths::data_directory()?.join("Versions");
    fs::create_dir_all(root.join("Projects"))?;
    Ok(root)
}

pub fn recover_pending_restore(root: &Path) -> CoreResult<()> {
    let record = resolve_project(root)?;
    recover_journal(root, &record)
}

pub fn list(root: &Path) -> CoreResult<Vec<ProjectVersionSummary>> {
    let record = resolve_project(root)?;
    let mut versions = manifests_for(&record)?;
    versions.sort_by(|left, right| right.created_at.cmp(&left.created_at));
    Ok(versions
        .iter()
        .map(|manifest| {
            let mut summary = ProjectVersionSummary::from(manifest);
            if summary.preview_status == VersionPreviewStatus::Building {
                summary.preview_status = VersionPreviewStatus::NotBuilt;
            }
            summary
        })
        .collect())
}

pub fn review(root: &Path, main_document: Option<&str>) -> CoreResult<VersionSnapshotReview> {
    let (_, files, total_size) = capture_tree(root, main_document, None)?;
    Ok(VersionSnapshotReview {
        file_count: files.len(),
        total_size,
    })
}

pub fn create(
    root: &Path,
    name: &str,
    kind: ProjectVersionKind,
    main_document: Option<String>,
) -> CoreResult<ProjectVersionSummary> {
    let name = validated_name(name)?;
    let record = resolve_project(root)?;
    let directory = project_directory(&record)?;
    let objects = directory.join("objects");
    fs::create_dir_all(&objects)?;
    let (directories, files, total_size) =
        capture_tree(root, main_document.as_deref(), Some(&objects))?;
    let manifest = ProjectVersionManifest {
        schema_version: SCHEMA_VERSION,
        id: ProjectVersionId(Uuid::new_v4().to_string()),
        project_record_id: record.id.clone(),
        name: name.to_owned(),
        created_at: Utc::now().to_rfc3339(),
        kind,
        main_document,
        directories,
        files,
        total_size,
        preview_status: VersionPreviewStatus::NotBuilt,
        preview_error: None,
        preview_pdf_path: None,
    };
    write_manifest(&record, &manifest)?;
    if kind == ProjectVersionKind::Recovery {
        prune_recovery_versions(&record)?;
    }
    Ok(ProjectVersionSummary::from(&manifest))
}

pub fn rename(root: &Path, id: &ProjectVersionId, name: &str) -> CoreResult<ProjectVersionSummary> {
    let name = validated_name(name)?;
    let record = resolve_project(root)?;
    let mut manifest = load_manifest(&record, id)?;
    manifest.name = name.to_owned();
    write_manifest(&record, &manifest)?;
    Ok(ProjectVersionSummary::from(&manifest))
}

pub fn remove(root: &Path, id: &ProjectVersionId) -> CoreResult<()> {
    let record = resolve_project(root)?;
    remove_from_record(&record, id)?;
    gc_objects(&record)
}

pub fn manifest(root: &Path, id: &ProjectVersionId) -> CoreResult<ProjectVersionManifest> {
    let record = resolve_project(root)?;
    load_manifest(&record, id)
}

pub fn tree(root: &Path, id: &ProjectVersionId) -> CoreResult<Vec<ProjectEntry>> {
    let manifest = manifest(root, id)?;
    let mut tree = TreeNode {
        is_directory: true,
        children: BTreeMap::new(),
    };
    for directory in &manifest.directories {
        insert_tree_path(&mut tree, directory, true)?;
    }
    for file in &manifest.files {
        insert_tree_path(&mut tree, &file.relative_path, false)?;
    }
    Ok(tree_entries(tree))
}

pub fn read_text(root: &Path, id: &ProjectVersionId, relative_path: &str) -> CoreResult<String> {
    let record = resolve_project(root)?;
    let manifest = load_manifest(&record, id)?;
    let relative_path = normalized_relative(relative_path)?;
    let entry = manifest
        .files
        .iter()
        .find(|entry| entry.relative_path == relative_path)
        .ok_or_else(|| {
            CoreError::Message(format!(
                "The saved version does not contain {relative_path}."
            ))
        })?;
    if entry.kind != VersionFileKind::File {
        return Err(CoreError::Message(
            "Symbolic links cannot be opened in the editor.".into(),
        ));
    }
    let bytes = read_blob(&record, entry)?;
    String::from_utf8(bytes)
        .map_err(|_| CoreError::Message(format!("{relative_path} is not a UTF-8 text file.")))
}

pub fn compare(root: &Path, id: &ProjectVersionId) -> CoreResult<VersionChangeSummary> {
    let manifest = manifest(root, id)?;
    let (_, current, _) = capture_tree(root, manifest.main_document.as_deref(), None)?;
    Ok(compare_entries(&current, &manifest.files))
}

pub fn line_summary(
    root: &Path,
    id: &ProjectVersionId,
    buffers: &[OpenBuffer],
) -> CoreResult<VersionLineSummary> {
    let record = resolve_project(root)?;
    let manifest = load_manifest(&record, id)?;
    let (_, current_files, _) = capture_tree(root, manifest.main_document.as_deref(), None)?;
    let current: HashMap<_, _> = current_files
        .iter()
        .map(|entry| (entry.relative_path.as_str(), entry))
        .collect();
    let target: HashMap<_, _> = manifest
        .files
        .iter()
        .map(|entry| (entry.relative_path.as_str(), entry))
        .collect();
    let buffers: HashMap<_, _> = buffers
        .iter()
        .map(|buffer| (buffer.relative_path.as_str(), buffer.text.as_str()))
        .collect();
    let paths: BTreeSet<&str> = current.keys().chain(target.keys()).copied().collect();
    let mut summary = VersionLineSummary {
        additions: 0,
        deletions: 0,
        changed_files: 0,
    };
    for relative_path in paths {
        let current_entry = current.get(relative_path).copied();
        let target_entry = target.get(relative_path).copied();
        let buffer = buffers.get(relative_path).copied();
        if buffer.is_none() && current_entry == target_entry {
            continue;
        }
        let old = current_text(root, relative_path, current_entry, buffer)?;
        let new = saved_text(&record, target_entry)?;
        let changed = match (old, new) {
            (Some(old), Some(new)) => {
                let diff = diff_text(relative_path, &old, &new);
                summary.additions += diff.additions;
                summary.deletions += diff.deletions;
                diff.additions > 0 || diff.deletions > 0 || current_entry != target_entry
            }
            _ => true,
        };
        if changed {
            summary.changed_files += 1;
        }
    }
    Ok(summary)
}

pub fn file_diff(
    root: &Path,
    id: &ProjectVersionId,
    relative_path: &str,
    current_buffer: Option<&str>,
) -> CoreResult<VersionFileDiff> {
    let relative_path = normalized_relative(relative_path)?;
    let record = resolve_project(root)?;
    let manifest = load_manifest(&record, id)?;
    let target = manifest
        .files
        .iter()
        .find(|entry| entry.relative_path == relative_path);
    let current_entry = capture_tree(root, manifest.main_document.as_deref(), None)?
        .1
        .into_iter()
        .find(|entry| entry.relative_path == relative_path);
    let old = current_text(root, &relative_path, current_entry.as_ref(), current_buffer)?;
    let new = saved_text(&record, target)?;
    match (old, new) {
        (Some(old), Some(new)) => Ok(diff_text(&relative_path, &old, &new)),
        _ => Ok(VersionFileDiff {
            relative_path,
            additions: 0,
            deletions: 0,
            binary: true,
            lines: Vec::new(),
        }),
    }
}

pub fn restore(
    root: &Path,
    id: &ProjectVersionId,
    current_main_document: Option<String>,
) -> CoreResult<VersionRestoreOutcome> {
    let record = resolve_project(root)?;
    recover_journal(root, &record)?;
    let target = load_manifest(&record, id)?;
    verify_manifest_blobs(&record, &target)?;
    let changes = compare(root, id)?;
    let changed_paths = changes
        .added
        .iter()
        .chain(changes.modified.iter())
        .chain(changes.removed.iter())
        .cloned()
        .collect();
    let recovery_name = format!("Before restoring “{}”", shortened_name(&target.name, 48));
    let recovery = create(
        root,
        &recovery_name,
        ProjectVersionKind::Recovery,
        current_main_document,
    )?;
    apply_manifest(root, &record, &target)?;
    Ok(VersionRestoreOutcome {
        recovery_version: recovery,
        changed_paths,
        main_document: target.main_document,
    })
}

pub fn materialize_preview(
    root: &Path,
    id: &ProjectVersionId,
) -> CoreResult<(PathBuf, ProjectVersionManifest)> {
    let record = resolve_project(root)?;
    let manifest = load_manifest(&record, id)?;
    verify_manifest_blobs(&record, &manifest)?;
    let base = preview_directory(&record, id)?;
    let project = base.join("project");
    if project.exists() {
        fs::remove_dir_all(&project)?;
    }
    fs::create_dir_all(&project)?;
    materialize(&record, &manifest, &project)?;
    Ok((project, manifest))
}

pub fn set_preview_status(
    root: &Path,
    id: &ProjectVersionId,
    status: VersionPreviewStatus,
    error: Option<String>,
    pdf_path: Option<String>,
) -> CoreResult<ProjectVersionSummary> {
    let record = resolve_project(root)?;
    let mut manifest = load_manifest(&record, id)?;
    manifest.preview_status = status;
    manifest.preview_error = error;
    manifest.preview_pdf_path = pdf_path;
    write_manifest(&record, &manifest)?;
    Ok(ProjectVersionSummary::from(&manifest))
}

pub fn preview_pdf_path(root: &Path, id: &ProjectVersionId) -> CoreResult<Option<PathBuf>> {
    let manifest = manifest(root, id)?;
    let Some(path) = manifest.preview_pdf_path else {
        return Ok(None);
    };
    let candidate = PathBuf::from(path).canonicalize()?;
    let cache = paths::cache_directory()?.canonicalize()?;
    if !candidate.starts_with(cache)
        || candidate.extension().and_then(|value| value.to_str()) != Some("pdf")
    {
        return Err(CoreError::UnsafePath(candidate));
    }
    Ok(Some(candidate))
}

pub fn preview_project_root(root: &Path, id: &ProjectVersionId) -> CoreResult<PathBuf> {
    let record = resolve_project(root)?;
    Ok(preview_directory(&record, id)?.join("project"))
}

fn resolve_project(root: &Path) -> CoreResult<VersionProjectRecord> {
    let root = root.canonicalize()?;
    let path = root.to_string_lossy().into_owned();
    let identifier = root_identifier(&root);
    let catalog_path = versions_root()?.join("catalog.json");
    let mut catalog = read_json::<VersionCatalog>(&catalog_path)?.unwrap_or(VersionCatalog {
        schema_version: SCHEMA_VERSION,
        projects: Vec::new(),
    });
    let matching = catalog
        .projects
        .iter()
        .position(|record| identifier.is_some() && record.root_identifier == identifier);
    let record = if let Some(index) = matching {
        catalog.projects[index].last_known_path = path.clone();
        catalog.projects[index].clone()
    } else {
        let record = VersionProjectRecord {
            schema_version: SCHEMA_VERSION,
            id: Uuid::new_v4().to_string(),
            last_known_path: path,
            root_identifier: identifier,
        };
        catalog.projects.push(record.clone());
        record
    };
    write_json(&catalog_path, &catalog)?;
    fs::create_dir_all(project_directory(&record)?)?;
    Ok(record)
}

fn root_identifier(root: &Path) -> Option<String> {
    let metadata = fs::metadata(root).ok()?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        Some(format!("{}:{}", metadata.dev(), metadata.ino()))
    }
    #[cfg(not(unix))]
    {
        let _ = metadata;
        None
    }
}

fn project_directory(record: &VersionProjectRecord) -> CoreResult<PathBuf> {
    let id = validated_uuid(&record.id)?;
    Ok(versions_root()?.join("Projects").join(id.to_string()))
}

fn preview_directory(record: &VersionProjectRecord, id: &ProjectVersionId) -> CoreResult<PathBuf> {
    let version = validated_uuid(&id.0)?;
    #[cfg(test)]
    let previews = versions_root()?.join("Previews");
    #[cfg(not(test))]
    let previews = paths::cache_directory()?.join("VersionPreviews");
    let directory = previews
        .join(validated_uuid(&record.id)?.to_string())
        .join(version.to_string());
    fs::create_dir_all(&directory)?;
    Ok(directory)
}

fn manifest_path(record: &VersionProjectRecord, id: &ProjectVersionId) -> CoreResult<PathBuf> {
    Ok(project_directory(record)?
        .join("manifests")
        .join(format!("{}.json", validated_uuid(&id.0)?)))
}

fn load_manifest(
    record: &VersionProjectRecord,
    id: &ProjectVersionId,
) -> CoreResult<ProjectVersionManifest> {
    read_json(&manifest_path(record, id)?)?
        .ok_or_else(|| CoreError::Message("The saved version no longer exists.".into()))
}

fn write_manifest(
    record: &VersionProjectRecord,
    manifest: &ProjectVersionManifest,
) -> CoreResult<()> {
    let path = manifest_path(record, &manifest.id)?;
    write_json(&path, manifest)
}

fn manifests_for(record: &VersionProjectRecord) -> CoreResult<Vec<ProjectVersionManifest>> {
    let directory = project_directory(record)?.join("manifests");
    if !directory.is_dir() {
        return Ok(Vec::new());
    }
    let mut manifests = Vec::new();
    for entry in fs::read_dir(directory)? {
        let path = entry?.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        if let Some(manifest) = read_json(&path)? {
            manifests.push(manifest);
        }
    }
    Ok(manifests)
}

fn capture_tree(
    root: &Path,
    main_document: Option<&str>,
    objects: Option<&Path>,
) -> CoreResult<(Vec<String>, Vec<VersionFileEntry>, u64)> {
    let main_pdf = main_document.map(|path| Path::new(path).with_extension("pdf"));
    let mut directories = Vec::new();
    let mut files = Vec::new();
    let mut total_size = 0_u64;
    for entry in WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_entry(|entry| included_walk_entry(root, entry))
    {
        let entry = entry.map_err(|error| CoreError::Message(error.to_string()))?;
        if entry.path() == root {
            continue;
        }
        let relative = entry
            .path()
            .strip_prefix(root)
            .map_err(|_| CoreError::UnsafePath(entry.path().to_path_buf()))?;
        if main_pdf.as_deref() == Some(relative) || generated_latex_file(relative) {
            continue;
        }
        let relative_path = relative.to_string_lossy().replace('\\', "/");
        if entry.file_type().is_dir() {
            directories.push(relative_path);
            continue;
        }
        if entry.file_type().is_symlink() {
            let target = fs::read_link(entry.path())?.to_string_lossy().into_owned();
            total_size = total_size.saturating_add(target.len() as u64);
            files.push(VersionFileEntry {
                relative_path,
                kind: VersionFileKind::Symlink,
                blob_sha256: None,
                size: target.len() as u64,
                unix_mode: unix_mode(entry.path()),
                link_target: Some(target),
            });
            continue;
        }
        if !entry.file_type().is_file() {
            continue;
        }
        let before = fs::metadata(entry.path())?;
        let before_modified = before.modified().ok();
        let bytes = fs::read(entry.path())?;
        let after = fs::metadata(entry.path())?;
        if before.len() != after.len() || before_modified != after.modified().ok() {
            return Err(CoreError::Message(format!(
                "{} changed while the version was being saved. Try again.",
                relative_path
            )));
        }
        let digest = hex::encode(Sha256::digest(&bytes));
        if let Some(objects) = objects {
            write_blob(objects, &digest, &bytes)?;
        }
        total_size = total_size.saturating_add(bytes.len() as u64);
        files.push(VersionFileEntry {
            relative_path,
            kind: VersionFileKind::File,
            blob_sha256: Some(digest),
            size: bytes.len() as u64,
            unix_mode: unix_mode(entry.path()),
            link_target: None,
        });
    }
    directories.sort();
    files.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    Ok((directories, files, total_size))
}

fn included_walk_entry(root: &Path, entry: &DirEntry) -> bool {
    if entry.path() == root {
        return true;
    }
    let Ok(relative) = entry.path().strip_prefix(root) else {
        return false;
    };
    !relative.components().any(|component| {
        let Component::Normal(name) = component else {
            return true;
        };
        excluded_component(&name.to_string_lossy())
    })
}

fn excluded_component(name: &str) -> bool {
    matches!(
        name,
        ".git" | ".build" | "build" | "dist" | "node_modules" | ".cache" | ".DS_Store"
    ) || name.starts_with(".lightex-")
}

fn generated_latex_file(path: &Path) -> bool {
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or_default();
    if name.ends_with(".synctex.gz") {
        return true;
    }
    matches!(
        path.extension()
            .and_then(|value| value.to_str())
            .map(str::to_ascii_lowercase)
            .as_deref(),
        Some("aux" | "log" | "out" | "toc" | "fls" | "fdb_latexmk" | "synctex")
    )
}

fn write_blob(objects: &Path, digest: &str, bytes: &[u8]) -> CoreResult<()> {
    let path = object_path(objects, digest)?;
    if path.is_file() {
        return Ok(());
    }
    let parent = path
        .parent()
        .ok_or_else(|| CoreError::UnsafePath(path.clone()))?;
    fs::create_dir_all(parent)?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(bytes)?;
    temporary.as_file().sync_all()?;
    match temporary.persist(&path) {
        Ok(_) => Ok(()),
        Err(_error) if path.is_file() => Ok(()),
        Err(error) => Err(CoreError::Io(error.error)),
    }
}

fn object_path(objects: &Path, digest: &str) -> CoreResult<PathBuf> {
    if digest.len() != 64 || !digest.bytes().all(|value| value.is_ascii_hexdigit()) {
        return Err(CoreError::InvalidManifest(
            "A version contains an invalid blob hash.".into(),
        ));
    }
    Ok(objects.join(&digest[..2]).join(&digest[2..]))
}

fn read_blob(record: &VersionProjectRecord, entry: &VersionFileEntry) -> CoreResult<Vec<u8>> {
    let digest = entry.blob_sha256.as_deref().ok_or_else(|| {
        CoreError::InvalidManifest("A regular file is missing its blob hash.".into())
    })?;
    let bytes = fs::read(object_path(
        &project_directory(record)?.join("objects"),
        digest,
    )?)?;
    if hex::encode(Sha256::digest(&bytes)) != digest {
        return Err(CoreError::Message(format!(
            "The saved copy of {} is damaged.",
            entry.relative_path
        )));
    }
    Ok(bytes)
}

fn verify_manifest_blobs(
    record: &VersionProjectRecord,
    manifest: &ProjectVersionManifest,
) -> CoreResult<()> {
    for entry in &manifest.files {
        if entry.kind == VersionFileKind::File {
            let _ = read_blob(record, entry)?;
        }
    }
    Ok(())
}

fn materialize(
    record: &VersionProjectRecord,
    manifest: &ProjectVersionManifest,
    destination: &Path,
) -> CoreResult<()> {
    for directory in &manifest.directories {
        fs::create_dir_all(destination.join(normalized_relative(directory)?))?;
    }
    for entry in &manifest.files {
        let path = destination.join(normalized_relative(&entry.relative_path)?);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        match entry.kind {
            VersionFileKind::File => {
                fs::write(&path, read_blob(record, entry)?)?;
                set_unix_mode(&path, entry.unix_mode)?;
            }
            VersionFileKind::Symlink => create_symlink(
                Path::new(entry.link_target.as_deref().ok_or_else(|| {
                    CoreError::InvalidManifest("A symbolic link is missing its target.".into())
                })?),
                &path,
            )?,
        }
    }
    Ok(())
}

fn saved_text(
    record: &VersionProjectRecord,
    entry: Option<&VersionFileEntry>,
) -> CoreResult<Option<String>> {
    let Some(entry) = entry else {
        return Ok(Some(String::new()));
    };
    if entry.kind != VersionFileKind::File {
        return Ok(None);
    }
    Ok(decode_text(read_blob(record, entry)?))
}

fn current_text(
    root: &Path,
    relative_path: &str,
    entry: Option<&VersionFileEntry>,
    buffer: Option<&str>,
) -> CoreResult<Option<String>> {
    if let Some(buffer) = buffer {
        return Ok(Some(buffer.to_owned()));
    }
    let Some(entry) = entry else {
        return Ok(Some(String::new()));
    };
    if entry.kind != VersionFileKind::File {
        return Ok(None);
    }
    let path = root.join(normalized_relative(relative_path)?);
    let metadata = fs::symlink_metadata(&path)?;
    if !metadata.file_type().is_file() {
        return Ok(None);
    }
    Ok(decode_text(fs::read(path)?))
}

fn decode_text(bytes: Vec<u8>) -> Option<String> {
    let text = String::from_utf8(bytes).ok()?;
    (!text.chars().any(|character| {
        character == '\0' || (character.is_control() && !matches!(character, '\n' | '\r' | '\t'))
    }))
    .then_some(text)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LineOperation<'a> {
    Equal(&'a str),
    Addition(&'a str),
    Deletion(&'a str),
}

fn logical_lines(text: &str) -> Vec<&str> {
    if text.is_empty() {
        return Vec::new();
    }
    let mut lines: Vec<_> = text.split('\n').collect();
    if text.ends_with('\n') {
        lines.pop();
    }
    lines
}

fn line_operations<'a>(old: &'a str, new: &'a str) -> Vec<LineOperation<'a>> {
    let old = logical_lines(old);
    let new = logical_lines(new);
    let mut prefix = 0;
    while prefix < old.len() && prefix < new.len() && old[prefix] == new[prefix] {
        prefix += 1;
    }
    let mut suffix = 0;
    while suffix < old.len().saturating_sub(prefix)
        && suffix < new.len().saturating_sub(prefix)
        && old[old.len() - suffix - 1] == new[new.len() - suffix - 1]
    {
        suffix += 1;
    }

    let mut operations = old[..prefix]
        .iter()
        .copied()
        .map(LineOperation::Equal)
        .collect::<Vec<_>>();
    let old_middle = &old[prefix..old.len() - suffix];
    let new_middle = &new[prefix..new.len() - suffix];

    // The dynamic-programming matrix gives stable, Git-like line alignment for normal
    // source files. Extremely large replacements use a bounded fallback instead of
    // risking an unexpectedly large allocation.
    if old_middle.len().saturating_mul(new_middle.len()) > 4_000_000 {
        operations.extend(old_middle.iter().copied().map(LineOperation::Deletion));
        operations.extend(new_middle.iter().copied().map(LineOperation::Addition));
    } else {
        let columns = new_middle.len() + 1;
        let mut lcs = vec![0_u32; (old_middle.len() + 1) * columns];
        for old_index in (0..old_middle.len()).rev() {
            for new_index in (0..new_middle.len()).rev() {
                let index = old_index * columns + new_index;
                lcs[index] = if old_middle[old_index] == new_middle[new_index] {
                    lcs[(old_index + 1) * columns + new_index + 1] + 1
                } else {
                    lcs[(old_index + 1) * columns + new_index]
                        .max(lcs[old_index * columns + new_index + 1])
                };
            }
        }
        let (mut old_index, mut new_index) = (0, 0);
        while old_index < old_middle.len() && new_index < new_middle.len() {
            if old_middle[old_index] == new_middle[new_index] {
                operations.push(LineOperation::Equal(old_middle[old_index]));
                old_index += 1;
                new_index += 1;
            } else if lcs[(old_index + 1) * columns + new_index]
                >= lcs[old_index * columns + new_index + 1]
            {
                operations.push(LineOperation::Deletion(old_middle[old_index]));
                old_index += 1;
            } else {
                operations.push(LineOperation::Addition(new_middle[new_index]));
                new_index += 1;
            }
        }
        operations.extend(
            old_middle[old_index..]
                .iter()
                .copied()
                .map(LineOperation::Deletion),
        );
        operations.extend(
            new_middle[new_index..]
                .iter()
                .copied()
                .map(LineOperation::Addition),
        );
    }
    operations.extend(
        old[old.len() - suffix..]
            .iter()
            .copied()
            .map(LineOperation::Equal),
    );
    operations
}

fn diff_text(relative_path: &str, old: &str, new: &str) -> VersionFileDiff {
    let new_line_count = logical_lines(new).len();
    let (mut old_line, mut new_line) = (1, 1);
    let mut lines = Vec::new();
    let (mut additions, mut deletions) = (0, 0);
    for operation in line_operations(old, new) {
        match operation {
            LineOperation::Equal(_) => {
                old_line += 1;
                new_line += 1;
            }
            LineOperation::Addition(text) => {
                additions += 1;
                lines.push(VersionDiffLine {
                    kind: VersionDiffLineKind::Addition,
                    text: text.to_owned(),
                    old_line: None,
                    new_line: Some(new_line),
                    anchor_new_line: new_line,
                });
                new_line += 1;
            }
            LineOperation::Deletion(text) => {
                deletions += 1;
                lines.push(VersionDiffLine {
                    kind: VersionDiffLineKind::Deletion,
                    text: text.to_owned(),
                    old_line: Some(old_line),
                    new_line: None,
                    anchor_new_line: new_line.min(new_line_count + 1),
                });
                old_line += 1;
            }
        }
    }
    VersionFileDiff {
        relative_path: relative_path.to_owned(),
        additions,
        deletions,
        binary: false,
        lines,
    }
}

fn compare_entries(
    current: &[VersionFileEntry],
    target: &[VersionFileEntry],
) -> VersionChangeSummary {
    let current: HashMap<_, _> = current
        .iter()
        .map(|entry| (&entry.relative_path, entry))
        .collect();
    let target: HashMap<_, _> = target
        .iter()
        .map(|entry| (&entry.relative_path, entry))
        .collect();
    let mut added: Vec<String> = target
        .keys()
        .filter(|path| !current.contains_key(*path))
        .map(|path| (*path).clone())
        .collect();
    let mut removed: Vec<String> = current
        .keys()
        .filter(|path| !target.contains_key(*path))
        .map(|path| (*path).clone())
        .collect();
    let mut modified: Vec<String> = target
        .iter()
        .filter(|(path, entry)| {
            current
                .get(*path)
                .is_some_and(|current| *current != **entry)
        })
        .map(|(path, _)| (*path).clone())
        .collect();
    added.sort();
    modified.sort();
    removed.sort();
    VersionChangeSummary {
        added,
        modified,
        removed,
    }
}

fn apply_manifest(
    root: &Path,
    record: &VersionProjectRecord,
    manifest: &ProjectVersionManifest,
) -> CoreResult<()> {
    let stage = root.join(format!(".lightex-restore-{}", Uuid::new_v4()));
    let incoming = stage.join("incoming");
    let quarantine = stage.join("quarantine");
    fs::create_dir_all(&incoming)?;
    fs::create_dir_all(&quarantine)?;
    materialize(record, manifest, &incoming)?;
    let (current_directories, current_files, _) =
        capture_tree(root, manifest.main_document.as_deref(), None)?;
    let current_directories: HashSet<_> = current_directories.into_iter().collect();
    let target: HashMap<_, _> = manifest
        .files
        .iter()
        .map(|entry| (entry.relative_path.clone(), entry))
        .collect();
    let mut journal = RestoreJournal {
        schema_version: SCHEMA_VERSION,
        project_path: root.to_string_lossy().into_owned(),
        stage_path: stage.to_string_lossy().into_owned(),
        moved_paths: Vec::new(),
        installed_paths: Vec::new(),
        created_directories: Vec::new(),
    };
    write_journal(record, &journal)?;
    let result = (|| -> CoreResult<()> {
        let mut to_move: Vec<&VersionFileEntry> = current_files
            .iter()
            .filter(|entry| {
                target
                    .get(&entry.relative_path)
                    .is_none_or(|target| *target != *entry)
            })
            .collect();
        to_move.sort_by(|left, right| right.relative_path.len().cmp(&left.relative_path.len()));
        for entry in to_move {
            let source = root.join(normalized_relative(&entry.relative_path)?);
            if !source.exists() && !source.is_symlink() {
                continue;
            }
            let destination = quarantine.join(normalized_relative(&entry.relative_path)?);
            if let Some(parent) = destination.parent() {
                fs::create_dir_all(parent)?;
            }
            journal.moved_paths.push(entry.relative_path.clone());
            write_journal(record, &journal)?;
            fs::rename(&source, &destination)?;
        }
        for directory in &manifest.directories {
            if !current_directories.contains(directory) {
                journal.created_directories.push(directory.clone());
                write_journal(record, &journal)?;
            }
            fs::create_dir_all(root.join(normalized_relative(directory)?))?;
        }
        for entry in &manifest.files {
            let unchanged = current_files
                .iter()
                .find(|current| current.relative_path == entry.relative_path)
                .is_some_and(|current| current == entry);
            if unchanged {
                continue;
            }
            let source = incoming.join(normalized_relative(&entry.relative_path)?);
            let destination = root.join(normalized_relative(&entry.relative_path)?);
            if let Some(parent) = destination.parent() {
                fs::create_dir_all(parent)?;
            }
            if destination.is_dir() && !destination.is_symlink() {
                fs::remove_dir(&destination)?;
            }
            journal.installed_paths.push(entry.relative_path.clone());
            write_journal(record, &journal)?;
            fs::rename(source, &destination)?;
        }
        Ok(())
    })();
    if let Err(error) = result {
        let _ = rollback_journal(root, &journal);
        let _ = fs::remove_file(journal_path(record)?);
        let _ = fs::remove_dir_all(&stage);
        return Err(error);
    }
    remove_empty_old_directories(root, &manifest.directories)?;
    fs::remove_file(journal_path(record)?)?;
    fs::remove_dir_all(stage)?;
    Ok(())
}

fn recover_journal(root: &Path, record: &VersionProjectRecord) -> CoreResult<()> {
    let path = journal_path(record)?;
    let Some(journal) = read_json::<RestoreJournal>(&path)? else {
        return Ok(());
    };
    if journal.project_path != root.to_string_lossy() {
        return Err(CoreError::Message(
            "A previous restore needs recovery at the project's former location.".into(),
        ));
    }
    rollback_journal(root, &journal)?;
    if Path::new(&journal.stage_path).is_dir() {
        fs::remove_dir_all(&journal.stage_path)?;
    }
    fs::remove_file(path)?;
    Ok(())
}

fn rollback_journal(root: &Path, journal: &RestoreJournal) -> CoreResult<()> {
    let stage = PathBuf::from(&journal.stage_path);
    if !stage.starts_with(root)
        || !stage
            .file_name()
            .and_then(|value| value.to_str())
            .is_some_and(|name| name.starts_with(".lightex-restore-"))
    {
        return Err(CoreError::UnsafePath(stage));
    }
    for relative in journal.installed_paths.iter().rev() {
        let incoming = stage.join("incoming").join(normalized_relative(relative)?);
        if incoming.exists() || incoming.is_symlink() {
            // The journal entry is written before the atomic rename. If the staged
            // source still exists, the new file never reached the project.
            continue;
        }
        let path = root.join(normalized_relative(relative)?);
        if path.is_dir() && !path.is_symlink() {
            let _ = fs::remove_dir_all(path);
        } else if path.exists() || path.is_symlink() {
            let _ = fs::remove_file(path);
        }
    }
    for relative in journal.created_directories.iter().rev() {
        let path = root.join(normalized_relative(relative)?);
        if path.is_dir() && !path.is_symlink() {
            let _ = fs::remove_dir(path);
        }
    }
    for relative in journal.moved_paths.iter().rev() {
        let source = stage
            .join("quarantine")
            .join(normalized_relative(relative)?);
        let destination = root.join(normalized_relative(relative)?);
        if !source.exists() && !source.is_symlink() {
            continue;
        }
        if let Some(parent) = destination.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::rename(source, destination)?;
    }
    Ok(())
}

fn remove_empty_old_directories(root: &Path, target_directories: &[String]) -> CoreResult<()> {
    let keep: HashSet<_> = target_directories.iter().cloned().collect();
    let mut directories: Vec<PathBuf> = WalkDir::new(root)
        .min_depth(1)
        .follow_links(false)
        .into_iter()
        .filter_entry(|entry| included_walk_entry(root, entry))
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_dir())
        .map(|entry| entry.into_path())
        .collect();
    directories.sort_by_key(|path| std::cmp::Reverse(path.components().count()));
    for path in directories {
        let relative = path
            .strip_prefix(root)
            .unwrap()
            .to_string_lossy()
            .replace('\\', "/");
        if !keep.contains(&relative) {
            let _ = fs::remove_dir(path);
        }
    }
    Ok(())
}

fn prune_recovery_versions(record: &VersionProjectRecord) -> CoreResult<()> {
    let mut recovery: Vec<_> = manifests_for(record)?
        .into_iter()
        .filter(|manifest| manifest.kind == ProjectVersionKind::Recovery)
        .collect();
    recovery.sort_by(|left, right| right.created_at.cmp(&left.created_at));
    for manifest in recovery.into_iter().skip(RECOVERY_LIMIT) {
        remove_from_record(record, &manifest.id)?;
    }
    gc_objects(record)
}

fn remove_from_record(record: &VersionProjectRecord, id: &ProjectVersionId) -> CoreResult<()> {
    let path = manifest_path(record, id)?;
    if !path.is_file() {
        return Err(CoreError::Message(
            "The saved version no longer exists.".into(),
        ));
    }
    fs::remove_file(path)?;
    let preview = preview_directory(record, id)?;
    if preview.is_dir() {
        fs::remove_dir_all(preview)?;
    }
    Ok(())
}

fn gc_objects(record: &VersionProjectRecord) -> CoreResult<()> {
    let used: BTreeSet<String> = manifests_for(record)?
        .into_iter()
        .flat_map(|manifest| manifest.files)
        .filter_map(|entry| entry.blob_sha256)
        .collect();
    let objects = project_directory(record)?.join("objects");
    if !objects.is_dir() {
        return Ok(());
    }
    for entry in WalkDir::new(&objects).min_depth(2).max_depth(2) {
        let entry = entry.map_err(|error| CoreError::Message(error.to_string()))?;
        if !entry.file_type().is_file() {
            continue;
        }
        let prefix = entry
            .path()
            .parent()
            .and_then(|path| path.file_name())
            .and_then(|value| value.to_str())
            .unwrap_or_default();
        let suffix = entry.file_name().to_string_lossy();
        if !used.contains(&format!("{prefix}{suffix}")) {
            fs::remove_file(entry.path())?;
        }
    }
    for entry in fs::read_dir(objects)? {
        let path = entry?.path();
        if path.is_dir() {
            let _ = fs::remove_dir(path);
        }
    }
    Ok(())
}

fn insert_tree_path(root: &mut TreeNode, path: &str, directory: bool) -> CoreResult<()> {
    let path = normalized_relative(path)?;
    let components: Vec<String> = Path::new(&path)
        .components()
        .filter_map(|component| match component {
            Component::Normal(value) => Some(value.to_string_lossy().into_owned()),
            _ => None,
        })
        .collect();
    let mut current = root;
    for (index, component) in components.iter().enumerate() {
        current = current.children.entry(component.clone()).or_default();
        current.is_directory = index + 1 < components.len() || directory;
    }
    Ok(())
}

fn tree_entries(root: TreeNode) -> Vec<ProjectEntry> {
    root.children
        .into_iter()
        .map(|(name, node)| tree_entry(name, node, ""))
        .collect()
}

fn tree_entry(name: String, node: TreeNode, parent: &str) -> ProjectEntry {
    let relative_path = if parent.is_empty() {
        name.clone()
    } else {
        format!("{parent}/{name}")
    };
    let children = node
        .children
        .into_iter()
        .map(|(child, node)| tree_entry(child, node, &relative_path))
        .collect();
    ProjectEntry {
        name,
        relative_path,
        is_directory: node.is_directory,
        children,
    }
}

fn normalized_relative(value: &str) -> CoreResult<String> {
    let path = Path::new(value);
    if value.is_empty()
        || path.is_absolute()
        || path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err(CoreError::UnsafePath(path.to_path_buf()));
    }
    Ok(path.to_string_lossy().replace('\\', "/"))
}

fn validated_uuid(value: &str) -> CoreResult<Uuid> {
    Uuid::parse_str(value)
        .map_err(|_| CoreError::InvalidManifest("A version identifier is invalid.".into()))
}

fn validated_name(value: &str) -> CoreResult<&str> {
    let value = value.trim();
    if value.is_empty() || value.chars().count() > 80 || value.chars().any(char::is_control) {
        return Err(CoreError::Message(
            "Enter a version name between 1 and 80 characters.".into(),
        ));
    }
    Ok(value)
}

fn shortened_name(value: &str, limit: usize) -> String {
    let was_shortened = value.chars().count() > limit;
    let mut result: String = value.chars().take(limit).collect();
    if was_shortened {
        result.push('…');
    }
    result
}

fn journal_path(record: &VersionProjectRecord) -> CoreResult<PathBuf> {
    Ok(project_directory(record)?.join("restore-journal.json"))
}

fn write_journal(record: &VersionProjectRecord, journal: &RestoreJournal) -> CoreResult<()> {
    write_json(&journal_path(record)?, journal)
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> CoreResult<Option<T>> {
    if !path.is_file() {
        return Ok(None);
    }
    Ok(Some(serde_json::from_slice(&fs::read(path)?)?))
}

fn write_json(path: &Path, value: &impl Serialize) -> CoreResult<()> {
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

fn unix_mode(path: &Path) -> Option<u32> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::symlink_metadata(path)
            .ok()
            .map(|metadata| metadata.permissions().mode())
    }
    #[cfg(not(unix))]
    {
        let _ = path;
        None
    }
}

fn set_unix_mode(path: &Path, mode: Option<u32>) -> CoreResult<()> {
    #[cfg(unix)]
    if let Some(mode) = mode {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(mode))?;
    }
    #[cfg(not(unix))]
    let _ = (path, mode);
    Ok(())
}

fn create_symlink(target: &Path, destination: &Path) -> CoreResult<()> {
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(target, destination)?;
        Ok(())
    }
    #[cfg(not(unix))]
    {
        let _ = (target, destination);
        Err(CoreError::Message(
            "Symbolic links are unsupported on this platform.".into(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn project() -> tempfile::TempDir {
        let root = tempfile::tempdir().unwrap();
        TEST_VERSIONS_ROOT.with(|value| {
            *value.borrow_mut() = Some(root.path().join(".lightex-test-versions"));
        });
        fs::write(root.path().join("main.tex"), "before").unwrap();
        fs::create_dir(root.path().join("figures")).unwrap();
        fs::write(root.path().join("figures/a.bin"), [0_u8, 1, 2]).unwrap();
        fs::create_dir(root.path().join(".git")).unwrap();
        fs::write(root.path().join(".git/HEAD"), "ref: refs/heads/main").unwrap();
        root
    }

    #[test]
    fn saves_deduplicated_versions_without_git_metadata() {
        let root = project();
        let first = create(
            root.path(),
            "First",
            ProjectVersionKind::Named,
            Some("main.tex".into()),
        )
        .unwrap();
        let second = create(
            root.path(),
            "Second",
            ProjectVersionKind::Named,
            Some("main.tex".into()),
        )
        .unwrap();
        assert_eq!(first.total_size, second.total_size);
        let record = resolve_project(root.path()).unwrap();
        let objects = project_directory(&record).unwrap().join("objects");
        let count = WalkDir::new(objects)
            .into_iter()
            .filter_map(Result::ok)
            .filter(|entry| entry.file_type().is_file())
            .count();
        assert_eq!(count, 2);
        assert_eq!(
            fs::read_to_string(root.path().join(".git/HEAD")).unwrap(),
            "ref: refs/heads/main"
        );
    }

    #[test]
    fn creates_line_diff_with_stable_old_and_new_positions() {
        let diff = diff_text(
            "main.tex",
            "same\nold value\nlast\n",
            "same\nnew value\nlast\n",
        );
        assert_eq!(diff.additions, 1);
        assert_eq!(diff.deletions, 1);
        assert_eq!(diff.lines.len(), 2);
        assert_eq!(diff.lines[0].kind, VersionDiffLineKind::Deletion);
        assert_eq!(diff.lines[0].old_line, Some(2));
        assert_eq!(diff.lines[0].anchor_new_line, 2);
        assert_eq!(diff.lines[1].kind, VersionDiffLineKind::Addition);
        assert_eq!(diff.lines[1].new_line, Some(2));
    }

    #[test]
    fn line_summary_uses_unsaved_editor_buffers() {
        let root = project();
        fs::write(root.path().join("main.tex"), "one\ntwo\n").unwrap();
        let saved = create(
            root.path(),
            "First",
            ProjectVersionKind::Named,
            Some("main.tex".into()),
        )
        .unwrap();
        let summary = line_summary(
            root.path(),
            &saved.id,
            &[OpenBuffer {
                relative_path: "main.tex".into(),
                text: "one\nchanged\nthree\n".into(),
            }],
        )
        .unwrap();
        assert_eq!(summary.additions, 1);
        assert_eq!(summary.deletions, 2);
        assert_eq!(summary.changed_files, 1);
    }

    #[test]
    fn binary_files_have_no_fake_line_changes() {
        let root = project();
        let saved = create(
            root.path(),
            "First",
            ProjectVersionKind::Named,
            Some("main.tex".into()),
        )
        .unwrap();
        fs::write(root.path().join("figures/a.bin"), [0_u8, 9, 2]).unwrap();
        let diff = file_diff(root.path(), &saved.id, "figures/a.bin", None).unwrap();
        assert!(diff.binary);
        assert!(diff.lines.is_empty());
    }

    #[test]
    fn restores_the_whole_project_and_creates_recovery_version() {
        let root = project();
        let saved = create(
            root.path(),
            "First",
            ProjectVersionKind::Named,
            Some("main.tex".into()),
        )
        .unwrap();
        fs::write(root.path().join("main.tex"), "after").unwrap();
        fs::write(root.path().join("new.tex"), "new").unwrap();
        let outcome = restore(root.path(), &saved.id, Some("main.tex".into())).unwrap();
        assert_eq!(
            fs::read_to_string(root.path().join("main.tex")).unwrap(),
            "before"
        );
        assert!(!root.path().join("new.tex").exists());
        assert_eq!(outcome.recovery_version.kind, ProjectVersionKind::Recovery);
        assert_eq!(
            fs::read_to_string(root.path().join(".git/HEAD")).unwrap(),
            "ref: refs/heads/main"
        );
    }

    #[test]
    fn rejects_traversal_when_reading_a_version() {
        let root = project();
        let saved = create(
            root.path(),
            "First",
            ProjectVersionKind::Named,
            Some("main.tex".into()),
        )
        .unwrap();
        assert!(read_text(root.path(), &saved.id, "../main.tex").is_err());
    }

    #[test]
    fn keeps_history_when_the_project_folder_moves_on_the_same_disk() {
        let container = tempfile::tempdir().unwrap();
        let original = container.path().join("original");
        let moved = container.path().join("moved");
        fs::create_dir(&original).unwrap();
        fs::write(original.join("main.tex"), "draft").unwrap();
        TEST_VERSIONS_ROOT.with(|value| {
            *value.borrow_mut() = Some(container.path().join("versions"));
        });
        let saved = create(
            &original,
            "Milestone",
            ProjectVersionKind::Named,
            Some("main.tex".into()),
        )
        .unwrap();
        fs::rename(&original, &moved).unwrap();
        let versions = list(&moved).unwrap();
        assert_eq!(versions.len(), 1);
        assert_eq!(versions[0].id, saved.id);
        let catalog: VersionCatalog = read_json(&container.path().join("versions/catalog.json"))
            .unwrap()
            .unwrap();
        assert_eq!(
            catalog.projects[0].last_known_path,
            moved.canonicalize().unwrap().to_string_lossy()
        );
    }

    #[test]
    fn refuses_to_restore_a_corrupted_blob() {
        let root = project();
        let saved = create(
            root.path(),
            "First",
            ProjectVersionKind::Named,
            Some("main.tex".into()),
        )
        .unwrap();
        let record = resolve_project(root.path()).unwrap();
        let manifest = load_manifest(&record, &saved.id).unwrap();
        let digest = manifest
            .files
            .iter()
            .find(|entry| entry.relative_path == "main.tex")
            .unwrap()
            .blob_sha256
            .as_deref()
            .unwrap();
        let object =
            object_path(&project_directory(&record).unwrap().join("objects"), digest).unwrap();
        fs::write(object, "damaged").unwrap();
        fs::write(root.path().join("main.tex"), "current work").unwrap();
        assert!(restore(root.path(), &saved.id, Some("main.tex".into())).is_err());
        assert_eq!(
            fs::read_to_string(root.path().join("main.tex")).unwrap(),
            "current work"
        );
    }

    #[test]
    fn restores_a_file_over_a_directory() {
        let root = project();
        fs::write(root.path().join("node"), "saved as a file").unwrap();
        let saved = create(
            root.path(),
            "File shape",
            ProjectVersionKind::Named,
            Some("main.tex".into()),
        )
        .unwrap();
        fs::remove_file(root.path().join("node")).unwrap();
        fs::create_dir(root.path().join("node")).unwrap();
        fs::write(root.path().join("node/child.tex"), "later").unwrap();
        restore(root.path(), &saved.id, Some("main.tex".into())).unwrap();
        assert_eq!(
            fs::read_to_string(root.path().join("node")).unwrap(),
            "saved as a file"
        );
    }

    #[test]
    fn rolls_back_a_partially_applied_restore_journal() {
        let root = project();
        let stage = root.path().join(".lightex-restore-test");
        fs::create_dir_all(stage.join("incoming")).unwrap();
        fs::create_dir_all(stage.join("quarantine")).unwrap();
        fs::rename(
            root.path().join("main.tex"),
            stage.join("quarantine/main.tex"),
        )
        .unwrap();
        fs::write(root.path().join("replacement.tex"), "partial install").unwrap();
        fs::create_dir(root.path().join("new-empty-folder")).unwrap();
        let journal = RestoreJournal {
            schema_version: SCHEMA_VERSION,
            project_path: root.path().to_string_lossy().into_owned(),
            stage_path: stage.to_string_lossy().into_owned(),
            moved_paths: vec!["main.tex".into()],
            installed_paths: vec!["replacement.tex".into()],
            created_directories: vec!["new-empty-folder".into()],
        };
        rollback_journal(root.path(), &journal).unwrap();
        assert_eq!(
            fs::read_to_string(root.path().join("main.tex")).unwrap(),
            "before"
        );
        assert!(!root.path().join("replacement.tex").exists());
        assert!(!root.path().join("new-empty-folder").exists());
    }

    #[test]
    fn keeps_only_ten_automatic_recovery_versions() {
        let root = project();
        for index in 0..12 {
            create(
                root.path(),
                &format!("Recovery {index}"),
                ProjectVersionKind::Recovery,
                Some("main.tex".into()),
            )
            .unwrap();
        }
        let recovery = list(root.path())
            .unwrap()
            .into_iter()
            .filter(|version| version.kind == ProjectVersionKind::Recovery)
            .count();
        assert_eq!(recovery, RECOVERY_LIMIT);
    }

    #[cfg(unix)]
    #[test]
    fn preserves_symlinks_without_following_them() {
        let root = project();
        let outside = tempfile::tempdir().unwrap();
        let secret = outside.path().join("secret.txt");
        fs::write(&secret, "outside").unwrap();
        std::os::unix::fs::symlink(&secret, root.path().join("external-link")).unwrap();
        let saved = create(
            root.path(),
            "Links",
            ProjectVersionKind::Named,
            Some("main.tex".into()),
        )
        .unwrap();
        fs::remove_file(root.path().join("external-link")).unwrap();
        restore(root.path(), &saved.id, Some("main.tex".into())).unwrap();
        assert_eq!(
            fs::read_link(root.path().join("external-link")).unwrap(),
            secret
        );
        assert_eq!(
            fs::read_to_string(outside.path().join("secret.txt")).unwrap(),
            "outside"
        );
    }
}
