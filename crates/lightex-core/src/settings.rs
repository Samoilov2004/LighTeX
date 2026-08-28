use std::{fs, io::Write, path::PathBuf};

use crate::{AppConfigV1, CoreResult, ProjectSessionV1, ProjectSessionV2, paths};

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

pub fn load_session(project_path: &str) -> CoreResult<Option<ProjectSessionV2>> {
    let path = session_path(project_path)?;
    if !path.exists() {
        return Ok(None);
    }
    decode_session(&fs::read(path)?)
}

pub fn save_session(session: &ProjectSessionV2) -> CoreResult<()> {
    write_json(session_path(&session.project_path)?, session)
}

fn decode_session(bytes: &[u8]) -> CoreResult<Option<ProjectSessionV2>> {
    let value: serde_json::Value = serde_json::from_slice(bytes)?;
    match value
        .get("schemaVersion")
        .and_then(serde_json::Value::as_u64)
    {
        Some(1) => Ok(Some(
            serde_json::from_value::<ProjectSessionV1>(value)?.into(),
        )),
        Some(2) => Ok(Some(serde_json::from_value::<ProjectSessionV2>(value)?)),
        _ => Ok(None),
    }
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
        assert!(config.recent_projects.is_empty());
        assert!(!config.open_last_project);
        assert!(config.autosave);
        assert!(config.automatic_builds);
        assert_eq!(config.automatic_build_delay_seconds, 5);
    }

    #[test]
    fn migrates_project_session_v1_to_v2_outline_defaults() {
        let session = decode_session(
            br#"{
            "schemaVersion": 1,
            "projectPath": "/tmp/CoreMath",
            "mainDocument": "main.tex",
            "openDocuments": ["main.tex"],
            "selectedDocument": "main.tex"
        }"#,
        )
        .expect("valid session")
        .expect("known schema");

        assert_eq!(session.schema_version, 2);
        assert!(session.outline_expanded);
        assert_eq!(session.outline_height, 180);
        assert_eq!(session.selected_document.as_deref(), Some("main.tex"));
    }

    #[test]
    fn preserves_project_session_v2_outline_state() {
        let session = decode_session(
            br#"{
            "schemaVersion": 2,
            "projectPath": "/tmp/CoreMath",
            "mainDocument": null,
            "openDocuments": [],
            "selectedDocument": null,
            "outlineExpanded": false,
            "outlineHeight": 224
        }"#,
        )
        .expect("valid session")
        .expect("known schema");

        assert!(!session.outline_expanded);
        assert_eq!(session.outline_height, 224);
    }
}
