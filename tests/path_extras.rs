#[cfg(unix)]
#[test]
fn reports_only_unknown_executable_basenames_and_first_path_position() {
    use devcloud_agent::path_extras::inspect;
    use std::{fs, os::unix::fs::PermissionsExt};
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    let executable = first.path().join("custom-tool");
    fs::write(&executable, "not executed").unwrap();
    fs::set_permissions(&executable, fs::Permissions::from_mode(0o755)).unwrap();
    let known = first.path().join("git");
    fs::write(&known, "never run").unwrap();
    fs::set_permissions(&known, fs::Permissions::from_mode(0o755)).unwrap();
    let duplicate = second.path().join("custom-tool");
    fs::write(&duplicate, "never run").unwrap();
    fs::set_permissions(&duplicate, fs::Permissions::from_mode(0o755)).unwrap();

    let results = inspect(
        &[first.path().to_owned(), second.path().to_owned()],
        &["git"],
    );
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].name, "custom-tool");
    assert_eq!(results[0].path_position, 1);
}

#[cfg(unix)]
#[test]
fn ignores_symlinks_and_non_executable_files() {
    use devcloud_agent::path_extras::inspect;
    use std::{
        fs,
        os::unix::fs::{symlink, PermissionsExt},
    };
    let directory = tempfile::tempdir().unwrap();
    let plain = directory.path().join("plain.txt");
    fs::write(&plain, "ignore").unwrap();
    let linked = directory.path().join("linked-tool");
    symlink(&plain, &linked).unwrap();
    let results = inspect(&[directory.path().to_owned()], &[]);
    assert!(results.is_empty());
    let executable = directory.path().join("safe-tool");
    fs::write(&executable, "not run").unwrap();
    fs::set_permissions(&executable, fs::Permissions::from_mode(0o755)).unwrap();
    assert_eq!(inspect(&[directory.path().to_owned()], &[]).len(), 1);
}

#[cfg(unix)]
#[test]
fn ignores_relative_path_entries() {
    use devcloud_agent::path_extras::inspect;
    assert!(inspect(&[std::path::PathBuf::from("relative/path")], &[]).is_empty());
}

#[cfg(windows)]
#[test]
fn windows_scans_known_extensions_and_deduplicates_curated_commands() {
    use devcloud_agent::path_extras::inspect;
    use std::fs;
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    fs::write(first.path().join("git.EXE"), "not executed").unwrap();
    fs::write(first.path().join("custom-tool.cmd"), "not executed").unwrap();
    fs::write(first.path().join("script.ps1"), "not executed").unwrap();
    fs::write(second.path().join("custom-tool.exe"), "not executed").unwrap();
    let results = inspect(
        &[first.path().to_owned(), second.path().to_owned()],
        &["git"],
    );
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].name, "custom-tool.cmd");
    assert_eq!(results[0].path_position, 1);
}
