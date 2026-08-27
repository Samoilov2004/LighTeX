use std::{
    collections::BTreeSet,
    fs,
    io::{Read, Write},
    path::Path,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Instant,
};

use base64::{Engine as _, engine::general_purpose::STANDARD};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use futures_util::StreamExt;
use sha2::{Digest, Sha256};
use tokio::{fs::File, io::AsyncWriteExt, process::Command};

use crate::{
    CoreError, CoreResult, InstalledRuntime, ManagedRuntimeRecordV2, RuntimeArchitecture,
    RuntimeAsset, RuntimeEnvironment, RuntimeInstallEvent, RuntimeManifestV2, RuntimePlatform,
    RuntimeVariant, StorageUsage, paths, toolchain,
};

pub const MANIFEST_URL: &str = "https://github.com/Samoilov2004/LighTeX/releases/download/runtime-v2-latest/runtime-manifest.json";
pub const SIGNATURE_URL: &str = "https://github.com/Samoilov2004/LighTeX/releases/download/runtime-v2-latest/runtime-manifest.sig";
pub const PUBLIC_KEY_BASE64: &str = "ypmAAFFVK3x/OdzoPWUQPMOiq9XPc6tAfRlOHVVsJJ0=";

pub async fn fetch_manifest() -> CoreResult<RuntimeManifestV2> {
    let client = reqwest::Client::new();
    let (manifest, signature) = tokio::try_join!(
        async {
            Ok::<_, reqwest::Error>(
                client
                    .get(MANIFEST_URL)
                    .send()
                    .await?
                    .error_for_status()?
                    .bytes()
                    .await?,
            )
        },
        async {
            Ok::<_, reqwest::Error>(
                client
                    .get(SIGNATURE_URL)
                    .send()
                    .await?
                    .error_for_status()?
                    .bytes()
                    .await?,
            )
        },
    )?;
    verify_manifest(&manifest, &signature, PUBLIC_KEY_BASE64)?;
    let decoded: RuntimeManifestV2 = serde_json::from_slice(&manifest)?;
    validate_manifest(&decoded)?;
    Ok(decoded)
}

pub fn verify_manifest(data: &[u8], signature: &[u8], public_key_base64: &str) -> CoreResult<()> {
    let key_bytes = STANDARD
        .decode(public_key_base64)
        .map_err(|_| CoreError::InvalidManifestSignature)?;
    let key_array: [u8; 32] = key_bytes
        .try_into()
        .map_err(|_| CoreError::InvalidManifestSignature)?;
    let key =
        VerifyingKey::from_bytes(&key_array).map_err(|_| CoreError::InvalidManifestSignature)?;
    let signature =
        Signature::from_slice(signature).map_err(|_| CoreError::InvalidManifestSignature)?;
    key.verify(data, &signature)
        .map_err(|_| CoreError::InvalidManifestSignature)
}

pub fn validate_manifest(manifest: &RuntimeManifestV2) -> CoreResult<()> {
    if manifest.schema_version != 2
        || manifest.runtime_version.is_empty()
        || manifest.assets.is_empty()
    {
        return Err(CoreError::InvalidManifest(
            "unsupported schema or empty catalog".into(),
        ));
    }
    let hash = regex::Regex::new(r"^[a-fA-F0-9]{64}$").unwrap();
    let mut combinations = BTreeSet::new();
    for asset in &manifest.assets {
        let parts_size: u64 = archive_parts(asset).iter().map(|(_, size)| *size).sum();
        if asset.compressed_size == 0
            || asset.installed_size == 0
            || parts_size != asset.compressed_size
            || !hash.is_match(&asset.sha256)
            || asset.tools.values().any(|path| !safe_tool_relative(path))
        {
            return Err(CoreError::InvalidManifest("invalid runtime asset".into()));
        }
        if !combinations.insert((
            format!("{:?}", asset.variant),
            format!("{:?}", asset.platform),
            format!("{:?}", asset.architecture),
        )) {
            return Err(CoreError::InvalidManifest("duplicate runtime asset".into()));
        }
    }
    Ok(())
}

pub fn environment() -> RuntimeEnvironment {
    RuntimeEnvironment {
        platform: RuntimePlatform::current(),
        architecture: RuntimeArchitecture::current(),
    }
}

pub fn selected_asset(
    manifest: &RuntimeManifestV2,
    variant: RuntimeVariant,
) -> CoreResult<RuntimeAsset> {
    manifest
        .assets
        .iter()
        .find(|asset| {
            asset.variant == variant
                && asset.platform == RuntimePlatform::current()
                && asset.architecture == RuntimeArchitecture::current()
        })
        .cloned()
        .ok_or_else(|| CoreError::InvalidManifest("no runtime for this platform".into()))
}

pub async fn install(
    manifest: &RuntimeManifestV2,
    asset: &RuntimeAsset,
    cancel: Arc<AtomicBool>,
    progress: impl Fn(RuntimeInstallEvent) + Send + Sync,
) -> CoreResult<ManagedRuntimeRecordV2> {
    progress(RuntimeInstallEvent::Checking);
    let base = paths::data_directory()?.join("Runtimes");
    let downloads = base.join("Downloads");
    fs::create_dir_all(&downloads)?;
    let archive = downloads.join(format!(
        "{}-{:?}-{:?}.zip",
        manifest.runtime_version, asset.platform, asset.architecture
    ));
    let mut destination = File::create(&archive).await?;
    let client = reqwest::Client::new();
    let started = Instant::now();
    let mut received = 0_u64;
    for (url, _) in archive_parts(asset) {
        let response = client.get(url).send().await?.error_for_status()?;
        let mut stream = response.bytes_stream();
        while let Some(chunk) = stream.next().await {
            if cancel.load(Ordering::Relaxed) {
                let _ = tokio::fs::remove_file(&archive).await;
                progress(RuntimeInstallEvent::Cancelled);
                return Err(CoreError::Cancelled);
            }
            let chunk = chunk?;
            destination.write_all(&chunk).await?;
            received += chunk.len() as u64;
            progress(RuntimeInstallEvent::Downloading {
                received,
                total: asset.compressed_size,
                bytes_per_second: received as f64 / started.elapsed().as_secs_f64().max(0.1),
            });
        }
    }
    destination.flush().await?;
    drop(destination);
    progress(RuntimeInstallEvent::Verifying);
    if sha256_file(&archive)? != asset.sha256.to_lowercase() {
        let _ = fs::remove_file(&archive);
        return Err(CoreError::InvalidArchiveHash);
    }
    if cancel.load(Ordering::Relaxed) {
        let _ = fs::remove_file(&archive);
        progress(RuntimeInstallEvent::Cancelled);
        return Err(CoreError::Cancelled);
    }
    progress(RuntimeInstallEvent::Installing);
    let parent = base
        .join(&manifest.runtime_version)
        .join(format!("{:?}", asset.variant).to_lowercase())
        .join(match asset.platform {
            RuntimePlatform::MacOs => "macos",
            RuntimePlatform::Linux => "linux",
        });
    fs::create_dir_all(&parent)?;
    let architecture = match asset.architecture {
        RuntimeArchitecture::Arm64 => "arm64",
        RuntimeArchitecture::X86_64 => "x86_64",
    };
    let target = parent.join(architecture);
    let staging = base.join(format!(".staging-{}", uuid::Uuid::new_v4()));
    let backup = base.join(format!(".backup-{}", uuid::Uuid::new_v4()));
    fs::create_dir_all(&staging)?;
    if let Err(error) = extract_zip(&archive, &staging) {
        let _ = fs::remove_dir_all(&staging);
        return Err(error);
    }
    let staged = ManagedRuntimeRecordV2 {
        schema_version: 2,
        runtime_version: manifest.runtime_version.clone(),
        tex_live_year: manifest.tex_live_year,
        variant: asset.variant,
        platform: asset.platform,
        architecture: asset.architecture,
        root_path: staging.to_string_lossy().into_owned(),
        tools: asset.tools.clone(),
    };
    let status = match toolchain::from_runtime(&staged) {
        Ok(status) => status,
        Err(error) => {
            let _ = fs::remove_dir_all(&staging);
            return Err(error);
        }
    };
    if status.engines.len() != 3
        || status.latexmk.is_none()
        || status.synctex.is_none()
        || status.tlmgr.is_none()
    {
        let _ = fs::remove_dir_all(&staging);
        return Err(CoreError::InvalidManifest(
            "runtime tools failed validation".into(),
        ));
    }
    let record = ManagedRuntimeRecordV2 {
        root_path: target.to_string_lossy().into_owned(),
        ..staged
    };
    fs::write(
        staging.join(".lightex-runtime.json"),
        serde_json::to_vec_pretty(&record)?,
    )?;
    if target.exists() {
        fs::rename(&target, &backup)?;
    }
    if let Err(error) = fs::rename(&staging, &target) {
        if backup.exists() {
            let _ = fs::rename(&backup, &target);
        }
        return Err(error.into());
    }
    if backup.exists() {
        let _ = fs::remove_dir_all(backup);
    }
    progress(RuntimeInstallEvent::Ready {
        record: record.clone(),
    });
    Ok(record)
}

pub fn scan_installed() -> CoreResult<Vec<ManagedRuntimeRecordV2>> {
    let root = paths::data_directory()?.join("Runtimes");
    if !root.exists() {
        return Ok(Vec::new());
    }
    let mut records = Vec::new();
    for entry in walkdir::WalkDir::new(root)
        .into_iter()
        .filter_map(Result::ok)
    {
        if entry.file_name() != ".lightex-runtime.json" {
            continue;
        }
        if let Ok(data) = fs::read(entry.path())
            && let Ok(record) = serde_json::from_slice::<ManagedRuntimeRecordV2>(&data)
            && toolchain::from_runtime(&record).is_ok()
        {
            records.push(record);
        }
    }
    Ok(records)
}

pub fn inventory(active_record_path: Option<&str>) -> CoreResult<Vec<InstalledRuntime>> {
    let mut records = scan_installed()?
        .into_iter()
        .map(|record| {
            let manifest = Path::new(&record.root_path).join(".lightex-runtime.json");
            let active = active_record_path.is_some_and(|value| Path::new(value) == manifest);
            let installed_size = directory_size(Path::new(&record.root_path));
            InstalledRuntime {
                record,
                installed_size,
                active,
            }
        })
        .collect::<Vec<_>>();
    records.sort_by(|left, right| {
        right
            .record
            .runtime_version
            .cmp(&left.record.runtime_version)
    });
    Ok(records)
}

pub fn remove_inactive(
    record: &ManagedRuntimeRecordV2,
    active_record_path: Option<&str>,
) -> CoreResult<()> {
    let runtimes = paths::data_directory()?.join("Runtimes").canonicalize()?;
    let root = Path::new(&record.root_path).canonicalize()?;
    if root == runtimes || !root.starts_with(&runtimes) {
        return Err(CoreError::UnsafePath(root));
    }
    let manifest = root.join(".lightex-runtime.json");
    if active_record_path.is_some_and(|value| Path::new(value) == manifest) {
        return Err(CoreError::Message(
            "Choose another TeX provider before removing the active runtime.".into(),
        ));
    }
    let disk_record = runtime_record(&manifest)?;
    if disk_record != *record {
        return Err(CoreError::Message(
            "The runtime changed on disk. Refresh Settings and try again.".into(),
        ));
    }
    trash::delete(root).map_err(|error| CoreError::Message(error.to_string()))
}

pub fn storage_usage() -> CoreResult<StorageUsage> {
    let runtimes = paths::data_directory()?.join("Runtimes");
    let runtime_downloads = directory_size(&runtimes.join("Downloads"));
    let runtime_staging = fs::read_dir(&runtimes)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .filter(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            name.starts_with(".staging-") || name.starts_with(".backup-")
        })
        .map(|entry| directory_size(&entry.path()))
        .sum();
    let build_cache = directory_size(&paths::cache_directory()?.join("Builds"));
    Ok(StorageUsage {
        runtime_downloads,
        runtime_staging,
        build_cache,
    })
}

pub fn clear_storage(
    clear_downloads: bool,
    clear_staging: bool,
    clear_build_cache: bool,
) -> CoreResult<StorageUsage> {
    let before = storage_usage()?;
    let runtimes = paths::data_directory()?.join("Runtimes");
    if clear_downloads {
        remove_owned_directory(&runtimes.join("Downloads"))?;
    }
    if clear_staging && runtimes.is_dir() {
        for entry in fs::read_dir(&runtimes)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with(".staging-") || name.starts_with(".backup-") {
                remove_owned_directory(&entry.path())?;
            }
        }
    }
    if clear_build_cache {
        remove_owned_directory(&paths::cache_directory()?.join("Builds"))?;
    }
    let after = storage_usage()?;
    Ok(StorageUsage {
        runtime_downloads: before
            .runtime_downloads
            .saturating_sub(after.runtime_downloads),
        runtime_staging: before.runtime_staging.saturating_sub(after.runtime_staging),
        build_cache: before.build_cache.saturating_sub(after.build_cache),
    })
}

pub async fn install_missing_package(
    record: &ManagedRuntimeRecordV2,
    missing_file: &str,
) -> CoreResult<String> {
    let status = toolchain::from_runtime(record)?;
    let tlmgr = status
        .tlmgr
        .ok_or_else(|| CoreError::MissingTool("tlmgr".into()))?;
    let search = Command::new(&tlmgr.path)
        .args([
            "search",
            "--global",
            "--file",
            &format!("/{}", missing_file.trim_start_matches('/')),
        ])
        .output()
        .await?;
    if !search.status.success() {
        return Err(CoreError::Message(
            String::from_utf8_lossy(&search.stderr).into_owned(),
        ));
    }
    let package = String::from_utf8_lossy(&search.stdout)
        .lines()
        .map(str::trim)
        .find(|line| line.ends_with(':') && !line.starts_with("tlmgr"))
        .map(|line| line.trim_end_matches(':').to_owned())
        .ok_or_else(|| {
            CoreError::Message(format!("No TeX Live package provides {missing_file}."))
        })?;
    let install = Command::new(&tlmgr.path)
        .args(["install", &package])
        .output()
        .await?;
    let mut output = String::from_utf8_lossy(&install.stdout).into_owned();
    output.push_str(&String::from_utf8_lossy(&install.stderr));
    if !install.status.success() {
        return Err(CoreError::Message(output));
    }
    Ok(output)
}

fn archive_parts(asset: &RuntimeAsset) -> Vec<(&str, u64)> {
    if let Some(parts) = asset
        .download_parts
        .as_ref()
        .filter(|parts| !parts.is_empty())
    {
        return parts
            .iter()
            .map(|part| (part.download_url.as_str(), part.compressed_size))
            .collect();
    }
    asset
        .download_url
        .as_deref()
        .map(|url| vec![(url, asset.compressed_size)])
        .unwrap_or_default()
}

fn sha256_file(path: &Path) -> CoreResult<String> {
    let mut file = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0_u8; 1024 * 1024];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    Ok(hex::encode(hasher.finalize()))
}

fn extract_zip(archive: &Path, destination: &Path) -> CoreResult<()> {
    let mut zip = zip::ZipArchive::new(fs::File::open(archive)?)?;
    for index in 0..zip.len() {
        let mut entry = zip.by_index(index)?;
        let Some(enclosed) = entry.enclosed_name() else {
            return Err(CoreError::InvalidManifest("unsafe archive path".into()));
        };
        let output = destination.join(enclosed);
        if entry.is_dir() {
            fs::create_dir_all(&output)?;
            continue;
        }
        if let Some(parent) = output.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut file = fs::File::create(&output)?;
        std::io::copy(&mut entry, &mut file)?;
        file.flush()?;
        #[cfg(unix)]
        if let Some(mode) = entry.unix_mode() {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&output, fs::Permissions::from_mode(mode))?;
        }
    }
    Ok(())
}

fn safe_tool_relative(path: &str) -> bool {
    let value = Path::new(path);
    !value.is_absolute()
        && !value
            .components()
            .any(|component| matches!(component, std::path::Component::ParentDir))
}

fn directory_size(path: &Path) -> u64 {
    if !path.exists() {
        return 0;
    }
    walkdir::WalkDir::new(path)
        .follow_links(false)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .filter_map(|entry| entry.metadata().ok().map(|metadata| metadata.len()))
        .sum()
}

fn remove_owned_directory(path: &Path) -> CoreResult<()> {
    if !path.exists() {
        return Ok(());
    }
    if path.is_symlink() || !path.is_dir() {
        return Err(CoreError::UnsafePath(path.to_path_buf()));
    }
    fs::remove_dir_all(path)?;
    Ok(())
}

pub fn runtime_record(path: &Path) -> CoreResult<ManagedRuntimeRecordV2> {
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};

    #[test]
    fn verifies_manifest_signature_and_rejects_tampering() {
        let key = SigningKey::from_bytes(&[7_u8; 32]);
        let public = STANDARD.encode(key.verifying_key().as_bytes());
        let data = br#"{"schemaVersion":2}"#;
        let signature = key.sign(data).to_bytes();
        assert!(verify_manifest(data, &signature, &public).is_ok());
        assert!(verify_manifest(br#"{"schemaVersion":1}"#, &signature, &public).is_err());
    }

    #[test]
    fn rejects_unsafe_tool_path() {
        assert!(safe_tool_relative("runtime/bin/pdflatex"));
        assert!(!safe_tool_relative("../pdflatex"));
        assert!(!safe_tool_relative("/usr/bin/pdflatex"));
    }
}
