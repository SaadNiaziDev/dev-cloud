use crate::{model::Report, safe_file::read_bounded_regular};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};

const LATEST: &str = "latest.json";
const CHANGES: &str = "changes.json";
const MAX_SNAPSHOTS: usize = 50;
const MAX_SNAPSHOT_BYTES: u64 = 16 * 1024 * 1024;
static SNAPSHOT_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Deserialize)]
struct Saved {
    observed_at_unix_seconds: u64,
    resources: Vec<SavedResource>,
}

#[derive(Debug, Clone, Deserialize)]
struct SavedResource {
    canonical_tool_id: String,
    display_name: String,
    kind: String,
    version: Option<String>,
    installation_provider: Option<String>,
    provider_package_id: Option<String>,
    installation_instance_id: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct Change {
    pub display_name: String,
    pub kind: String,
    pub canonical_tool_id: String,
    pub installation_provider: Option<String>,
    pub version: Option<String>,
    pub previous_version: Option<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct Changes {
    pub previous_observed_at_unix_seconds: u64,
    pub added: Vec<Change>,
    pub removed: Vec<Change>,
    pub updated: Vec<Change>,
}

impl Changes {
    pub fn is_empty(&self) -> bool {
        self.added.is_empty() && self.removed.is_empty() && self.updated.is_empty()
    }
}

/// Compares `report` with the last saved scan, then saves it. A copy is kept
/// only when something changed, so the directory holds change points.
pub fn record(dir: &Path, report: &Report) -> io::Result<Option<Changes>> {
    if report.warnings.iter().any(|warning| {
        (warning.starts_with("Unable to read ") && warning.contains(" inventory"))
            || warning.ends_with(" inventory exceeded its entry limit")
    }) {
        return Err(io::Error::other("inventory is incomplete"));
    }
    create_private_dir(dir)?;
    let previous = load(&dir.join(LATEST));
    let changes = previous.as_ref().map(|previous| diff(previous, report));
    let json = serde_json::to_vec_pretty(report).map_err(io::Error::other)?;
    if changes.as_ref().is_none_or(|c| !c.is_empty()) {
        let name = format!(
            "scan-{}-{}-{}.json",
            report.observed_at_unix_seconds,
            std::process::id(),
            SNAPSHOT_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        );
        write_private(&dir.join(name), &json)?;
        prune(dir)?;
    }
    // The latest non-empty diff outlives quiet scans so the app can show it after relaunch.
    if let Some(changes) = changes.as_ref().filter(|c| !c.is_empty()) {
        let bytes = serde_json::to_vec_pretty(changes).map_err(io::Error::other)?;
        write_private(&dir.join(CHANGES), &bytes)?;
    }
    write_private(&dir.join(LATEST), &json)?;
    Ok(changes)
}

fn diff(previous: &Saved, report: &Report) -> Changes {
    let key = |id: &str, instance: &str| (id.to_owned(), instance.to_owned());
    let mut old: BTreeMap<_, _> = previous
        .resources
        .iter()
        .map(|r| (key(&r.canonical_tool_id, &r.installation_instance_id), r))
        .collect();
    let mut changes = Changes {
        previous_observed_at_unix_seconds: previous.observed_at_unix_seconds,
        added: Vec::new(),
        removed: Vec::new(),
        updated: Vec::new(),
    };
    let mut unmatched = Vec::new();
    for resource in &report.resources {
        match old.remove(&key(
            &resource.canonical_tool_id,
            &resource.installation_instance_id,
        )) {
            Some(before) => {
                if before.version != resource.version
                    || before.installation_provider != resource.installation_provider
                {
                    changes.updated.push(Change {
                        previous_version: before.version.clone(),
                        ..change(resource)
                    });
                }
            }
            None => unmatched.push(resource),
        }
    }
    // An upgrade moves the install to a new directory, so pair a new instance
    // with a vanished one from the same package before calling it added.
    for resource in &unmatched {
        let same_package: Vec<_> = old
            .iter()
            .filter(|(_, before)| {
                before.canonical_tool_id == resource.canonical_tool_id
                    && before.installation_provider == resource.installation_provider
                    && before.provider_package_id == resource.provider_package_id
                    && before.kind == resource.kind
            })
            .map(|(key, _)| key.clone())
            .collect();
        let new_count = unmatched
            .iter()
            .filter(|candidate| {
                candidate.canonical_tool_id == resource.canonical_tool_id
                    && candidate.installation_provider == resource.installation_provider
                    && candidate.provider_package_id == resource.provider_package_id
                    && candidate.kind == resource.kind
            })
            .count();
        let previous = if same_package.len() == 1 && new_count == 1 {
            old.remove(&same_package[0])
        } else {
            None
        };
        match previous {
            Some(before) => changes.updated.push(Change {
                previous_version: before.version.clone(),
                ..change(resource)
            }),
            None => changes.added.push(change(resource)),
        }
    }
    changes.removed = old
        .into_values()
        .map(|before| Change {
            display_name: before.display_name.clone(),
            kind: before.kind.clone(),
            canonical_tool_id: before.canonical_tool_id.clone(),
            installation_provider: before.installation_provider.clone(),
            version: before.version.clone(),
            previous_version: None,
        })
        .collect();
    changes
}

fn change(resource: &crate::model::Resource) -> Change {
    Change {
        display_name: resource.display_name.clone(),
        kind: resource.kind.clone(),
        canonical_tool_id: resource.canonical_tool_id.clone(),
        installation_provider: resource.installation_provider.clone(),
        version: resource.version.clone(),
        previous_version: None,
    }
}

fn load(path: &Path) -> Option<Saved> {
    let bytes = read_bounded_regular(path, MAX_SNAPSHOT_BYTES).ok()??;
    serde_json::from_slice(&bytes).ok()
}

fn prune(dir: &Path) -> io::Result<()> {
    let mut snapshots: Vec<PathBuf> = fs::read_dir(dir)?
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.starts_with("scan-") && n.ends_with(".json"))
        })
        .collect();
    snapshots.sort();
    let excess = snapshots.len().saturating_sub(MAX_SNAPSHOTS);
    for path in snapshots.into_iter().take(excess) {
        fs::remove_file(path)?;
    }
    Ok(())
}

// History lives in a directory only this user can read. A symlinked directory is
// refused so permissions are never changed on whatever it points to.
fn create_private_dir(dir: &Path) -> io::Result<()> {
    fs::create_dir_all(dir)?;
    if fs::symlink_metadata(dir)?.file_type().is_symlink() {
        return Err(io::Error::other("history directory must not be a symlink"));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
        let directory = fs::OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW)
            .open(dir)?;
        directory.set_permissions(fs::Permissions::from_mode(0o700))?;
    }
    Ok(())
}

// A fresh temporary file is created with owner-only permissions and renamed into
// place, so readers never see a partial write and stale files cannot widen access.
fn write_private(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    match fs::remove_file(&temporary) {
        Err(error) if error.kind() != io::ErrorKind::NotFound => return Err(error),
        _ => {}
    }
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let result = options.open(&temporary).and_then(|mut file| {
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&temporary, path)
    });
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}
