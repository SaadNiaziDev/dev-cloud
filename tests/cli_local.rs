#![cfg(target_os = "macos")]

use serde_json::Value;
use std::fs;

#[test]
fn local_scan_shows_progress_and_redacts_optional_configuration() {
    let temp = tempfile::tempdir().unwrap();
    let home = temp.path().join("home");
    let workspace = temp.path().join("private-workspace");
    let mcp_config = home.join("Library/Application Support/Claude/claude_desktop_config.json");
    let editor_settings = home.join("Library/Application Support/Code/User/settings.json");
    fs::create_dir_all(workspace.join(".git")).unwrap();
    fs::write(workspace.join(".git/HEAD"), "ref: refs/heads/main\n").unwrap();
    fs::create_dir_all(mcp_config.parent().unwrap()).unwrap();
    fs::write(
        &mcp_config,
        r#"{"mcpServers":{"local":{"command":"/private/secret/runner","args":["do-not-show"],"env":{"TOKEN":"private-value"}},"remote":{"url":"https://private.example/secret","headers":{"Authorization":"private-header"}}}}"#,
    )
    .unwrap();
    fs::create_dir_all(editor_settings.parent().unwrap()).unwrap();
    fs::write(
        &editor_settings,
        r#"{"editor.tabSize":2,"files.secretPath":"/private/editor","unknown.private":"discard"}"#,
    )
    .unwrap();

    let output = std::process::Command::new(env!("CARGO_BIN_EXE_continuity-agent"))
        .env("HOME", &home)
        .env("PATH", "")
        .args([
            "scan",
            "--format",
            "json",
            "--progress",
            "--local",
            "--inspect-mcp",
            "--inspect-editor-settings",
            "--approved-root",
        ])
        .arg(&workspace)
        .output()
        .unwrap();
    assert!(output.status.success());
    let json: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["local"]["workspaces"][0]["branch"], "main");
    assert_eq!(json["local"]["mcp_servers"].as_array().unwrap().len(), 2);
    assert_eq!(json["local"]["mcp_servers"][0]["executable"], "runner");
    assert_eq!(json["local"]["editor_settings"][0]["value"], "2");
    let text = String::from_utf8(output.stdout).unwrap();
    assert!(!text.contains(workspace.to_string_lossy().as_ref()));
    assert!(!text.contains("private-value"));
    assert!(!text.contains("private-header"));
    assert!(!text.contains("private.example"));
    assert!(!text.contains("do-not-show"));
    assert!(!text.contains("/private/editor"));
    assert!(String::from_utf8_lossy(&output.stderr).contains("CONTINUITY_PROGRESS|"));
}

#[test]
fn history_dir_reports_changes_after_first_scan() {
    let temp = tempfile::tempdir().unwrap();
    let history = temp.path().join("history");
    let run = || {
        let output = std::process::Command::new(env!("CARGO_BIN_EXE_continuity-agent"))
            .env("HOME", temp.path())
            .env("PATH", "")
            .args(["scan", "--format", "json", "--local", "--history-dir"])
            .arg(&history)
            .output()
            .unwrap();
        assert!(output.status.success());
        serde_json::from_slice::<Value>(&output.stdout).unwrap()
    };
    let first = run();
    assert!(first["changes"].is_null());
    assert_eq!(first["history_error"], false);
    let second = run();
    assert_eq!(second["changes"]["added"].as_array().unwrap().len(), 0);
    assert!(history.join("latest.json").is_file());
}
