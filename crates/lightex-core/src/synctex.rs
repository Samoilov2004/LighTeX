use std::path::{Path, PathBuf};

use tokio::process::Command;

use crate::{CoreResult, SyncTeXPdfTarget, SyncTeXSourceTarget};

pub async fn forward(
    executable: &Path,
    root: &Path,
    source_relative: &str,
    line: usize,
    column: usize,
    pdf_path: &Path,
) -> CoreResult<Option<SyncTeXPdfTarget>> {
    let source = crate::paths::safe_relative_path(root, source_relative)?;
    let output = Command::new(executable)
        .args([
            "view",
            "-i",
            &format!("{}:{}:{}", line.max(1), column.max(1), source.display()),
            "-o",
            &pdf_path.to_string_lossy(),
        ])
        .current_dir(root)
        .output()
        .await?;
    if !output.status.success() {
        return Ok(None);
    }
    Ok(parse_forward(&String::from_utf8_lossy(&output.stdout)))
}

pub async fn inverse(
    executable: &Path,
    root: &Path,
    pdf_path: &Path,
    page: usize,
    x: f64,
    y_from_top: f64,
) -> CoreResult<Option<SyncTeXSourceTarget>> {
    let position = format!(
        "{}:{x:.3}:{y_from_top:.3}:{}",
        page.max(1),
        pdf_path.display()
    );
    let output = Command::new(executable)
        .args(["edit", "-o", &position])
        .current_dir(root)
        .output()
        .await?;
    if !output.status.success() {
        return Ok(None);
    }
    Ok(parse_inverse(
        &String::from_utf8_lossy(&output.stdout),
        root,
    ))
}

pub fn parse_forward(output: &str) -> Option<SyncTeXPdfTarget> {
    let mut page = None;
    let mut x = None;
    let mut y = None;
    for line in output.lines().map(str::trim) {
        if let Some(value) = line.strip_prefix("Page:") {
            page = value.trim().parse::<usize>().ok();
        } else if let Some(value) = line.strip_prefix("x:") {
            x = value.trim().parse::<f64>().ok();
        } else if let Some(value) = line.strip_prefix("y:") {
            y = value.trim().parse::<f64>().ok();
        }
    }
    page.map(|page| SyncTeXPdfTarget {
        page,
        x,
        y_from_top: y,
    })
}

pub fn parse_inverse(output: &str, root: &Path) -> Option<SyncTeXSourceTarget> {
    let mut input = None;
    let mut line = None;
    let mut column = None;
    for value in output.lines().map(str::trim) {
        if let Some(raw) = value.strip_prefix("Input:") {
            input = Some(raw.trim().to_owned());
        } else if let Some(raw) = value.strip_prefix("Line:") {
            line = raw.trim().parse::<usize>().ok();
        } else if let Some(raw) = value.strip_prefix("Column:") {
            column = raw.trim().parse::<usize>().ok();
        }
    }
    let input = input?;
    let absolute = if Path::new(&input).is_absolute() {
        PathBuf::from(input)
    } else {
        root.join(input)
    };
    let relative = absolute
        .strip_prefix(root)
        .ok()?
        .to_string_lossy()
        .replace('\\', "/");
    Some(SyncTeXSourceTarget {
        relative_path: relative,
        line: line.unwrap_or(1).max(1),
        column: column.map_or(1, |value| value + 1),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_both_directions() {
        assert_eq!(
            parse_forward("Page:2\nx:12.5\ny:44"),
            Some(SyncTeXPdfTarget {
                page: 2,
                x: Some(12.5),
                y_from_top: Some(44.0)
            })
        );
        let root = Path::new("/tmp/project");
        let target = parse_inverse("Input:/tmp/project/main.tex\nLine:7\nColumn:0", root).unwrap();
        assert_eq!(target.relative_path, "main.tex");
        assert_eq!(target.column, 1);
    }
}
