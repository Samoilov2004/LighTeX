use std::{fs, io::Write, path::PathBuf};

use crate::{AppConfigV1, CoreResult, ProjectSessionV1, paths};

pub fn config_path() -> CoreResult<PathBuf> {
    Ok(paths::config_directory()?.join("config.json"))
}

pub fn load_config() -> CoreResult<AppConfigV1> {
    let path = config_path()?;
    if !path.exists() {
        return Ok(AppConfigV1::default());
    }
    let value: AppConfigV1 = serde_json::from_slice(&fs::read(path)?)?;
    if value.schema_version != 1 {
        return Ok(AppConfigV1::default());
    }
    Ok(value)
}

pub fn save_config(config: &AppConfigV1) -> CoreResult<()> {
    write_json(config_path()?, config)
}

pub fn session_path(project_path: &str) -> CoreResult<PathBuf> {
    use sha2::{Digest, Sha256};
    let key = hex::encode(Sha256::digest(project_path.as_bytes()));
    let directory = paths::data_directory()?.join("Sessions");
    fs::create_dir_all(&directory)?;
    Ok(directory.join(format!("{key}.json")))
}

pub fn load_session(project_path: &str) -> CoreResult<Option<ProjectSessionV1>> {
    let path = session_path(project_path)?;
    if !path.exists() {
        return Ok(None);
    }
    let session: ProjectSessionV1 = serde_json::from_slice(&fs::read(path)?)?;
    Ok((session.schema_version == 1).then_some(session))
}

pub fn save_session(session: &ProjectSessionV1) -> CoreResult<()> {
    write_json(session_path(&session.project_path)?, session)
}

fn write_json(path: PathBuf, value: &impl serde::Serialize) -> CoreResult<()> {
    let parent = path.parent().expect("config path has a parent");
    fs::create_dir_all(parent)?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(&serde_json::to_vec_pretty(value)?)?;
    temporary.write_all(b"\n")?;
    temporary.as_file().sync_all()?;
    temporary
        .persist(path)
        .map_err(|error| crate::CoreError::Io(error.error))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_are_safe_and_calm() {
        let config = AppConfigV1::default();
        assert!(config.autosave);
        assert!(config.automatic_builds);
        assert_eq!(config.automatic_build_delay_seconds, 5);
    }
}
