use continuity_agent::workspace::{canonical_root, inspect};
use std::{fs, path::Path};

#[test]
fn reads_branch_and_worktree_count_without_reading_remote_urls() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("project");
    let git = root.join(".git");
    fs::create_dir_all(git.join("worktrees/linked-one")).unwrap();
    fs::create_dir_all(git.join("worktrees/linked-two")).unwrap();
    fs::write(git.join("HEAD"), "ref: refs/heads/feature/local-index\n").unwrap();
    fs::write(
        git.join("config"),
        "[remote \"origin\"]\nurl = https://user:secret@example.invalid/repo.git\n",
    )
    .unwrap();

    let entry = inspect(&root, false).unwrap().unwrap();
    let encoded = format!("{entry:?}");
    assert_eq!(entry.branch.as_deref(), Some("feature/local-index"));
    assert_eq!(entry.linked_worktree_count, 2);
    assert!(entry.path.is_none());
    assert!(!encoded.contains(&root.to_string_lossy().to_string()));
    assert!(!encoded.contains("secret"));
    assert!(!encoded.contains("example.invalid"));

    let visible_path = inspect(&root, true).unwrap().unwrap();
    let canonical_root = fs::canonicalize(&root).unwrap();
    assert_eq!(
        visible_path.path.as_deref(),
        Some(canonical_root.to_str().unwrap())
    );
}

#[test]
fn identifies_linked_worktree_without_following_gitdir_pointer() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("linked");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join(".git"),
        "gitdir: /outside/approved/root/.git/worktrees/linked\n",
    )
    .unwrap();

    let entry = inspect(&root, false).unwrap().unwrap();
    assert!(entry.is_linked_worktree);
    assert_eq!(entry.branch, None);
    assert_eq!(entry.linked_worktree_count, 0);
}

#[test]
fn skips_non_repositories() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("not-a-project");
    fs::create_dir_all(&root).unwrap();
    assert!(inspect(&root, false).unwrap().is_none());
    assert!(canonical_root(Path::new(".")).unwrap().is_dir());
    fs::write(root.join(".git"), "not a git pointer\n").unwrap();
    assert!(inspect(&root, false).unwrap().is_none());
}

#[test]
fn rejects_invalid_branch_metadata() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("project");
    let git = root.join(".git");
    fs::create_dir_all(&git).unwrap();
    fs::write(git.join("HEAD"), "ref: refs/heads/private\u{0000}value\n").unwrap();
    let workspace = inspect(&root, false).unwrap().unwrap();
    assert!(workspace.branch.is_none());
}

#[cfg(unix)]
#[test]
fn skips_git_metadata_symlink() {
    use std::os::unix::fs::symlink;

    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("symlinked-project");
    let outside = temp.path().join("outside.git");
    fs::create_dir_all(&root).unwrap();
    fs::create_dir_all(&outside).unwrap();
    fs::write(outside.join("HEAD"), "ref: refs/heads/private\n").unwrap();
    symlink(outside, root.join(".git")).unwrap();
    assert!(inspect(&root, true).unwrap().is_none());
}
