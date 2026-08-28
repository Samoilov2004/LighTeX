use std::{collections::BTreeSet, fs, path::Path, sync::OnceLock};

use regex::Regex;

use crate::{ProjectCompletionIndex, project::editable_files};

pub fn build_index(root: &Path) -> ProjectCompletionIndex {
    static LABEL: OnceLock<Regex> = OnceLock::new();
    static CITE: OnceLock<Regex> = OnceLock::new();
    static PACKAGE: OnceLock<Regex> = OnceLock::new();
    static BIB_ENTRY: OnceLock<Regex> = OnceLock::new();
    let label = LABEL.get_or_init(|| Regex::new(r"\\label\{([^}]+)\}").unwrap());
    let cite = CITE.get_or_init(|| Regex::new(r"\\cite[a-zA-Z*]*\{([^}]+)\}").unwrap());
    let package =
        PACKAGE.get_or_init(|| Regex::new(r"\\usepackage(?:\[[^]]*\])?\{([^}]+)\}").unwrap());
    let bib_entry =
        BIB_ENTRY.get_or_init(|| Regex::new(r"(?m)^@[A-Za-z]+\s*\{\s*([^,\s]+)").unwrap());
    let mut labels = BTreeSet::new();
    let mut citations = BTreeSet::new();
    let mut packages = BTreeSet::new();
    let mut classes = BTreeSet::new();
    let mut input_paths = BTreeSet::new();
    let mut image_paths = BTreeSet::new();
    for path in editable_files(root) {
        let relative = path
            .strip_prefix(root)
            .unwrap()
            .to_string_lossy()
            .replace('\\', "/");
        match path
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
        {
            "tex" => {
                let source = fs::read_to_string(&path).unwrap_or_default();
                for capture in label.captures_iter(&source) {
                    labels.insert(capture[1].to_owned());
                }
                for capture in cite.captures_iter(&source) {
                    citations.extend(capture[1].split(',').map(|value| value.trim().to_owned()));
                }
                for capture in package.captures_iter(&source) {
                    packages.extend(capture[1].split(',').map(|value| value.trim().to_owned()));
                }
                input_paths.insert(relative);
            }
            "bib" => {
                let source = fs::read_to_string(&path).unwrap_or_default();
                citations.extend(
                    bib_entry
                        .captures_iter(&source)
                        .map(|capture| capture[1].to_owned()),
                );
                input_paths.insert(relative);
            }
            "sty" => {
                packages.insert(relative.trim_end_matches(".sty").to_owned());
            }
            "cls" => {
                classes.insert(relative.trim_end_matches(".cls").to_owned());
            }
            _ => {}
        }
    }
    for entry in walkdir::WalkDir::new(root)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
    {
        let extension = entry
            .path()
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_lowercase();
        if matches!(
            extension.as_str(),
            "png" | "jpg" | "jpeg" | "pdf" | "svg" | "eps"
        ) {
            image_paths.insert(
                entry
                    .path()
                    .strip_prefix(root)
                    .unwrap()
                    .to_string_lossy()
                    .replace('\\', "/"),
            );
        }
    }
    ProjectCompletionIndex {
        labels: labels.into_iter().collect(),
        citations: citations.into_iter().collect(),
        packages: packages.into_iter().collect(),
        classes: classes.into_iter().collect(),
        input_paths: input_paths.into_iter().collect(),
        image_paths: image_paths.into_iter().collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn indexes_labels_and_bibliography() {
        let root = tempfile::tempdir().unwrap();
        fs::write(
            root.path().join("main.tex"),
            "\\label{eq:one}\n\\cite{gauss}",
        )
        .unwrap();
        fs::write(root.path().join("refs.bib"), "@book{euler, title={A}}").unwrap();
        let index = build_index(root.path());
        assert!(index.labels.contains(&"eq:one".into()));
        assert!(index.citations.contains(&"euler".into()));
    }
}
