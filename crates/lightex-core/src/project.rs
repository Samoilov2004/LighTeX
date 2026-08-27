use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
    sync::RwLock,
};

use uuid::Uuid;

use crate::{
    CoreError, CoreResult, ProjectEntry, ProjectHandle, ProjectId,
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
    template: &str,
) -> CoreResult<PathBuf> {
    let root = create_project(parent, name)?;
    let source = match template {
        "article" => {
            "\\documentclass[11pt]{article}\n\\usepackage[T1]{fontenc}\n\\usepackage{amsmath,amssymb}\n\\usepackage{graphicx}\n\\usepackage{hyperref}\n\\title{Article Title}\n\\author{Your Name}\n\\date{\\today}\n\\begin{document}\n\\maketitle\n\\begin{abstract}\nA concise summary of the work.\n\\end{abstract}\n\\section{Introduction}\nStart writing here.\n\\end{document}\n"
        }
        "mathematics" => {
            "\\documentclass[11pt]{article}\n\\usepackage[T1]{fontenc}\n\\usepackage{amsmath,amssymb,amsthm,mathtools}\n\\newtheorem{theorem}{Theorem}\n\\newtheorem{definition}{Definition}\n\\title{Mathematical Notes}\n\\author{Your Name}\n\\begin{document}\n\\maketitle\n\\section{Preliminaries}\n\\begin{definition}\nA useful definition.\n\\end{definition}\n\\begin{theorem}\nA significant result.\n\\end{theorem}\n\\begin{proof}\nWrite the proof here.\n\\end{proof}\n\\end{document}\n"
        }
        "textbook" => {
            "\\documentclass[11pt,oneside]{book}\n\\usepackage[T1]{fontenc}\n\\usepackage{amsmath,amssymb,amsthm,graphicx,booktabs}\n\\title{Textbook Title}\n\\author{Your Name}\n\\begin{document}\n\\frontmatter\n\\maketitle\n\\tableofcontents\n\\mainmatter\n\\chapter{Foundations}\n\\section{First Ideas}\nStart writing here.\n\\end{document}\n"
        }
        "presentation" => {
            "\\documentclass{beamer}\n\\usetheme{default}\n\\title{Presentation Title}\n\\author{Your Name}\n\\begin{document}\n\\begin{frame}\n  \\titlepage\n\\end{frame}\n\\begin{frame}{Main Idea}\n  \\begin{itemize}\n    \\item First point\n    \\item Second point\n  \\end{itemize}\n\\end{frame}\n\\end{document}\n"
        }
        _ => return Ok(root),
    };
    fs::write(root.join("main.tex"), source)?;
    if matches!(template, "article" | "textbook") {
        fs::create_dir_all(root.join("figures"))?;
    }
    Ok(root)
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
}
