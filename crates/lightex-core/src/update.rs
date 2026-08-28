use serde::Deserialize;

use crate::{AppUpdateInfo, CoreError, CoreResult};

const LATEST_RELEASE_URL: &str =
    "https://api.github.com/repos/Samoilov2004/LighTeX/releases/latest";

pub async fn check(current_version: &str) -> CoreResult<AppUpdateInfo> {
    #[derive(Deserialize)]
    struct Release {
        tag_name: String,
        html_url: String,
    }
    let release = reqwest::Client::new()
        .get(LATEST_RELEASE_URL)
        .header(reqwest::header::USER_AGENT, "LighTex update checker")
        .send()
        .await?
        .error_for_status()?
        .json::<Release>()
        .await?;
    let latest_version = release.tag_name.trim_start_matches('v').to_owned();
    let latest = version_parts(&latest_version)?;
    let current = version_parts(current_version)?;
    Ok(AppUpdateInfo {
        current_version: current_version.to_owned(),
        latest_version,
        release_url: release.html_url,
        update_available: latest > current,
    })
}

fn version_parts(value: &str) -> CoreResult<(u64, u64, u64)> {
    let value = value.trim_start_matches('v');
    let clean = value
        .split_once('-')
        .map(|(stable, _)| stable)
        .unwrap_or(value);
    let mut parts = clean.split('.');
    let major = parts
        .next()
        .and_then(|value| value.parse().ok())
        .ok_or_else(|| CoreError::Message("Invalid release version.".into()))?;
    let minor = parts
        .next()
        .and_then(|value| value.parse().ok())
        .unwrap_or(0);
    let patch = parts
        .next()
        .and_then(|value| value.parse().ok())
        .unwrap_or(0);
    Ok((major, minor, patch))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compares_stable_versions_numerically() {
        assert!(version_parts("1.10.0").unwrap() > version_parts("1.9.9").unwrap());
        assert_eq!(version_parts("v1.1.1-beta.1").unwrap(), (1, 1, 1));
    }
}
