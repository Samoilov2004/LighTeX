use std::{collections::HashMap, fs, path::Path};

use regex::{Regex, RegexBuilder};

use crate::{
    CoreResult, OpenBuffer, ReplacePreview, SearchQuery, SearchResult, project::editable_files,
};

pub const MAXIMUM_RESULTS: usize = 2_000;

pub fn search(
    root: &Path,
    query: &SearchQuery,
    buffers: &[OpenBuffer],
) -> CoreResult<Vec<SearchResult>> {
    if query.text.is_empty() {
        return Ok(Vec::new());
    }
    let expression = expression(query)?;
    let overlays: HashMap<&str, &str> = buffers
        .iter()
        .map(|buffer| (buffer.relative_path.as_str(), buffer.text.as_str()))
        .collect();
    let mut results = Vec::new();
    for path in editable_files(root) {
        if results.len() >= MAXIMUM_RESULTS {
            break;
        }
        let relative = path
            .strip_prefix(root)
            .unwrap()
            .to_string_lossy()
            .replace('\\', "/");
        let source = overlays
            .get(relative.as_str())
            .map(|value| (*value).to_owned())
            .unwrap_or_else(|| fs::read_to_string(&path).unwrap_or_default());
        for matched in expression.find_iter(&source) {
            if results.len() >= MAXIMUM_RESULTS {
                break;
            }
            let before = &source[..matched.start()];
            let line = before.bytes().filter(|byte| *byte == b'\n').count() + 1;
            let line_start = before.rfind('\n').map_or(0, |index| index + 1);
            let line_end = source[matched.end()..]
                .find('\n')
                .map_or(source.len(), |index| matched.end() + index);
            let column = source[line_start..matched.start()].chars().count() + 1;
            results.push(SearchResult {
                relative_path: relative.clone(),
                line,
                column,
                preview: source[line_start..line_end].trim().to_owned(),
                match_start: matched.start(),
                match_length: matched.end() - matched.start(),
            });
        }
    }
    Ok(results)
}

pub fn replacement_preview(
    root: &Path,
    query: &SearchQuery,
    replacement: &str,
    buffers: &[OpenBuffer],
) -> CoreResult<Vec<ReplacePreview>> {
    if query.text.is_empty() {
        return Ok(Vec::new());
    }
    let expression = expression(query)?;
    let overlays: HashMap<&str, &str> = buffers
        .iter()
        .map(|buffer| (buffer.relative_path.as_str(), buffer.text.as_str()))
        .collect();
    let mut changes = Vec::new();
    for path in editable_files(root) {
        let relative = path
            .strip_prefix(root)
            .unwrap()
            .to_string_lossy()
            .replace('\\', "/");
        let source = overlays
            .get(relative.as_str())
            .map(|value| (*value).to_owned())
            .unwrap_or_else(|| fs::read_to_string(&path).unwrap_or_default());
        let count = expression.find_iter(&source).count();
        if count == 0 {
            continue;
        }
        let replacement_text = if query.uses_regular_expression {
            expression.replace_all(&source, replacement).into_owned()
        } else {
            expression
                .replace_all(&source, regex::NoExpand(replacement))
                .into_owned()
        };
        changes.push(ReplacePreview {
            relative_path: relative,
            replacements: count,
            original_text: source,
            replacement_text,
        });
    }
    Ok(changes)
}

pub fn apply_replacements(root: &Path, changes: &[ReplacePreview], undo: bool) -> CoreResult<()> {
    for change in changes {
        let path = crate::paths::safe_relative_path(root, &change.relative_path)?;
        let expected = if undo {
            &change.replacement_text
        } else {
            &change.original_text
        };
        let replacement = if undo {
            &change.original_text
        } else {
            &change.replacement_text
        };
        let current = fs::read_to_string(&path)?;
        if &current != expected {
            return Err(crate::CoreError::Message(format!(
                "{} changed after the replacement preview. Run the search again.",
                change.relative_path
            )));
        }
        let revision = crate::document::current_revision(&path)?.expect("replacement file exists");
        match crate::document::save(&path, replacement, Some(&revision), false)? {
            crate::SaveOutcome::Saved { .. } => {}
            _ => return Err(crate::CoreError::DocumentConflict),
        }
    }
    Ok(())
}

fn expression(query: &SearchQuery) -> CoreResult<Regex> {
    let body = if query.uses_regular_expression {
        query.text.clone()
    } else {
        regex::escape(&query.text)
    };
    let pattern = if query.whole_word {
        format!(r"\b(?:{body})\b")
    } else {
        body
    };
    Ok(RegexBuilder::new(&pattern)
        .case_insensitive(!query.case_sensitive)
        .multi_line(true)
        .build()?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn searches_unsaved_buffer_text() {
        let root = tempfile::tempdir().unwrap();
        fs::write(root.path().join("main.tex"), "disk").unwrap();
        let results = search(
            root.path(),
            &SearchQuery {
                text: "unsaved".into(),
                case_sensitive: false,
                whole_word: false,
                uses_regular_expression: false,
            },
            &[OpenBuffer {
                relative_path: "main.tex".into(),
                text: "hello unsaved".into(),
            }],
        )
        .unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].column, 7);
    }
}
