#![cfg(target_os = "windows")]

use devcloud_agent::discovery::{scan, ScanPaths};
use std::{fs, path::Path};

fn paths(root: &Path) -> ScanPaths {
    ScanPaths {
        home: Some(root.join("home")),
        path: vec![root.join("bin")],
        brew_prefixes: vec![],
        system_version: Path::new("").to_path_buf(),
        application_dirs: vec![root.join("Applications/VS Code")],
    }
}

#[test]
fn discovers_windows_path_tools_without_running_them() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    fs::create_dir_all(root.join("bin")).unwrap();
    let marker = root.join("was-executed");
    fs::write(
        root.join("bin/git.cmd"),
        format!("@echo off\r\necho run > {}\r\n", marker.display()),
    )
    .unwrap();
    fs::write(root.join("bin/node.exe"), "not executed").unwrap();

    let report = scan(&paths(root), false);
    assert_eq!(report.host.platform, "windows");
    assert!(report
        .resources
        .iter()
        .any(|resource| resource.canonical_tool_id == "git"));
    assert!(report
        .resources
        .iter()
        .any(|resource| resource.canonical_tool_id == "nodejs"));
    assert!(!marker.exists());
    assert!(!serde_json::to_string(&report)
        .unwrap()
        .contains(&root.to_string_lossy().to_string()));
}

#[test]
fn discovers_editor_version_from_local_metadata() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let editor = root.join("Applications/VS Code");
    fs::create_dir_all(editor.join("resources/app")).unwrap();
    fs::write(editor.join("Code.exe"), "not executed").unwrap();
    fs::write(
        editor.join("resources/app/package.json"),
        r#"{"name":"vscode","version":"1.90.0"}"#,
    )
    .unwrap();
    let report = scan(&paths(root), true);
    let vscode = report
        .resources
        .iter()
        .find(|resource| resource.canonical_tool_id == "vscode")
        .unwrap();
    assert_eq!(vscode.version.as_deref(), Some("1.90.0"));
    assert!(vscode.installation_path.is_some());
}

#[test]
fn cli_help_identifies_desktop_app() {
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_devcloud-agent"))
        .arg("--help")
        .output()
        .unwrap();
    assert!(output.status.success());
    let text = String::from_utf8_lossy(&output.stdout);
    assert!(text.contains("DevCloud.app"));
}

#[test]
fn report_matches_the_shared_schema() {
    let temp = tempfile::tempdir().unwrap();
    let report = serde_json::to_value(scan(&paths(temp.path()), false)).unwrap();
    let schema: serde_json::Value =
        serde_json::from_str(include_str!("../schema/resource-schema-v1.json")).unwrap();
    jsonschema::validate(&schema, &report).expect("Windows report must match schema v1");
}
