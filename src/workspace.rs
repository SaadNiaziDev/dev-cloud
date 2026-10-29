use crate::safe_file::read_bounded_regular;
use serde::Serialize;
use std::{
    fs, io,
    path::{Path, PathBuf},
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Workspace {
    pub id: String,
    pub name: String,
    pub branch: Option<String>,
    pub is_linked_worktree: bool,
    pub linked_worktree_count: usize,
    pub path: Option<String>,
}

pub fn inspect(root: &Path, include_path: bool) -> io::Result<Option<Workspace>> {
    if !root.is_dir() {
        return Ok(None);
    }

    let git_metadata = root.join(".git");
    let metadata = match fs::symlink_metadata(&git_metadata) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error),
    };

    if metadata.file_type().is_symlink() {
        return Ok(None);
    }
    let is_linked_worktree = metadata.is_file() && is_gitdir_pointer(&git_metadata)?;
    if !metadata.is_dir() && !is_linked_worktree {
        return Ok(None);
    }

    let branch = if is_linked_worktree {
        None
    } else {
        read_branch(&git_metadata.join("HEAD"))?
    };
    let linked_worktree_count = if is_linked_worktree {
        0
    } else {
        count_worktrees(&git_metadata.join("worktrees"))
    };
    let canonical_root = fs::canonicalize(root)?;
    let name = root
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .unwrap_or("Git repository")
        .to_owned();

    Ok(Some(Workspace {
        id: stable_id(&canonical_root),
        name,
        branch,
        is_linked_worktree,
        linked_worktree_count,
        path: include_path.then(|| canonical_root.to_string_lossy().into_owned()),
    }))
}

fn is_gitdir_pointer(path: &Path) -> io::Result<bool> {
    let Some(contents) = read_bounded_regular(path, 4096)? else {
        return Ok(false);
    };
    let contents = String::from_utf8(contents)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
    Ok(contents.lines().next().is_some_and(|line| {
        line.trim()
            .strip_prefix("gitdir: ")
            .is_some_and(|path| !path.is_empty())
    }))
}

fn read_branch(head_path: &Path) -> io::Result<Option<String>> {
    let Some(contents) = read_bounded_regular(head_path, 1024)? else {
        return Ok(None);
    };
    let head = String::from_utf8(contents)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
    Ok(head
        .trim()
        .strip_prefix("ref: refs/heads/")
        .filter(|branch| {
            !branch.is_empty() && branch.len() <= 256 && !branch.chars().any(char::is_control)
        })
        .map(str::to_owned))
}

fn count_worktrees(directory: &Path) -> usize {
    let Ok(metadata) = fs::symlink_metadata(directory) else {
        return 0;
    };
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return 0;
    }
    fs::read_dir(directory)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .filter(|entry| {
            entry
                .file_type()
                .map(|kind| kind.is_dir() && !kind.is_symlink())
                .unwrap_or(false)
        })
        .count()
}

fn stable_id(path: &Path) -> String {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in path.to_string_lossy().as_bytes() {
        hash = (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3);
    }
    format!("workspace-{hash:016x}")
}

pub fn canonical_root(path: &Path) -> io::Result<PathBuf> {
    let canonical = fs::canonicalize(path)?;
    if !canonical.is_dir() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "workspace root must be a directory",
        ));
    }
    Ok(canonical)
}
