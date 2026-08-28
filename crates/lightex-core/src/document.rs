use std::{fs, io::Write, path::Path, time::UNIX_EPOCH};

use sha2::{Digest, Sha256};

use crate::{CoreError, CoreResult, DocumentRevision, DocumentSnapshot, SaveOutcome};

pub fn read(path: &Path, relative_path: String) -> CoreResult<DocumentSnapshot> {
    let bytes = fs::read(path)?;
    let text =
        String::from_utf8(bytes.clone()).map_err(|_| CoreError::InvalidUtf8(path.to_path_buf()))?;
    Ok(DocumentSnapshot {
        relative_path,
        text,
        revision: revision(path, &bytes)?,
    })
}

pub fn current_revision(path: &Path) -> CoreResult<Option<DocumentRevision>> {
    if !path.exists() {
        return Ok(None);
    }
    let bytes = fs::read(path)?;
    Ok(Some(revision(path, &bytes)?))
}

pub fn save(
    path: &Path,
    text: &str,
    base_revision: Option<&DocumentRevision>,
    overwrite_conflict: bool,
) -> CoreResult<SaveOutcome> {
    if !path.exists() {
        return Ok(SaveOutcome::Missing);
    }
    let disk_revision = current_revision(path)?;
    if !overwrite_conflict && base_revision.is_some() && disk_revision.as_ref() != base_revision {
        return Ok(SaveOutcome::Conflict { disk_revision });
    }
    let parent = path
        .parent()
        .ok_or_else(|| CoreError::UnsafePath(path.to_path_buf()))?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(text.as_bytes())?;
    temporary.as_file().sync_all()?;
    let permissions = fs::metadata(path)?.permissions();
    temporary.as_file().set_permissions(permissions)?;
    temporary
        .persist(path)
        .map_err(|error| CoreError::Io(error.error))?;
    let bytes = text.as_bytes();
    Ok(SaveOutcome::Saved {
        revision: revision(path, bytes)?,
    })
}

pub fn write_copy(path: &Path, text: &str) -> CoreResult<DocumentRevision> {
    if path.exists() {
        return Err(CoreError::DestinationExists(path.to_path_buf()));
    }
    let parent = path
        .parent()
        .ok_or_else(|| CoreError::UnsafePath(path.to_path_buf()))?;
    fs::create_dir_all(parent)?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(text.as_bytes())?;
    temporary.as_file().sync_all()?;
    temporary
        .persist(path)
        .map_err(|error| CoreError::Io(error.error))?;
    revision(path, text.as_bytes())
}

pub fn revision(path: &Path, bytes: &[u8]) -> CoreResult<DocumentRevision> {
    let metadata = fs::metadata(path)?;
    let modification_unix_ms = metadata
        .modified()
        .ok()
        .and_then(|date| date.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64);
    #[cfg(unix)]
    let file_identifier = {
        use std::os::unix::fs::MetadataExt;
        Some(format!("{}:{}", metadata.dev(), metadata.ino()))
    };
    #[cfg(not(unix))]
    let file_identifier = None;
    Ok(DocumentRevision {
        modification_unix_ms,
        file_size: metadata.len(),
        file_identifier,
        content_hash: hex::encode(Sha256::digest(bytes)),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_conflicting_save() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("main.tex");
        fs::write(&path, "old").unwrap();
        let snapshot = read(&path, "main.tex".into()).unwrap();
        fs::write(&path, "external").unwrap();
        let result = save(&path, "mine", Some(&snapshot.revision), false).unwrap();
        assert!(matches!(result, SaveOutcome::Conflict { .. }));
        assert_eq!(fs::read_to_string(path).unwrap(), "external");
    }
}
