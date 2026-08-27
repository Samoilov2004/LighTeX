use std::{
    path::{Path, PathBuf},
    sync::mpsc,
    thread,
    time::Duration,
};

use notify::{RecommendedWatcher, RecursiveMode, Watcher};

use crate::{CoreResult, ProjectChangeEvent, paths::relative_string};

pub struct ProjectMonitor {
    _watcher: RecommendedWatcher,
}

impl ProjectMonitor {
    pub fn start(
        root: &Path,
        callback: impl Fn(ProjectChangeEvent) + Send + 'static,
    ) -> CoreResult<Self> {
        let root = root.to_path_buf();
        let (sender, receiver) = mpsc::channel::<Vec<PathBuf>>();
        let mut watcher =
            notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
                if let Ok(event) = event {
                    let _ = sender.send(event.paths);
                }
            })?;
        watcher.watch(&root, RecursiveMode::Recursive)?;
        thread::Builder::new()
            .name("lightex-project-monitor".into())
            .spawn(move || {
                while let Ok(first) = receiver.recv() {
                    let mut paths = first;
                    while let Ok(next) = receiver.recv_timeout(Duration::from_millis(200)) {
                        paths.extend(next);
                    }
                    let mut relative: Vec<String> = paths
                        .into_iter()
                        .filter_map(|path| relative_string(&root, &path))
                        .filter(|path| !path.starts_with(".git/") && !path.starts_with(".lightex-"))
                        .collect();
                    relative.sort();
                    relative.dedup();
                    if !relative.is_empty() {
                        callback(ProjectChangeEvent { paths: relative });
                    }
                }
            })?;
        Ok(Self { _watcher: watcher })
    }
}
