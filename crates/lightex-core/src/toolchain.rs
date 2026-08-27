use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use crate::{
    CoreError, CoreResult, LatexEngine, ManagedRuntimeRecordV2, ToolExecutable, ToolchainStatus,
};

pub fn detect_system() -> ToolchainStatus {
    let mut directories: BTreeSet<PathBuf> = env::var_os("PATH")
        .map(|value| env::split_paths(&value).collect())
        .unwrap_or_default();
    for known in known_directories() {
        directories.insert(known);
    }
    let directories: Vec<PathBuf> = directories.into_iter().collect();
    let mut engines = BTreeMap::new();
    for engine in [
        LatexEngine::PdfLaTex,
        LatexEngine::XeLaTex,
        LatexEngine::LuaLaTex,
    ] {
        if let Some(tool) = detect_tool(engine.executable(), &directories) {
            engines.insert(engine.executable().to_owned(), tool);
        }
    }
    ToolchainStatus {
        engines,
        latexmk: detect_tool("latexmk", &directories),
        synctex: detect_tool("synctex", &directories),
        tlmgr: detect_tool("tlmgr", &directories),
    }
}

pub fn from_runtime(record: &ManagedRuntimeRecordV2) -> CoreResult<ToolchainStatus> {
    let root = PathBuf::from(&record.root_path).canonicalize()?;
    let tool = |name: &str| -> CoreResult<Option<ToolExecutable>> {
        let Some(relative) = record.tools.get(name) else {
            return Ok(None);
        };
        let candidate = root.join(relative);
        let canonical = candidate.canonicalize()?;
        if !canonical.starts_with(&root) || !is_executable(&canonical) {
            return Err(CoreError::MissingTool(name.to_owned()));
        }
        Ok(Some(tool_status(&canonical)))
    };
    let mut engines = BTreeMap::new();
    for name in ["pdflatex", "xelatex", "lualatex"] {
        if let Some(status) = tool(name)? {
            engines.insert(name.to_owned(), status);
        }
    }
    Ok(ToolchainStatus {
        engines,
        latexmk: tool("latexmk")?,
        synctex: tool("synctex")?,
        tlmgr: tool("tlmgr")?,
    })
}

pub fn chosen_executable(
    status: &ToolchainStatus,
    engine: LatexEngine,
    tool: crate::BuildTool,
) -> CoreResult<PathBuf> {
    let selected = match tool {
        crate::BuildTool::Latexmk => status.latexmk.as_ref(),
        crate::BuildTool::DirectCompiler => status.engines.get(engine.executable()),
    }
    .ok_or_else(|| {
        CoreError::MissingTool(match tool {
            crate::BuildTool::Latexmk => "latexmk".into(),
            crate::BuildTool::DirectCompiler => engine.executable().into(),
        })
    })?;
    Ok(PathBuf::from(&selected.path))
}

fn detect_tool(name: &str, directories: &[PathBuf]) -> Option<ToolExecutable> {
    directories
        .iter()
        .map(|directory| directory.join(name))
        .find(|path| is_executable(path))
        .map(|path| tool_status(&path))
}

fn tool_status(path: &Path) -> ToolExecutable {
    let arguments: &[&str] = if path.file_name().is_some_and(|name| name == "latexmk") {
        &["-v"]
    } else {
        &["--version"]
    };
    let version = Command::new(path)
        .args(arguments)
        .stdin(Stdio::null())
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .and_then(|text| text.lines().next().map(str::to_owned));
    ToolExecutable {
        path: path.to_string_lossy().into_owned(),
        version,
    }
}

fn is_executable(path: &Path) -> bool {
    if !path.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        path.metadata()
            .is_ok_and(|metadata| metadata.permissions().mode() & 0o111 != 0)
    }
    #[cfg(not(unix))]
    true
}

fn known_directories() -> Vec<PathBuf> {
    let mut values = vec![
        PathBuf::from("/usr/bin"),
        PathBuf::from("/usr/local/bin"),
        PathBuf::from("/bin"),
    ];
    if cfg!(target_os = "macos") {
        values.extend([
            PathBuf::from("/Library/TeX/texbin"),
            PathBuf::from("/opt/homebrew/bin"),
        ]);
    } else if let Ok(entries) = std::fs::read_dir("/usr/local/texlive") {
        for entry in entries.flatten() {
            values.push(entry.path().join("bin/x86_64-linux"));
        }
    }
    values
}
