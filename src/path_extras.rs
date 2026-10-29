use serde::Serialize;
use std::fs;
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
#[cfg(windows)]
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct PathExecutable {
    pub name: String,
    pub path_position: usize,
}

#[cfg(unix)]
pub fn inspect(
    path_directories: &[std::path::PathBuf],
    known_commands: &[&str],
) -> Vec<PathExecutable> {
    let known: std::collections::BTreeSet<String> = known_commands
        .iter()
        .map(|name| name.to_ascii_lowercase())
        .collect();
    let mut found = std::collections::BTreeSet::new();
    let mut result = Vec::new();
    for (index, directory) in path_directories.iter().enumerate() {
        if !directory.is_absolute() {
            continue;
        }
        let Ok(entries) = fs::read_dir(directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(metadata) = fs::symlink_metadata(&path) else {
                continue;
            };
            if !metadata.is_file()
                || metadata.file_type().is_symlink()
                || metadata.permissions().mode() & 0o111 == 0
            {
                continue;
            }
            let Some(name) = path
                .file_name()
                .and_then(|name| name.to_str())
                .filter(|name| !name.is_empty() && !name.chars().any(char::is_control))
            else {
                continue;
            };
            let normalized = name.to_ascii_lowercase();
            if known.contains(&normalized) || !found.insert(normalized) {
                continue;
            }
            result.push(PathExecutable {
                name: name.to_owned(),
                path_position: index + 1,
            });
        }
    }
    result.sort_by(|a, b| {
        a.name
            .to_ascii_lowercase()
            .cmp(&b.name.to_ascii_lowercase())
    });
    result
}

#[cfg(windows)]
pub fn inspect(
    path_directories: &[std::path::PathBuf],
    known_commands: &[&str],
) -> Vec<PathExecutable> {
    let known: std::collections::BTreeSet<String> = known_commands
        .iter()
        .map(|name| name.to_ascii_lowercase())
        .collect();
    let mut found = std::collections::BTreeSet::new();
    let mut result = Vec::new();
    for (index, directory) in path_directories.iter().enumerate() {
        if !directory.is_absolute() {
            continue;
        }
        let Ok(entries) = fs::read_dir(directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(metadata) = fs::symlink_metadata(&path) else {
                continue;
            };
            if !metadata.is_file() || metadata.file_type().is_symlink() {
                continue;
            }
            let Some(name) = path
                .file_name()
                .and_then(|name| name.to_str())
                .filter(|name| !name.is_empty() && !name.chars().any(char::is_control))
            else {
                continue;
            };
            let Some(extension) = path.extension().and_then(|ext| ext.to_str()) else {
                continue;
            };
            if !["exe", "com", "cmd", "bat"]
                .iter()
                .any(|allowed| extension.eq_ignore_ascii_case(allowed))
            {
                continue;
            }
            let stem = Path::new(name)
                .file_stem()
                .and_then(|stem| stem.to_str())
                .unwrap_or(name);
            let normalized = stem.to_ascii_lowercase();
            if known.contains(&normalized) || !found.insert(normalized) {
                continue;
            }
            result.push(PathExecutable {
                name: name.to_owned(),
                path_position: index + 1,
            });
        }
    }
    result.sort_by(|a, b| {
        a.name
            .to_ascii_lowercase()
            .cmp(&b.name.to_ascii_lowercase())
    });
    result
}

#[cfg(not(any(unix, windows)))]
pub fn inspect(_: &[std::path::PathBuf], _: &[&str]) -> Vec<PathExecutable> {
    Vec::new()
}
