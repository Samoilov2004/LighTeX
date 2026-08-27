use std::path::PathBuf;

use thiserror::Error;

pub type CoreResult<T> = Result<T, CoreError>;

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("The project folder does not exist or is not a directory: {0}")]
    InvalidProject(PathBuf),
    #[error("The requested path is outside the project: {0}")]
    UnsafePath(PathBuf),
    #[error("The project is not open: {0}")]
    UnknownProject(String),
    #[error("The file is not valid UTF-8: {0}")]
    InvalidUtf8(PathBuf),
    #[error("The document changed on disk. Review the external change before saving.")]
    DocumentConflict,
    #[error("A file or folder with that name already exists: {0}")]
    DestinationExists(PathBuf),
    #[error("No LaTeX engine is available. Configure System TeX or a LighTeX Runtime.")]
    MissingToolchain,
    #[error("The selected TeX tool is unavailable: {0}")]
    MissingTool(String),
    #[error("The runtime manifest is invalid: {0}")]
    InvalidManifest(String),
    #[error("The runtime manifest signature is invalid.")]
    InvalidManifestSignature,
    #[error("The downloaded runtime failed its SHA-256 check.")]
    InvalidArchiveHash,
    #[error("The operation was cancelled.")]
    Cancelled,
    #[error("{0}")]
    Message(String),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Regex(#[from] regex::Error),
    #[error(transparent)]
    Notify(#[from] notify::Error),
    #[error(transparent)]
    Request(#[from] reqwest::Error),
    #[error(transparent)]
    Zip(#[from] zip::result::ZipError),
}

impl From<CoreError> for String {
    fn from(value: CoreError) -> Self {
        value.to_string()
    }
}
