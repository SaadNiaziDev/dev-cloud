use continuity_agent::editor_metadata::inspect_settings;
use std::fs;

#[test]
fn extracts_only_validated_preference_allowlist() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("settings.json");
    fs::write(
        &path,
        r#"{
          "editor.tabSize": 4,
          "editor.insertSpaces": true,
          "editor.wordWrap": "bounded",
          "files.autoSave": "afterDelay",
          "editor.fontSize": 14,
          "editor.minimap.enabled": false,
          "window.title": "SECRET_PATH_SENTINEL",
          "extensions": {"secret.extension": {"token": "SECRET_TOKEN"}},
          "editor.lineHeight": 999,
          "editor.tabCompletion": "unexpected"
        }"#,
    )
    .unwrap();
    let settings = inspect_settings(&path, "VS Code").unwrap();
    assert_eq!(settings.len(), 6);
    let output = format!("{settings:?}");
    assert!(!output.contains("SECRET_PATH_SENTINEL"));
    assert!(!output.contains("SECRET_TOKEN"));
    assert!(!output.contains("window.title"));
    assert!(!output.contains("999"));
}

#[cfg(unix)]
#[test]
fn ignores_symlinked_settings_files() {
    use std::os::unix::fs::symlink;
    let directory = tempfile::tempdir().unwrap();
    let source = directory.path().join("source.json");
    let link = directory.path().join("settings.json");
    fs::write(&source, r#"{"editor.tabSize":2}"#).unwrap();
    symlink(source, &link).unwrap();
    assert!(inspect_settings(&link, "Cursor").unwrap().is_empty());
}
