use std::path::{Component, Path, PathBuf};

use directories::ProjectDirs;

use crate::{CoreError, CoreResult};

pub fn canonical_directory(path: impl AsRef<Path>) -> CoreResult<PathBuf> {
    let path = path.as_ref();
    let canonical = path
        .canonicalize()
        .map_err(|_| CoreError::InvalidProject(path.to_path_buf()))?;
    if !canonical.is_dir() {
        return Err(CoreError::InvalidProject(canonical));
    }
    Ok(canonical)
}

pub fn safe_relative_path(root: &Path, relative: impl AsRef<Path>) -> CoreResult<PathBuf> {
    let relative = relative.as_ref();
    if relative.is_absolute()
        || relative.components().any(|component| {
            matches!(
                component,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return Err(CoreError::UnsafePath(relative.to_path_buf()));
    }
    let candidate = root.join(relative);
    let existing_parent = if candidate.exists() {
        candidate.as_path()
    } else {
        candidate.parent().unwrap_or(root)
    };
    let canonical_parent = existing_parent.canonicalize()?;
    if canonical_parent != root && !canonical_parent.starts_with(root) {
        return Err(CoreError::UnsafePath(candidate));
    }
    Ok(candidate)
}

pub fn relative_string(root: &Path, path: &Path) -> Option<String> {
    path.strip_prefix(root)
        .ok()
        .map(|value| value.to_string_lossy().replace('\\', "/"))
}

pub fn project_dirs() -> CoreResult<ProjectDirs> {
    ProjectDirs::from("app", "LighTeX", "LighTeX").ok_or_else(|| {
        CoreError::Message("The platform application directories are unavailable.".into())
    })
}

pub fn config_directory() -> CoreResult<PathBuf> {
    let dirs = project_dirs()?;
    let path = if cfg!(target_os = "macos") {
        dirs.data_dir().join("v2")
    } else {
        dirs.config_dir().to_path_buf()
    };
    std::fs::create_dir_all(&path)?;
    Ok(path)
}

pub fn data_directory() -> CoreResult<PathBuf> {
    let dirs = project_dirs()?;
    let path = if cfg!(target_os = "macos") {
        dirs.data_dir().join("v2")
    } else {
        dirs.data_dir().to_path_buf()
    };
    std::fs::create_dir_all(&path)?;
    Ok(path)
}

pub fn cache_directory() -> CoreResult<PathBuf> {
    let path = project_dirs()?.cache_dir().join("v2");
    std::fs::create_dir_all(&path)?;
    Ok(path)
}
