use continuity_agent::{
    history,
    model::{Host, Report, Resource},
};
use std::fs;

fn resource(id: &str, instance: &str, version: &str) -> Resource {
    Resource {
        canonical_tool_id: id.into(),
        display_name: id.into(),
        kind: "package".into(),
        version: Some(version.into()),
        installation_provider: Some("homebrew_formula".into()),
        provider_package_id: Some(id.into()),
        installation_instance_id: instance.into(),
        discovery_adapter: "homebrew_formula".into(),
        evidence: Vec::new(),
        path_status: None,
        installation_path: None,
    }
}

fn report(at: u64, resources: Vec<Resource>) -> Report {
    Report {
        schema_version: 1,
        observed_at_unix_seconds: at,
        host: Host {
            platform: "macos",
            architecture: "aarch64",
            os_version: None,
        },
        resources,
        warnings: Vec::new(),
    }
}

fn snapshots(dir: &std::path::Path) -> usize {
    fs::read_dir(dir)
        .unwrap()
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().starts_with("scan-"))
        .count()
}

#[test]
fn first_scan_has_no_changes_and_is_saved() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path().join("history");
    let changes = history::record(&dir, &report(1, vec![resource("git", "a", "2.0")])).unwrap();
    assert!(changes.is_none());
    assert!(dir.join("latest.json").is_file());
    assert_eq!(snapshots(&dir), 1);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = fs::metadata(dir.join("latest.json"))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o077, 0);
    }
}

#[test]
fn reports_added_removed_and_upgraded_packages() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    history::record(
        dir,
        &report(
            1,
            vec![resource("git", "a", "2.0"), resource("redis", "r", "7.0")],
        ),
    )
    .unwrap();
    let changes = history::record(
        dir,
        &report(
            2,
            vec![resource("git", "b", "2.1"), resource("go", "g", "1.26")],
        ),
    )
    .unwrap()
    .unwrap();
    assert_eq!(changes.previous_observed_at_unix_seconds, 1);
    assert_eq!(changes.updated.len(), 1);
    assert_eq!(changes.updated[0].version.as_deref(), Some("2.1"));
    assert_eq!(changes.updated[0].previous_version.as_deref(), Some("2.0"));
    assert_eq!(changes.added[0].canonical_tool_id, "go");
    assert_eq!(changes.removed[0].canonical_tool_id, "redis");
    assert_eq!(snapshots(dir), 2);
    let saved: serde_json::Value =
        serde_json::from_slice(&fs::read(dir.join("changes.json")).unwrap()).unwrap();
    assert_eq!(saved["added"][0]["canonical_tool_id"], "go");
}

#[test]
fn unchanged_scan_keeps_no_extra_snapshot() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    let items = vec![resource("git", "a", "2.0")];
    history::record(dir, &report(1, items.clone())).unwrap();
    let changes = history::record(dir, &report(2, items)).unwrap().unwrap();
    assert!(changes.is_empty());
    assert_eq!(snapshots(dir), 1);
    assert!(!dir.join("changes.json").exists());
}

#[test]
fn incomplete_scan_preserves_the_previous_inventory() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    history::record(dir, &report(1, vec![resource("git", "a", "2.0")])).unwrap();
    let mut partial = report(2, Vec::new());
    partial
        .warnings
        .push("Unable to read Homebrew inventory".into());
    assert!(history::record(dir, &partial).is_err());
    let latest: serde_json::Value =
        serde_json::from_slice(&fs::read(dir.join("latest.json")).unwrap()).unwrap();
    assert_eq!(latest["observed_at_unix_seconds"], 1);
    assert_eq!(snapshots(dir), 1);
}

#[test]
fn changed_scans_in_the_same_second_keep_both_snapshots() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    history::record(dir, &report(1, vec![resource("git", "a", "2.0")])).unwrap();
    history::record(dir, &report(1, vec![resource("git", "b", "2.1")])).unwrap();
    assert_eq!(snapshots(dir), 2);
}

#[test]
fn ambiguous_installations_are_not_paired_as_upgrades() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    history::record(
        dir,
        &report(
            1,
            vec![resource("node", "a", "18"), resource("node", "b", "20")],
        ),
    )
    .unwrap();
    let changes = history::record(
        dir,
        &report(
            2,
            vec![resource("node", "c", "22"), resource("node", "d", "24")],
        ),
    )
    .unwrap()
    .unwrap();
    assert!(changes.updated.is_empty());
    assert_eq!(changes.added.len(), 2);
    assert_eq!(changes.removed.len(), 2);
}

#[test]
fn unreadable_previous_scan_is_treated_as_first() {
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join("latest.json"), "not json").unwrap();
    let changes = history::record(temp.path(), &report(1, Vec::new())).unwrap();
    assert!(changes.is_none());
}

#[cfg(unix)]
#[test]
fn saved_files_stay_private_when_a_loose_file_already_exists() {
    use std::os::unix::fs::PermissionsExt;
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(dir.join("latest.json"), "{}").unwrap();
    fs::set_permissions(dir.join("latest.json"), fs::Permissions::from_mode(0o644)).unwrap();
    history::record(dir, &report(1, Vec::new())).unwrap();
    let mode = fs::metadata(dir.join("latest.json"))
        .unwrap()
        .permissions()
        .mode();
    assert_eq!(mode & 0o077, 0);
    let dir_mode = fs::metadata(dir).unwrap().permissions().mode();
    assert_eq!(dir_mode & 0o077, 0);
    assert!(fs::read_dir(dir)
        .unwrap()
        .flatten()
        .all(|e| !e.file_name().to_string_lossy().ends_with(".tmp")));
}

#[cfg(unix)]
#[test]
fn symlinked_history_directory_is_refused() {
    use std::os::unix::fs::PermissionsExt;
    let temp = tempfile::tempdir().unwrap();
    let target = temp.path().join("shared");
    fs::create_dir(&target).unwrap();
    fs::set_permissions(&target, fs::Permissions::from_mode(0o755)).unwrap();
    let link = temp.path().join("history");
    std::os::unix::fs::symlink(&target, &link).unwrap();
    assert!(history::record(&link, &report(1, Vec::new())).is_err());
    let mode = fs::metadata(&target).unwrap().permissions().mode();
    assert_eq!(mode & 0o777, 0o755);
    assert!(fs::read_dir(&target).unwrap().next().is_none());
}

#[cfg(unix)]
#[test]
fn symlinked_latest_report_is_not_read_or_overwritten() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path().join("history");
    fs::create_dir(&dir).unwrap();
    let target = temp.path().join("outside.json");
    let original = r#"{"observed_at_unix_seconds":1,"resources":[]}"#;
    fs::write(&target, original).unwrap();
    std::os::unix::fs::symlink(&target, dir.join("latest.json")).unwrap();
    let changes = history::record(&dir, &report(2, Vec::new())).unwrap();
    assert!(changes.is_none());
    assert_eq!(fs::read_to_string(target).unwrap(), original);
}

#[cfg(unix)]
#[test]
fn symlinked_history_lock_is_refused() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path().join("history");
    fs::create_dir(&dir).unwrap();
    let target = temp.path().join("outside");
    fs::write(&target, "untouched").unwrap();
    std::os::unix::fs::symlink(&target, dir.join(".lock")).unwrap();
    assert!(history::record(&dir, &report(1, Vec::new())).is_err());
    assert_eq!(fs::read_to_string(target).unwrap(), "untouched");
}

#[cfg(unix)]
#[test]
fn concurrent_history_writes_wait_for_the_lock() {
    use std::{os::fd::AsRawFd, sync::mpsc, thread, time::Duration};
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path().to_owned();
    let lock = fs::File::create(dir.join(".lock")).unwrap();
    // SAFETY: the file remains open while the lock is held and released.
    assert_eq!(unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX) }, 0);
    let (sender, receiver) = mpsc::channel();
    let worker = thread::spawn(move || {
        sender
            .send(history::record(&dir, &report(1, Vec::new())))
            .unwrap();
    });
    assert!(matches!(
        receiver.recv_timeout(Duration::from_millis(100)),
        Err(mpsc::RecvTimeoutError::Timeout)
    ));
    // SAFETY: the file descriptor still refers to the open lock file.
    assert_eq!(unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_UN) }, 0);
    assert!(receiver
        .recv_timeout(Duration::from_secs(3))
        .unwrap()
        .is_ok());
    worker.join().unwrap();
}
