use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

use base64::{Engine as _, engine::general_purpose::STANDARD};
use lightex_core::{
    AppConfigV1, AppUpdateInfo, BuildRequest, BuildResult, DocumentRevision, DocumentSnapshot,
    InstalledRuntime, ManagedRuntimeRecordV2, OpenBuffer, OutlineItem, PersonalTemplateManifestV2,
    ProjectChangeEvent, ProjectCompletionIndex, ProjectEntry, ProjectHandle, ProjectId,
    ProjectMonitor, ProjectRegistry, ProjectSessionV2, ProjectVersionId, ProjectVersionSummary,
    ReplacePreview, RuntimeEnvironment, RuntimeInstallEvent, RuntimeManifestV2, RuntimeVariant,
    SaveOutcome, SearchQuery, SearchResult, StorageUsage, SyncTeXPdfTarget, SyncTeXSourceTarget,
    TemplateReview, ToolchainStatus, VersionChangeSummary, VersionFileDiff, VersionLineSummary,
    VersionPreviewEvent, VersionPreviewStatus, VersionRestoreOutcome, VersionSnapshotReview,
};
use tauri::{
    AppHandle, Emitter, Manager,
    menu::{MenuBuilder, MenuItemBuilder, SubmenuBuilder},
};

struct DesktopState {
    projects: ProjectRegistry,
    monitor: Mutex<Option<ProjectMonitor>>,
    build_cancel: Mutex<Option<Arc<AtomicBool>>>,
    runtime_cancel: Mutex<Option<Arc<AtomicBool>>>,
    version_cancel: Mutex<HashMap<String, Arc<AtomicBool>>>,
    version_lock: Arc<Mutex<()>>,
}

impl Default for DesktopState {
    fn default() -> Self {
        Self {
            projects: ProjectRegistry::default(),
            monitor: Mutex::new(None),
            build_cancel: Mutex::new(None),
            runtime_cancel: Mutex::new(None),
            version_cancel: Mutex::new(HashMap::new()),
            version_lock: Arc::new(Mutex::new(())),
        }
    }
}

#[tauri::command]
fn load_config() -> Result<AppConfigV1, String> {
    lightex_core::settings::load_config().map_err(Into::into)
}

#[tauri::command]
fn save_config(config: AppConfigV1) -> Result<(), String> {
    lightex_core::settings::save_config(&config).map_err(Into::into)
}

#[tauri::command]
fn load_session(project_path: String) -> Result<Option<ProjectSessionV2>, String> {
    lightex_core::settings::load_session(&project_path).map_err(Into::into)
}

#[tauri::command]
fn save_session(session: ProjectSessionV2) -> Result<(), String> {
    lightex_core::settings::save_session(&session).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn open_project(
    path: String,
    state: tauri::State<'_, DesktopState>,
    app: AppHandle,
) -> Result<ProjectHandle, String> {
    lightex_core::version::recover_pending_restore(Path::new(&path)).map_err(String::from)?;
    let handle = state.projects.open(&path).map_err(String::from)?;
    let project_id = handle.id.clone();
    let root = state.projects.root(&project_id).map_err(String::from)?;
    let monitor = start_project_monitor(&root, app)?;
    *state.monitor.lock().expect("monitor lock poisoned") = Some(monitor);
    Ok(handle)
}

fn start_project_monitor(root: &Path, app: AppHandle) -> Result<ProjectMonitor, String> {
    ProjectMonitor::start(root, move |change: ProjectChangeEvent| {
        let _ = app.emit("project://changed", change);
    })
    .map_err(String::from)
}

#[tauri::command(rename_all = "camelCase")]
fn close_project(project_id: ProjectId, state: tauri::State<'_, DesktopState>) {
    *state.monitor.lock().expect("monitor lock poisoned") = None;
    for cancel in state
        .version_cancel
        .lock()
        .expect("version cancel lock poisoned")
        .drain()
        .map(|(_, cancel)| cancel)
    {
        cancel.store(true, Ordering::Relaxed);
    }
    state.projects.close(&project_id);
}

#[tauri::command(rename_all = "camelCase")]
fn create_project(parent_path: String, name: String) -> Result<String, String> {
    lightex_core::project::create_project(Path::new(&parent_path), &name)
        .map(|path| path.to_string_lossy().into_owned())
        .map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn create_project_from_template(
    parent_path: String,
    name: String,
    template: String,
    app: AppHandle,
) -> Result<String, String> {
    let templates_root = bundled_templates_root(&app)?;
    lightex_core::project::create_project_from_template(
        Path::new(&parent_path),
        &name,
        &templates_root,
        &template,
    )
    .map(|path| path.to_string_lossy().into_owned())
    .map_err(Into::into)
}

fn bundled_templates_root(app: &AppHandle) -> Result<PathBuf, String> {
    let bundled = app
        .path()
        .resource_dir()
        .map_err(|error| error.to_string())?
        .join("templates");
    if bundled.is_dir() {
        return Ok(bundled);
    }
    #[cfg(debug_assertions)]
    {
        let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../templates");
        if source.is_dir() {
            return Ok(source);
        }
    }
    Err("Bundled templates are missing from this LighTex installation.".into())
}

#[tauri::command(rename_all = "camelCase")]
fn scan_project(
    project_id: ProjectId,
    state: tauri::State<'_, DesktopState>,
) -> Result<Vec<ProjectEntry>, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::project::scan(&root).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn open_document(
    project_id: ProjectId,
    relative_path: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<DocumentSnapshot, String> {
    let path = state
        .projects
        .resolve(&project_id, &relative_path)
        .map_err(String::from)?;
    lightex_core::document::read(&path, relative_path).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn document_revision(
    project_id: ProjectId,
    relative_path: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<Option<DocumentRevision>, String> {
    let path = state
        .projects
        .resolve(&project_id, relative_path)
        .map_err(String::from)?;
    lightex_core::document::current_revision(&path).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn locate_document(
    project_id: ProjectId,
    file_identifier: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<Option<String>, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    Ok(lightex_core::project::locate_file_identifier(
        &root,
        &file_identifier,
    ))
}

#[tauri::command(rename_all = "camelCase")]
fn save_document(
    project_id: ProjectId,
    relative_path: String,
    text: String,
    base_revision: Option<DocumentRevision>,
    overwrite_conflict: bool,
    state: tauri::State<'_, DesktopState>,
) -> Result<SaveOutcome, String> {
    let path = state
        .projects
        .resolve(&project_id, relative_path)
        .map_err(String::from)?;
    lightex_core::document::save(&path, &text, base_revision.as_ref(), overwrite_conflict)
        .map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn save_document_copy(path: String, text: String) -> Result<DocumentRevision, String> {
    let path = Path::new(&path);
    if !path.is_absolute() {
        return Err("Choose an absolute destination for Save Copy.".into());
    }
    lightex_core::document::write_copy(path, &text).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn create_file(
    project_id: ProjectId,
    parent: String,
    name: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<String, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::project::create_file(&root, &parent, &name).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn create_folder(
    project_id: ProjectId,
    parent: String,
    name: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<String, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::project::create_folder(&root, &parent, &name).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn rename_entry(
    project_id: ProjectId,
    relative_path: String,
    new_name: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<String, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::project::rename(&root, &relative_path, &new_name).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn duplicate_entry(
    project_id: ProjectId,
    relative_path: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<String, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::project::duplicate(&root, &relative_path).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn move_entry(
    project_id: ProjectId,
    relative_path: String,
    destination_folder: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<String, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::project::move_entry(&root, &relative_path, &destination_folder)
        .map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn trash_entry(
    project_id: ProjectId,
    relative_path: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<(), String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::project::move_to_trash(&root, &relative_path).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn upload_entries(
    project_id: ProjectId,
    destination_folder: String,
    sources: Vec<String>,
    state: tauri::State<'_, DesktopState>,
) -> Result<Vec<String>, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::project::copy_into(&root, &destination_folder, &sources).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn template_review(source_path: String) -> Result<TemplateReview, String> {
    lightex_core::template::review(Path::new(&source_path)).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn create_personal_template(
    name: String,
    review: TemplateReview,
    preview_base64: Option<String>,
) -> Result<PersonalTemplateManifestV2, String> {
    let preview = preview_base64
        .map(|value| STANDARD.decode(value).map_err(|error| error.to_string()))
        .transpose()?;
    lightex_core::template::create(&name, &review, preview.as_deref()).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn template_preview_pdf(review: TemplateReview) -> Result<Option<String>, String> {
    let Some(path) = lightex_core::template::preview_pdf_source(&review).map_err(String::from)?
    else {
        return Ok(None);
    };
    std::fs::read(path)
        .map(|data| Some(STANDARD.encode(data)))
        .map_err(|error| error.to_string())
}

#[tauri::command]
fn list_personal_templates() -> Result<Vec<PersonalTemplateManifestV2>, String> {
    lightex_core::template::list().map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn create_project_from_personal_template(
    id: String,
    parent_path: String,
    name: String,
) -> Result<String, String> {
    lightex_core::template::instantiate(&id, Path::new(&parent_path), &name)
        .map(|path| path.to_string_lossy().into_owned())
        .map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn remove_personal_template(id: String) -> Result<(), String> {
    lightex_core::template::remove(&id).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn personal_template_preview(id: String) -> Result<Option<String>, String> {
    let Some(path) = lightex_core::template::preview_path(&id).map_err(String::from)? else {
        return Ok(None);
    };
    std::fs::read(path)
        .map(|data| Some(STANDARD.encode(data)))
        .map_err(|error| error.to_string())
}

#[tauri::command(rename_all = "camelCase")]
fn project_search(
    project_id: ProjectId,
    query: SearchQuery,
    buffers: Vec<OpenBuffer>,
    state: tauri::State<'_, DesktopState>,
) -> Result<Vec<SearchResult>, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::search::search(&root, &query, &buffers).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn replace_preview(
    project_id: ProjectId,
    query: SearchQuery,
    replacement: String,
    buffers: Vec<OpenBuffer>,
    state: tauri::State<'_, DesktopState>,
) -> Result<Vec<ReplacePreview>, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::search::replacement_preview(&root, &query, &replacement, &buffers)
        .map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn apply_replacements(
    project_id: ProjectId,
    changes: Vec<ReplacePreview>,
    undo: bool,
    state: tauri::State<'_, DesktopState>,
) -> Result<(), String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::search::apply_replacements(&root, &changes, undo).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn document_outline(relative_path: String, text: String) -> Vec<OutlineItem> {
    lightex_core::outline::parse(&relative_path, &text)
}

#[tauri::command(rename_all = "camelCase")]
fn completion_index(
    project_id: ProjectId,
    state: tauri::State<'_, DesktopState>,
) -> Result<ProjectCompletionIndex, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    Ok(lightex_core::completion::build_index(&root))
}

async fn run_version_task<T, F>(lock: Arc<Mutex<()>>, task: F) -> Result<T, String>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, String> + Send + 'static,
{
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = lock.lock().expect("version lock poisoned");
        task()
    })
    .await
    .map_err(|error| format!("The version operation stopped unexpectedly: {error}"))?
}

#[tauri::command(rename_all = "camelCase")]
async fn list_project_versions(
    project_id: ProjectId,
    state: tauri::State<'_, DesktopState>,
) -> Result<Vec<ProjectVersionSummary>, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    run_version_task(state.version_lock.clone(), move || {
        lightex_core::version::list(&root).map_err(Into::into)
    })
    .await
}

#[tauri::command(rename_all = "camelCase")]
async fn review_project_version(
    project_id: ProjectId,
    main_document: Option<String>,
    state: tauri::State<'_, DesktopState>,
) -> Result<VersionSnapshotReview, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    run_version_task(state.version_lock.clone(), move || {
        lightex_core::version::review(&root, main_document.as_deref()).map_err(Into::into)
    })
    .await
}

#[tauri::command(rename_all = "camelCase")]
async fn create_project_version(
    project_id: ProjectId,
    name: String,
    main_document: Option<String>,
    state: tauri::State<'_, DesktopState>,
) -> Result<ProjectVersionSummary, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    run_version_task(state.version_lock.clone(), move || {
        lightex_core::version::create(
            &root,
            &name,
            lightex_core::ProjectVersionKind::Named,
            main_document,
        )
        .map_err(Into::into)
    })
    .await
}

#[tauri::command(rename_all = "camelCase")]
async fn rename_project_version(
    project_id: ProjectId,
    version_id: ProjectVersionId,
    name: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<ProjectVersionSummary, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    run_version_task(state.version_lock.clone(), move || {
        lightex_core::version::rename(&root, &version_id, &name).map_err(Into::into)
    })
    .await
}

#[tauri::command(rename_all = "camelCase")]
async fn delete_project_version(
    project_id: ProjectId,
    version_id: ProjectVersionId,
    state: tauri::State<'_, DesktopState>,
) -> Result<(), String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    if let Some(cancel) = state
        .version_cancel
        .lock()
        .expect("version cancel lock poisoned")
        .remove(&version_id.0)
    {
        cancel.store(true, Ordering::Relaxed);
    }
    run_version_task(state.version_lock.clone(), move || {
        lightex_core::version::remove(&root, &version_id).map_err(Into::into)
    })
    .await
}

#[tauri::command(rename_all = "camelCase")]
async fn project_version_tree(
    project_id: ProjectId,
    version_id: ProjectVersionId,
    state: tauri::State<'_, DesktopState>,
) -> Result<Vec<ProjectEntry>, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    run_version_task(state.version_lock.clone(), move || {
        lightex_core::version::tree(&root, &version_id).map_err(Into::into)
    })
    .await
}

#[tauri::command(rename_all = "camelCase")]
async fn read_project_version_file(
    project_id: ProjectId,
    version_id: ProjectVersionId,
    relative_path: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<String, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    run_version_task(state.version_lock.clone(), move || {
        lightex_core::version::read_text(&root, &version_id, &relative_path).map_err(Into::into)
    })
    .await
}

#[tauri::command(rename_all = "camelCase")]
async fn compare_project_version(
    project_id: ProjectId,
    version_id: ProjectVersionId,
    state: tauri::State<'_, DesktopState>,
) -> Result<VersionChangeSummary, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    run_version_task(state.version_lock.clone(), move || {
        lightex_core::version::compare(&root, &version_id).map_err(Into::into)
    })
    .await
}

#[tauri::command(rename_all = "camelCase")]
async fn project_version_line_summary(
    project_id: ProjectId,
    version_id: ProjectVersionId,
    buffers: Vec<OpenBuffer>,
    state: tauri::State<'_, DesktopState>,
) -> Result<VersionLineSummary, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    run_version_task(state.version_lock.clone(), move || {
        lightex_core::version::line_summary(&root, &version_id, &buffers).map_err(Into::into)
    })
    .await
}

#[tauri::command(rename_all = "camelCase")]
async fn project_version_file_diff(
    project_id: ProjectId,
    version_id: ProjectVersionId,
    relative_path: String,
    current_text: Option<String>,
    state: tauri::State<'_, DesktopState>,
) -> Result<VersionFileDiff, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    run_version_task(state.version_lock.clone(), move || {
        lightex_core::version::file_diff(
            &root,
            &version_id,
            &relative_path,
            current_text.as_deref(),
        )
        .map_err(Into::into)
    })
    .await
}

#[tauri::command(rename_all = "camelCase")]
async fn restore_project_version(
    project_id: ProjectId,
    version_id: ProjectVersionId,
    current_main_document: Option<String>,
    state: tauri::State<'_, DesktopState>,
    app: AppHandle,
) -> Result<VersionRestoreOutcome, String> {
    if let Some(cancel) = state
        .build_cancel
        .lock()
        .expect("build lock poisoned")
        .as_ref()
    {
        cancel.store(true, Ordering::Relaxed);
    }
    let root = state.projects.root(&project_id).map_err(String::from)?;
    // Stop watching before the transactional tree replacement so LighTex never
    // reports its own restore as an external edit conflict.
    *state.monitor.lock().expect("monitor lock poisoned") = None;
    let restore_root = root.clone();
    let outcome = run_version_task(state.version_lock.clone(), move || {
        lightex_core::version::restore(&restore_root, &version_id, current_main_document)
            .map_err(Into::into)
    })
    .await;
    if let Ok(monitor) = start_project_monitor(&root, app) {
        *state.monitor.lock().expect("monitor lock poisoned") = Some(monitor);
    }
    outcome
}

#[tauri::command(rename_all = "camelCase")]
async fn build_project_version_preview(
    mut request: BuildRequest,
    version_id: ProjectVersionId,
    state: tauri::State<'_, DesktopState>,
    app: AppHandle,
) -> Result<ProjectVersionSummary, String> {
    let root = state
        .projects
        .root(&request.project_id)
        .map_err(String::from)?;
    let cancel = Arc::new(AtomicBool::new(false));
    state
        .version_cancel
        .lock()
        .expect("version cancel lock poisoned")
        .insert(version_id.0.clone(), cancel.clone());
    let building = lightex_core::version::set_preview_status(
        &root,
        &version_id,
        VersionPreviewStatus::Building,
        None,
        None,
    )
    .map_err(String::from)?;
    let _ = app.emit(
        "version://preview",
        VersionPreviewEvent {
            version_id: version_id.clone(),
            status: VersionPreviewStatus::Building,
            message: None,
        },
    );
    let result = async {
        let (preview_root, manifest) =
            lightex_core::version::materialize_preview(&root, &version_id)?;
        request.entry_file = manifest.main_document.ok_or_else(|| {
            lightex_core::CoreError::Message("This version has no main document to compile.".into())
        })?;
        lightex_core::build::run_cancellable(&preview_root, &request, cancel).await
    }
    .await;
    state
        .version_cancel
        .lock()
        .expect("version cancel lock poisoned")
        .remove(&version_id.0);
    let summary = match result {
        Ok(result) if result.succeeded => lightex_core::version::set_preview_status(
            &root,
            &version_id,
            VersionPreviewStatus::Ready,
            None,
            result.preview_pdf_path,
        )
        .map_err(String::from)?,
        Ok(result) => {
            let message = result
                .diagnostics
                .first()
                .map(|group| group.primary.message.clone())
                .unwrap_or_else(|| "The saved version could not be compiled.".into());
            lightex_core::version::set_preview_status(
                &root,
                &version_id,
                VersionPreviewStatus::Failed,
                Some(message),
                None,
            )
            .map_err(String::from)?
        }
        Err(lightex_core::CoreError::Cancelled) => lightex_core::version::set_preview_status(
            &root,
            &version_id,
            VersionPreviewStatus::NotBuilt,
            None,
            None,
        )
        .map_err(String::from)?,
        Err(error) => lightex_core::version::set_preview_status(
            &root,
            &version_id,
            VersionPreviewStatus::Failed,
            Some(error.to_string()),
            None,
        )
        .map_err(String::from)?,
    };
    let _ = app.emit(
        "version://preview",
        VersionPreviewEvent {
            version_id,
            status: summary.preview_status,
            message: summary.preview_error.clone(),
        },
    );
    let _ = building;
    Ok(summary)
}

#[tauri::command(rename_all = "camelCase")]
fn read_project_version_preview(
    project_id: ProjectId,
    version_id: ProjectVersionId,
    state: tauri::State<'_, DesktopState>,
) -> Result<Option<String>, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    let Some(path) =
        lightex_core::version::preview_pdf_path(&root, &version_id).map_err(String::from)?
    else {
        return Ok(None);
    };
    std::fs::read(path)
        .map(|bytes| Some(STANDARD.encode(bytes)))
        .map_err(|error| error.to_string())
}

#[tauri::command]
fn detect_system_tex() -> ToolchainStatus {
    lightex_core::toolchain::detect_system()
}

#[tauri::command(rename_all = "camelCase")]
async fn build_project(
    request: BuildRequest,
    state: tauri::State<'_, DesktopState>,
    app: AppHandle,
) -> Result<BuildResult, String> {
    let root = state
        .projects
        .root(&request.project_id)
        .map_err(String::from)?;
    let cancel = Arc::new(AtomicBool::new(false));
    *state.build_cancel.lock().expect("build lock poisoned") = Some(cancel.clone());
    let _ = app.emit("build://event", lightex_core::BuildEvent::Started);
    let result = lightex_core::build::run_cancellable(&root, &request, cancel).await;
    *state.build_cancel.lock().expect("build lock poisoned") = None;
    let result = match result {
        Ok(result) => result,
        Err(lightex_core::CoreError::Cancelled) => {
            let _ = app.emit("build://event", lightex_core::BuildEvent::Cancelled);
            return Err("Build cancelled.".into());
        }
        Err(error) => return Err(error.to_string()),
    };
    let _ = app.emit(
        "build://event",
        lightex_core::BuildEvent::Finished {
            result: result.clone(),
        },
    );
    Ok(result)
}

#[tauri::command]
fn cancel_build(state: tauri::State<'_, DesktopState>) {
    if let Some(cancel) = state
        .build_cancel
        .lock()
        .expect("build lock poisoned")
        .as_ref()
    {
        cancel.store(true, Ordering::Relaxed);
    }
}

#[tauri::command(rename_all = "camelCase")]
fn read_preview_pdf(
    project_id: ProjectId,
    path: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<String, String> {
    let candidate = Path::new(&path)
        .canonicalize()
        .map_err(|error| format!("The PDF preview is unavailable: {error}"))?;
    if candidate
        .extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase)
        .as_deref()
        != Some("pdf")
    {
        return Err("Only PDF preview files can be read.".into());
    }

    let project_root = state.projects.root(&project_id).map_err(String::from)?;
    let cache_root = lightex_core::paths::cache_directory()
        .and_then(|path| path.canonicalize().map_err(Into::into))
        .map_err(String::from)?;
    if !candidate.starts_with(&project_root) && !candidate.starts_with(&cache_root) {
        return Err("The PDF preview is outside the project and LighTeX cache boundaries.".into());
    }

    std::fs::read(candidate)
        .map(|data| STANDARD.encode(data))
        .map_err(|error| error.to_string())
}

#[tauri::command(rename_all = "camelCase")]
async fn synctex_forward(
    project_id: ProjectId,
    executable_path: String,
    source_relative: String,
    line: usize,
    column: usize,
    pdf_path: String,
    state: tauri::State<'_, DesktopState>,
) -> Result<Option<SyncTeXPdfTarget>, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::synctex::forward(
        Path::new(&executable_path),
        &root,
        &source_relative,
        line,
        column,
        Path::new(&pdf_path),
    )
    .await
    .map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
async fn synctex_inverse(
    project_id: ProjectId,
    executable_path: String,
    pdf_path: String,
    page: usize,
    x: f64,
    y_from_top: f64,
    state: tauri::State<'_, DesktopState>,
) -> Result<Option<SyncTeXSourceTarget>, String> {
    let root = state.projects.root(&project_id).map_err(String::from)?;
    lightex_core::synctex::inverse(
        Path::new(&executable_path),
        &root,
        Path::new(&pdf_path),
        page,
        x,
        y_from_top,
    )
    .await
    .map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
async fn synctex_project_version_forward(
    project_id: ProjectId,
    version_id: ProjectVersionId,
    executable_path: String,
    source_relative: String,
    line: usize,
    column: usize,
    state: tauri::State<'_, DesktopState>,
) -> Result<Option<SyncTeXPdfTarget>, String> {
    let project_root = state.projects.root(&project_id).map_err(String::from)?;
    let preview_root = lightex_core::version::preview_project_root(&project_root, &version_id)
        .map_err(String::from)?;
    let Some(pdf_path) = lightex_core::version::preview_pdf_path(&project_root, &version_id)
        .map_err(String::from)?
    else {
        return Ok(None);
    };
    lightex_core::synctex::forward(
        Path::new(&executable_path),
        &preview_root,
        &source_relative,
        line,
        column,
        &pdf_path,
    )
    .await
    .map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
async fn synctex_project_version_inverse(
    project_id: ProjectId,
    version_id: ProjectVersionId,
    executable_path: String,
    page: usize,
    x: f64,
    y_from_top: f64,
    state: tauri::State<'_, DesktopState>,
) -> Result<Option<SyncTeXSourceTarget>, String> {
    let project_root = state.projects.root(&project_id).map_err(String::from)?;
    let preview_root = lightex_core::version::preview_project_root(&project_root, &version_id)
        .map_err(String::from)?;
    let Some(pdf_path) = lightex_core::version::preview_pdf_path(&project_root, &version_id)
        .map_err(String::from)?
    else {
        return Ok(None);
    };
    lightex_core::synctex::inverse(
        Path::new(&executable_path),
        &preview_root,
        &pdf_path,
        page,
        x,
        y_from_top,
    )
    .await
    .map_err(Into::into)
}

#[tauri::command]
async fn runtime_manifest() -> Result<RuntimeManifestV2, String> {
    lightex_core::runtime::fetch_manifest()
        .await
        .map_err(Into::into)
}

#[tauri::command]
fn installed_runtimes() -> Result<Vec<ManagedRuntimeRecordV2>, String> {
    lightex_core::runtime::scan_installed().map_err(Into::into)
}

#[tauri::command]
fn runtime_environment() -> RuntimeEnvironment {
    lightex_core::runtime::environment()
}

#[tauri::command(rename_all = "camelCase")]
fn runtime_inventory(active_record_path: Option<String>) -> Result<Vec<InstalledRuntime>, String> {
    lightex_core::runtime::inventory(active_record_path.as_deref()).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn remove_runtime(
    record: ManagedRuntimeRecordV2,
    active_record_path: Option<String>,
) -> Result<(), String> {
    lightex_core::runtime::remove_inactive(&record, active_record_path.as_deref())
        .map_err(Into::into)
}

#[tauri::command]
fn storage_usage() -> Result<StorageUsage, String> {
    lightex_core::runtime::storage_usage().map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn clear_storage(
    downloads: bool,
    staging: bool,
    build_cache: bool,
) -> Result<StorageUsage, String> {
    lightex_core::runtime::clear_storage(downloads, staging, build_cache).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
fn runtime_toolchain(record: ManagedRuntimeRecordV2) -> Result<ToolchainStatus, String> {
    lightex_core::toolchain::from_runtime(&record).map_err(Into::into)
}

#[tauri::command(rename_all = "camelCase")]
async fn install_runtime(
    manifest: RuntimeManifestV2,
    variant: RuntimeVariant,
    state: tauri::State<'_, DesktopState>,
    app: AppHandle,
) -> Result<ManagedRuntimeRecordV2, String> {
    let cancel = Arc::new(AtomicBool::new(false));
    *state.runtime_cancel.lock().expect("runtime lock poisoned") = Some(cancel.clone());
    let asset = lightex_core::runtime::selected_asset(&manifest, variant).map_err(String::from)?;
    let result =
        lightex_core::runtime::install(&manifest, &asset, cancel, |event: RuntimeInstallEvent| {
            let _ = app.emit("runtime://install", event);
        })
        .await;
    if let Err(error) = &result
        && !matches!(error, lightex_core::CoreError::Cancelled)
    {
        let _ = app.emit(
            "runtime://install",
            RuntimeInstallEvent::Failed {
                message: error.to_string(),
            },
        );
    }
    *state.runtime_cancel.lock().expect("runtime lock poisoned") = None;
    result.map_err(String::from)
}

#[tauri::command]
fn cancel_runtime_install(state: tauri::State<'_, DesktopState>) {
    if let Some(cancel) = state
        .runtime_cancel
        .lock()
        .expect("runtime lock poisoned")
        .as_ref()
    {
        cancel.store(true, Ordering::Relaxed);
    }
}

#[tauri::command(rename_all = "camelCase")]
async fn install_missing_package(
    record: ManagedRuntimeRecordV2,
    missing_file: String,
) -> Result<String, String> {
    lightex_core::runtime::install_missing_package(&record, &missing_file)
        .await
        .map_err(Into::into)
}

#[tauri::command]
async fn check_for_updates() -> Result<AppUpdateInfo, String> {
    lightex_core::update::check(env!("CARGO_PKG_VERSION"))
        .await
        .map_err(Into::into)
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .manage(DesktopState::default())
        .setup(|app| {
            let handle = app.handle();
            let settings = MenuItemBuilder::with_id("settings", "Settings…")
                .accelerator("CmdOrCtrl+,")
                .build(handle)?;
            let new_project = MenuItemBuilder::with_id("new-project", "New Project…")
                .accelerator("CmdOrCtrl+Shift+N")
                .build(handle)?;
            let open_project = MenuItemBuilder::with_id("open-project", "Open Project…")
                .accelerator("CmdOrCtrl+O")
                .build(handle)?;
            let save = MenuItemBuilder::with_id("save", "Save")
                .accelerator("CmdOrCtrl+S")
                .build(handle)?;
            let build = MenuItemBuilder::with_id("build", "Recompile")
                .accelerator("CmdOrCtrl+B")
                .build(handle)?;
            let project_search = MenuItemBuilder::with_id("project-search", "Find in Project")
                .accelerator("CmdOrCtrl+Shift+F")
                .build(handle)?;
            let insert_shelf = MenuItemBuilder::with_id("insert-shelf", "Insert Shelf")
                .accelerator("CmdOrCtrl+Shift+I")
                .build(handle)?;
            let save_version =
                MenuItemBuilder::with_id("save-version", "Save Version…").build(handle)?;
            let show_versions =
                MenuItemBuilder::with_id("show-versions", "Show Versions").build(handle)?;
            let app_menu = SubmenuBuilder::new(handle, "LighTex")
                .about(None)
                .separator()
                .item(&settings)
                .separator()
                .quit()
                .build()?;
            let file_menu = SubmenuBuilder::new(handle, "File")
                .item(&new_project)
                .item(&open_project)
                .separator()
                .item(&save)
                .separator()
                .close_window()
                .build()?;
            let edit_menu = SubmenuBuilder::new(handle, "Edit")
                .undo()
                .redo()
                .separator()
                .cut()
                .copy()
                .paste()
                .select_all()
                .build()?;
            let project_menu = SubmenuBuilder::new(handle, "Project")
                .item(&build)
                .item(&project_search)
                .item(&insert_shelf)
                .separator()
                .item(&save_version)
                .item(&show_versions)
                .build()?;
            let view_menu = SubmenuBuilder::new(handle, "View").fullscreen().build()?;
            let window_menu = SubmenuBuilder::new(handle, "Window")
                .minimize()
                .close_window()
                .build()?;
            let menu = MenuBuilder::new(handle)
                .item(&app_menu)
                .item(&file_menu)
                .item(&edit_menu)
                .item(&project_menu)
                .item(&view_menu)
                .item(&window_menu)
                .build()?;
            app.set_menu(menu)?;
            Ok(())
        })
        .on_menu_event(|app, event| {
            let _ = app.emit("menu://action", event.id().as_ref());
        })
        .invoke_handler(tauri::generate_handler![
            load_config,
            save_config,
            load_session,
            save_session,
            open_project,
            close_project,
            create_project,
            create_project_from_template,
            scan_project,
            open_document,
            document_revision,
            locate_document,
            save_document,
            save_document_copy,
            create_file,
            create_folder,
            rename_entry,
            duplicate_entry,
            move_entry,
            trash_entry,
            upload_entries,
            template_review,
            create_personal_template,
            template_preview_pdf,
            list_personal_templates,
            create_project_from_personal_template,
            remove_personal_template,
            personal_template_preview,
            project_search,
            replace_preview,
            apply_replacements,
            document_outline,
            completion_index,
            list_project_versions,
            review_project_version,
            create_project_version,
            rename_project_version,
            delete_project_version,
            project_version_tree,
            read_project_version_file,
            compare_project_version,
            project_version_line_summary,
            project_version_file_diff,
            restore_project_version,
            build_project_version_preview,
            read_project_version_preview,
            detect_system_tex,
            build_project,
            cancel_build,
            read_preview_pdf,
            synctex_forward,
            synctex_inverse,
            synctex_project_version_forward,
            synctex_project_version_inverse,
            runtime_manifest,
            installed_runtimes,
            runtime_environment,
            runtime_inventory,
            remove_runtime,
            storage_usage,
            clear_storage,
            runtime_toolchain,
            install_runtime,
            cancel_runtime_install,
            install_missing_package,
            check_for_updates,
        ])
        .run(tauri::generate_context!())
        .expect("error while running LighTex");
}
