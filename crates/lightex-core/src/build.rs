use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
    process::Stdio,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

use regex::Regex;
use sha2::{Digest, Sha256};
use tokio::process::Command;

use crate::{
    BuildDiagnostic, BuildDiagnosticGroup, BuildRequest, BuildResult, BuildTool, CoreError,
    CoreResult, DiagnosticSeverity, paths,
};

pub async fn run(root: &Path, request: &BuildRequest) -> CoreResult<BuildResult> {
    run_cancellable(root, request, Arc::new(AtomicBool::new(false))).await
}

pub async fn run_cancellable(
    root: &Path,
    request: &BuildRequest,
    cancel: Arc<AtomicBool>,
) -> CoreResult<BuildResult> {
    run_cancellable_in(root, request, cancel, None).await
}

async fn run_cancellable_in(
    root: &Path,
    request: &BuildRequest,
    cancel: Arc<AtomicBool>,
    cache_override: Option<&Path>,
) -> CoreResult<BuildResult> {
    let entry = crate::paths::safe_relative_path(root, &request.entry_file)?;
    if !entry.is_file() {
        return Err(CoreError::Message(format!(
            "The main document does not exist: {}",
            request.entry_file
        )));
    }
    let executable = PathBuf::from(&request.executable_path);
    if !executable.is_absolute() || !executable.is_file() {
        return Err(CoreError::MissingTool(request.executable_path.clone()));
    }
    let cache = match cache_override {
        Some(base) => build_cache_in(base, root, &entry)?,
        None => build_cache(root, &entry)?,
    };
    let arguments = build_arguments(&cache, &entry, request);
    let mut environment: HashMap<String, String> = std::env::vars().collect();
    let mut search = request.search_directories.clone();
    if let Some(parent) = executable.parent() {
        search.push(parent.to_string_lossy().into_owned());
    }
    search.push(
        environment
            .get("PATH")
            .cloned()
            .unwrap_or_else(|| "/usr/bin:/bin".into()),
    );
    environment.insert("PATH".into(), search.join(":"));

    let child = Command::new(&executable)
        .args(&arguments)
        .current_dir(entry.parent().unwrap_or(root))
        .envs(environment)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()?;
    let output_future = child.wait_with_output();
    tokio::pin!(output_future);
    let output = loop {
        tokio::select! {
            output = &mut output_future => break output?,
            _ = tokio::time::sleep(std::time::Duration::from_millis(75)) => {
                if cancel.load(Ordering::Relaxed) {
                    return Err(CoreError::Cancelled);
                }
            }
        }
    };
    let mut log = String::from_utf8_lossy(&output.stdout).into_owned();
    log.push_str(&String::from_utf8_lossy(&output.stderr));
    let cached_pdf = cache.join(entry.file_stem().unwrap()).with_extension("pdf");
    let success = output.status.success() && cached_pdf.is_file();
    let compiler_log =
        fs::read_to_string(cache.join(entry.file_stem().unwrap()).with_extension("log")).ok();
    let (diagnostics, used_compiler_log) = diagnostics_with_compiler_log_fallback(
        &log,
        compiler_log.as_deref(),
        root,
        entry.parent().unwrap_or(root),
    );
    let missing_package_file =
        missing_package(&log).or_else(|| compiler_log.as_deref().and_then(missing_package));
    if !success && used_compiler_log {
        log.push_str("\n\n--- TeX engine log ---\n");
        log.push_str(compiler_log.as_deref().unwrap_or_default());
    }
    if !success {
        return Ok(BuildResult {
            succeeded: false,
            log,
            preview_pdf_path: None,
            project_pdf_path: None,
            diagnostics,
            missing_package_file,
        });
    }
    let project_pdf = entry.with_extension("pdf");
    atomic_copy(&cached_pdf, &project_pdf)?;
    Ok(BuildResult {
        succeeded: true,
        log,
        preview_pdf_path: Some(cached_pdf.to_string_lossy().into_owned()),
        project_pdf_path: Some(project_pdf.to_string_lossy().into_owned()),
        diagnostics,
        missing_package_file: None,
    })
}

pub fn parse_diagnostics(log: &str, root: &Path) -> Vec<BuildDiagnosticGroup> {
    parse_diagnostics_from(log, root, root)
}

fn diagnostics_with_compiler_log_fallback(
    process_log: &str,
    compiler_log: Option<&str>,
    root: &Path,
    working_directory: &Path,
) -> (Vec<BuildDiagnosticGroup>, bool) {
    let diagnostics = parse_diagnostics_from(process_log, root, working_directory);
    if !diagnostics.is_empty() {
        return (diagnostics, false);
    }
    let Some(compiler_log) = compiler_log else {
        return (diagnostics, false);
    };
    let fallback = parse_diagnostics_from(compiler_log, root, working_directory);
    let used_fallback = !fallback.is_empty();
    (fallback, used_fallback)
}

fn parse_diagnostics_from(
    log: &str,
    root: &Path,
    working_directory: &Path,
) -> Vec<BuildDiagnosticGroup> {
    let file_line = Regex::new(r"(?m)^(.+?\.(?:tex|sty|cls|ltx|bib)):(\d+):\s*(.+)$").unwrap();
    let warning = Regex::new(r"(?mi)^(?:LaTeX|Package .+?) Warning:\s*(.+)$").unwrap();
    let error = Regex::new(r"(?m)^!\s*(.+)$").unwrap();
    let mut diagnostics = Vec::new();
    for capture in file_line.captures_iter(log) {
        let raw = capture.get(1).unwrap().as_str();
        let relative = diagnostic_path(raw, root, working_directory);
        diagnostics.push(BuildDiagnostic {
            severity: DiagnosticSeverity::Error,
            relative_path: relative,
            line: capture.get(2).and_then(|value| value.as_str().parse().ok()),
            message: complete_wrapped_message(log, &capture),
        });
    }
    for capture in error.captures_iter(log) {
        let message = capture.get(1).unwrap().as_str().trim().to_owned();
        if !diagnostics.iter().any(|item| item.message == message) {
            diagnostics.push(BuildDiagnostic {
                severity: DiagnosticSeverity::Error,
                relative_path: None,
                line: None,
                message,
            });
        }
    }
    for capture in warning.captures_iter(log) {
        diagnostics.push(BuildDiagnostic {
            severity: DiagnosticSeverity::Warning,
            relative_path: None,
            line: None,
            message: capture.get(1).unwrap().as_str().trim().to_owned(),
        });
    }
    let mut groups: Vec<BuildDiagnosticGroup> = Vec::new();
    for diagnostic in diagnostics {
        if let Some(group) = groups.last_mut().filter(|group| {
            group.primary.severity == diagnostic.severity
                && group.primary.relative_path == diagnostic.relative_path
                && group.primary.line == diagnostic.line
        }) {
            group.related.push(diagnostic);
        } else {
            groups.push(BuildDiagnosticGroup {
                primary: diagnostic,
                related: Vec::new(),
            });
        }
    }
    groups
}

fn complete_wrapped_message(log: &str, capture: &regex::Captures<'_>) -> String {
    let mut message = capture.get(3).unwrap().as_str().trim().to_owned();
    let Some(full_match) = capture.get(0) else {
        return message;
    };
    let remainder = log.get(full_match.end()..).unwrap_or_default();
    let continuation = remainder
        .strip_prefix("\r\n")
        .or_else(|| remainder.strip_prefix('\n'))
        .and_then(|rest| rest.lines().next())
        .map(str::trim)
        .unwrap_or_default();
    let looks_like_continuation = !continuation.is_empty()
        && continuation.len() <= 48
        && continuation
            .chars()
            .next()
            .is_some_and(char::is_alphanumeric)
        && !continuation.starts_with("LaTeX")
        && !continuation.starts_with("Package")
        && !continuation.starts_with("Latexmk")
        && !continuation.starts_with("l.");
    if looks_like_continuation && message.chars().last().is_some_and(char::is_alphanumeric) {
        message.push_str(continuation);
    }
    message
}

fn diagnostic_path(raw: &str, root: &Path, working_directory: &Path) -> Option<String> {
    let raw_path = PathBuf::from(raw);
    let candidate = if raw_path.is_absolute() {
        raw_path.clone()
    } else {
        working_directory.join(&raw_path)
    };
    let canonical_root = root.canonicalize().unwrap_or_else(|_| root.to_path_buf());
    let canonical_candidate = candidate.canonicalize().unwrap_or(candidate);
    if let Ok(relative) = canonical_candidate.strip_prefix(&canonical_root) {
        return Some(relative.to_string_lossy().replace('\\', "/"));
    }
    Some(raw_path.to_string_lossy().replace('\\', "/"))
}

pub fn missing_package(log: &str) -> Option<String> {
    let expression =
        Regex::new(r"(?m)! LaTeX Error: File `([^']+\.(?:sty|cls))' not found\.").unwrap();
    expression
        .captures(log)
        .and_then(|value| value.get(1))
        .map(|value| value.as_str().to_owned())
}

fn build_cache(root: &Path, entry: &Path) -> CoreResult<PathBuf> {
    build_cache_in(&paths::cache_directory()?.join("Builds"), root, entry)
}

fn build_cache_in(base: &Path, root: &Path, entry: &Path) -> CoreResult<PathBuf> {
    let key = hex::encode(Sha256::digest(
        format!("{}|{}", root.display(), entry.display()).as_bytes(),
    ));
    let path = base.join(key);
    fs::create_dir_all(&path)?;
    Ok(path)
}

fn build_arguments(cache: &Path, entry: &Path, request: &BuildRequest) -> Vec<String> {
    let mut arguments = Vec::new();
    if request.tool == BuildTool::Latexmk {
        arguments.push(request.engine.latexmk_flag().to_owned());
    }
    arguments.extend([
        "-interaction=nonstopmode".into(),
        "-halt-on-error".into(),
        "-file-line-error".into(),
        "-synctex=1".into(),
        format!("-output-directory={}", cache.to_string_lossy()),
        entry.file_name().unwrap().to_string_lossy().into_owned(),
    ]);
    arguments
}

fn atomic_copy(source: &Path, destination: &Path) -> CoreResult<()> {
    let parent = destination
        .parent()
        .ok_or_else(|| CoreError::UnsafePath(destination.to_path_buf()))?;
    let temporary = parent.join(format!(".lightex-{}.pdf", uuid::Uuid::new_v4()));
    fs::copy(source, &temporary)?;
    if destination.exists() {
        fs::remove_file(destination)?;
    }
    fs::rename(temporary, destination)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_missing_package_once() {
        let log = "! LaTeX Error: File `tikz.sty' not found.";
        assert_eq!(missing_package(log).as_deref(), Some("tikz.sty"));
    }

    #[test]
    fn normalizes_latex_file_line_paths_for_inline_diagnostics() {
        let temporary = tempfile::tempdir_in(std::env::current_dir().unwrap()).unwrap();
        let root = temporary.path().canonicalize().unwrap();
        fs::write(root.join("main.tex"), "\\bagin{equation}\n").unwrap();
        let log = "./main.tex:1: Undefined control sequence.\nl.1 \\bagin\n./main.tex:1:  ==> Fatal error occurred!";

        let diagnostics = parse_diagnostics(log, &root);

        assert_eq!(diagnostics.len(), 1);
        assert_eq!(
            diagnostics[0].primary.relative_path.as_deref(),
            Some("main.tex")
        );
        assert_eq!(diagnostics[0].primary.line, Some(1));
        assert_eq!(
            diagnostics[0].primary.message,
            "Undefined control sequence."
        );
        assert_eq!(diagnostics[0].related.len(), 1);
    }

    #[test]
    fn resolves_diagnostics_from_a_nested_main_document_directory() {
        let temporary = tempfile::tempdir_in(std::env::current_dir().unwrap()).unwrap();
        let root = temporary.path().canonicalize().unwrap();
        let nested = root.join("notes");
        fs::create_dir(&nested).unwrap();
        fs::write(nested.join("main.tex"), "\\bagin{equation}\n").unwrap();

        let diagnostics =
            parse_diagnostics_from("./main.tex:1: Undefined control sequence.", &root, &nested);

        assert_eq!(
            diagnostics[0].primary.relative_path.as_deref(),
            Some("notes/main.tex")
        );
    }

    #[test]
    fn maps_wrapped_package_errors_from_project_style_files() {
        let temporary = tempfile::tempdir_in(std::env::current_dir().unwrap()).unwrap();
        let root = temporary.path().canonicalize().unwrap();
        fs::create_dir(root.join("styles")).unwrap();
        fs::write(
            root.join("styles/mathnotes.sty"),
            "\\PackageError{mathnotes}{}{}\n",
        )
        .unwrap();
        let log = "./styles/mathnotes.sty:7: Package mathnotes Error: This template requires XeLaT\neX.\n";

        let diagnostics = parse_diagnostics(log, &root);

        assert_eq!(diagnostics.len(), 1);
        assert_eq!(
            diagnostics[0].primary.relative_path.as_deref(),
            Some("styles/mathnotes.sty")
        );
        assert_eq!(diagnostics[0].primary.line, Some(7));
        assert_eq!(
            diagnostics[0].primary.message,
            "Package mathnotes Error: This template requires XeLaTeX."
        );
    }

    #[test]
    fn keeps_the_previous_tex_error_when_latexmk_only_reports_its_cached_failure() {
        let temporary = tempfile::tempdir_in(std::env::current_dir().unwrap()).unwrap();
        let root = temporary.path().canonicalize().unwrap();
        fs::write(root.join("main.tex"), "\\bфgin{proof}\n").unwrap();
        let latexmk_log = "Latexmk: Nothing to do for 'main.tex'.\n\
Collected error summary (may duplicate other messages):\n\
  xelatex: gave an error in previous invocation of latexmk.";
        let compiler_log = "./main.tex:29: Undefined control sequence.\n\
l.29 \\bфgin{proof}";

        let (diagnostics, used_fallback) =
            diagnostics_with_compiler_log_fallback(latexmk_log, Some(compiler_log), &root, &root);

        assert!(used_fallback);
        assert_eq!(diagnostics.len(), 1);
        assert_eq!(
            diagnostics[0].primary.relative_path.as_deref(),
            Some("main.tex")
        );
        assert_eq!(diagnostics[0].primary.line, Some(29));
        assert_eq!(
            diagnostics[0].primary.message,
            "Undefined control sequence."
        );
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn runs_all_engines_and_latexmk_with_an_absolute_executable() {
        let temporary = tempfile::tempdir_in(std::env::current_dir().unwrap()).unwrap();
        let root = temporary.path().canonicalize().unwrap();
        let entry = root.join("main.tex");
        fs::write(
            &entry,
            "\\documentclass{article}\\begin{document}Test\\end{document}",
        )
        .unwrap();
        let cache_base = root.join("cache");
        let cache = build_cache_in(&cache_base, &root, &entry).unwrap();
        fs::write(cache.join("main.pdf"), "%PDF-1.4\n").unwrap();
        let compiler = PathBuf::from("/usr/bin/true");

        for engine in [
            crate::LatexEngine::PdfLaTex,
            crate::LatexEngine::XeLaTex,
            crate::LatexEngine::LuaLaTex,
        ] {
            let result = run_cancellable_in(
                &root,
                &BuildRequest {
                    project_id: crate::ProjectId("integration".into()),
                    entry_file: "main.tex".into(),
                    engine,
                    tool: BuildTool::DirectCompiler,
                    executable_path: compiler.to_string_lossy().into_owned(),
                    search_directories: Vec::new(),
                },
                Arc::new(AtomicBool::new(false)),
                Some(&cache_base),
            )
            .await
            .unwrap();
            assert!(result.succeeded);
            assert!(Path::new(result.preview_pdf_path.as_deref().unwrap()).is_file());
            assert!(root.join("main.pdf").is_file());
        }

        let latexmk = run_cancellable_in(
            &root,
            &BuildRequest {
                project_id: crate::ProjectId("integration".into()),
                entry_file: "main.tex".into(),
                engine: crate::LatexEngine::XeLaTex,
                tool: BuildTool::Latexmk,
                executable_path: compiler.to_string_lossy().into_owned(),
                search_directories: Vec::new(),
            },
            Arc::new(AtomicBool::new(false)),
            Some(&cache_base),
        )
        .await
        .unwrap();
        assert!(latexmk.succeeded);
        let latexmk_arguments = build_arguments(
            &cache,
            &entry,
            &BuildRequest {
                project_id: crate::ProjectId("integration".into()),
                entry_file: "main.tex".into(),
                engine: crate::LatexEngine::XeLaTex,
                tool: BuildTool::Latexmk,
                executable_path: compiler.to_string_lossy().into_owned(),
                search_directories: Vec::new(),
            },
        );
        assert_eq!(
            latexmk_arguments.first().map(String::as_str),
            Some("-xelatex")
        );
        assert!(
            latexmk_arguments
                .iter()
                .any(|argument| argument == "-synctex=1")
        );
    }
}
