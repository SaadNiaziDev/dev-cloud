#![cfg(target_os = "macos")]

use devcloud_agent::discovery::{scan, scan_with_progress, ScanPaths};
use std::{fs, path::Path};

fn paths(root: &Path) -> ScanPaths {
    ScanPaths {
        home: Some(root.join("home")),
        path: vec![root.join("bin")],
        brew_prefixes: vec![root.join("brew")],
        system_version: root.join("system.plist"),
        application_dirs: vec![root.join("Applications")],
    }
}

#[test]
fn inventories_versions_and_redacts_paths() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    fs::create_dir_all(root.join("brew/Cellar/node/22.1.0")).unwrap();
    fs::create_dir_all(root.join("brew/Cellar/node/24.0.0")).unwrap();
    fs::create_dir_all(root.join("home/.pyenv/versions/3.12.1")).unwrap();
    fs::create_dir_all(root.join("home/.vscode/extensions/acme.example-1.2.3")).unwrap();
    fs::create_dir_all(root.join("bin")).unwrap();
    fs::write(root.join("bin/git"), "do not execute").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(root.join("bin/git"), fs::Permissions::from_mode(0o755)).unwrap();
    }
    let report = scan(&paths(root), false);
    assert_eq!(
        report
            .resources
            .iter()
            .filter(|r| r.canonical_tool_id == "nodejs")
            .count(),
        2
    );
    assert!(report
        .resources
        .iter()
        .any(|r| r.canonical_tool_id == "python" && r.version.as_deref() == Some("3.12.1")));
    assert!(report
        .resources
        .iter()
        .any(|r| r.canonical_tool_id == "vscode-extension:acme.example"));
    assert!(report
        .resources
        .iter()
        .any(|r| r.canonical_tool_id == "git" && r.version.is_none()));
    let json = serde_json::to_string(&report).unwrap();
    assert!(!json.contains(root.to_str().unwrap()));
    assert!(report.warnings.iter().any(|w| w.contains("macOS version")));
    let explicit = scan(&paths(root), true);
    assert!(explicit
        .resources
        .iter()
        .any(|r| r.installation_path.is_some()));
}

#[test]
fn scan_reports_progress_from_start_through_completion() {
    let temp = tempfile::tempdir().unwrap();
    let mut events = Vec::new();
    scan_with_progress(&paths(temp.path()), false, |event| {
        events.push(event.message)
    });
    assert_eq!(events.first(), Some(&"Preparing local scan"));
    assert!(events.contains(&"Reading package manager inventory"));
    assert!(events.contains(&"Checking executable locations"));
    assert_eq!(events.last(), Some(&"Scan complete"));
}

#[test]
fn repeated_scans_are_ordered_and_missing_sources_are_safe() {
    let temp = tempfile::tempdir().unwrap();
    let first = scan(&paths(temp.path()), false);
    let second = scan(&paths(temp.path()), false);
    assert_eq!(first.resources, second.resources);
    assert_eq!(first.warnings, second.warnings);
}

#[test]
fn reads_only_version_from_system_and_editor_plists() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let app = root.join("Applications/Visual Studio Code.app/Contents");
    fs::create_dir_all(&app).unwrap();
    fs::write(root.join("system.plist"), "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>ProductVersion</key><string>14.7</string></dict></plist>").unwrap();
    fs::write(app.join("Info.plist"), "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleShortVersionString</key><string>1.90</string></dict></plist>").unwrap();
    let report = scan(&paths(root), false);
    assert_eq!(report.host.os_version.as_deref(), Some("14.7"));
    assert!(report
        .resources
        .iter()
        .any(|r| r.canonical_tool_id == "vscode" && r.version.as_deref() == Some("1.90")));
}

#[cfg(unix)]
#[test]
fn path_and_managed_version_are_one_installation() {
    use std::os::unix::fs::{symlink, PermissionsExt};
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let managed_bin = root.join("home/.nvm/versions/node/v22.1.0/bin");
    fs::create_dir_all(&managed_bin).unwrap();
    fs::create_dir_all(root.join("bin")).unwrap();
    fs::write(managed_bin.join("node"), "must not execute").unwrap();
    fs::set_permissions(managed_bin.join("node"), fs::Permissions::from_mode(0o755)).unwrap();
    symlink(managed_bin.join("node"), root.join("bin/node")).unwrap();
    let report = scan(&paths(root), false);
    let nodes: Vec<_> = report
        .resources
        .iter()
        .filter(|r| r.canonical_tool_id == "nodejs")
        .collect();
    assert_eq!(nodes.len(), 1);
    assert_eq!(nodes[0].version.as_deref(), Some("22.1.0"));
    assert!(nodes[0]
        .evidence
        .iter()
        .any(|e| e == "executable present on PATH"));
}

#[test]
fn reports_match_the_published_json_schema() {
    let temp = tempfile::tempdir().unwrap();
    fs::create_dir_all(temp.path().join("brew/Cellar/git/2.45.0")).unwrap();
    let schema: serde_json::Value =
        serde_json::from_str(include_str!("../schema/resource-schema-v1.json")).unwrap();
    for include_paths in [false, true] {
        let report = serde_json::to_value(scan(&paths(temp.path()), include_paths)).unwrap();
        if let Err(error) = jsonschema::validate(&schema, &report) {
            panic!("report violates schema: {error}");
        }
    }
}

#[cfg(unix)]
#[test]
fn discovered_executable_is_never_run() {
    use std::os::unix::fs::PermissionsExt;
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    fs::create_dir_all(root.join("bin")).unwrap();
    let marker = root.join("executed");
    let executable = root.join("bin/git");
    fs::write(
        &executable,
        format!("#!/bin/sh\ntouch '{}'\n", marker.display()),
    )
    .unwrap();
    fs::set_permissions(&executable, fs::Permissions::from_mode(0o755)).unwrap();
    let report = scan(&paths(root), false);
    assert!(report
        .resources
        .iter()
        .any(|r| r.canonical_tool_id == "git"));
    assert!(!marker.exists());
}

#[test]
fn cli_rejects_invalid_options_without_scanning() {
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_devcloud-agent"))
        .args(["scan", "--format", "invalid"])
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("--format supports json"));
}

#[cfg(unix)]
#[test]
fn package_version_is_not_attributed_to_a_different_tool() {
    use std::os::unix::fs::{symlink, PermissionsExt};
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let keg = root.join("brew/Cellar/node@24/24.14.1_1");
    fs::create_dir_all(keg.join("bin")).unwrap();
    fs::create_dir_all(root.join("bin")).unwrap();
    for name in ["node", "npm"] {
        fs::write(keg.join("bin").join(name), "do not execute").unwrap();
        fs::set_permissions(
            keg.join("bin").join(name),
            fs::Permissions::from_mode(0o755),
        )
        .unwrap();
        symlink(keg.join("bin").join(name), root.join("bin").join(name)).unwrap();
    }
    let report = scan(&paths(root), false);
    let node: Vec<_> = report
        .resources
        .iter()
        .filter(|r| r.canonical_tool_id == "nodejs")
        .collect();
    assert_eq!(node.len(), 1);
    assert_eq!(node[0].version.as_deref(), Some("24.14.1"));
    assert_eq!(node[0].display_name, "Node.js");
    let npm = report
        .resources
        .iter()
        .find(|r| r.canonical_tool_id == "npm")
        .unwrap();
    assert_eq!(npm.version, None);
    assert_eq!(npm.provider_package_id.as_deref(), Some("node@24"));
}

#[cfg(unix)]
#[test]
fn path_order_is_recorded_without_claiming_other_versions_are_inactive() {
    use devcloud_agent::model::PathStatus;
    use std::os::unix::fs::PermissionsExt;
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let mut config = paths(root);
    config.path = vec![root.join("first"), root.join("second")];
    for dir in &config.path {
        fs::create_dir_all(dir).unwrap();
        fs::write(dir.join("git"), "not executed").unwrap();
        fs::set_permissions(dir.join("git"), fs::Permissions::from_mode(0o755)).unwrap();
    }
    let report = scan(&config, true);
    let first = report
        .resources
        .iter()
        .find(|r| {
            r.installation_path
                .as_deref()
                .is_some_and(|p| p.contains("/first/"))
        })
        .unwrap();
    let second = report
        .resources
        .iter()
        .find(|r| {
            r.installation_path
                .as_deref()
                .is_some_and(|p| p.contains("/second/"))
        })
        .unwrap();
    assert_eq!(first.path_status, Some(PathStatus::FirstOnPath));
    assert_eq!(second.path_status, Some(PathStatus::AlsoOnPath));
}

#[cfg(unix)]
#[test]
fn npm_version_comes_from_its_manifest_not_the_node_package() {
    use std::os::unix::fs::{symlink, PermissionsExt};
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let package = root.join("brew/Cellar/node/24.1.0/lib/node_modules/npm");
    fs::create_dir_all(package.join("bin")).unwrap();
    fs::create_dir_all(root.join("bin")).unwrap();
    fs::write(
        package.join("package.json"),
        r#"{"name":"npm","version":"11.4.2","private":"ignored"}"#,
    )
    .unwrap();
    fs::write(package.join("bin/npm-cli.js"), "not executed").unwrap();
    fs::set_permissions(
        package.join("bin/npm-cli.js"),
        fs::Permissions::from_mode(0o755),
    )
    .unwrap();
    symlink(package.join("bin/npm-cli.js"), root.join("bin/npm")).unwrap();
    let report = scan(&paths(root), false);
    let npm = report
        .resources
        .iter()
        .find(|r| r.canonical_tool_id == "npm")
        .unwrap();
    assert_eq!(npm.version.as_deref(), Some("11.4.2"));
    assert!(npm.evidence.iter().any(|e| e == "npm package metadata"));
    assert!(!serde_json::to_string(&report).unwrap().contains("ignored"));
    fs::write(package.join("package.json"), "{invalid").unwrap();
    let invalid = scan(&paths(root), false);
    assert_eq!(
        invalid
            .resources
            .iter()
            .find(|r| r.canonical_tool_id == "npm")
            .unwrap()
            .version,
        None
    );
}

#[cfg(unix)]
#[test]
fn pip_version_requires_matching_local_interpreter_and_unambiguous_metadata() {
    use std::os::unix::fs::PermissionsExt;
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let prefix = root.join("python");
    let bin = prefix.join("bin");
    let metadata = prefix.join("lib/python3.12/site-packages/pip-24.1.dist-info");
    fs::create_dir_all(&bin).unwrap();
    fs::create_dir_all(&metadata).unwrap();
    fs::write(bin.join("python3"), "not executed").unwrap();
    fs::write(
        bin.join("pip3"),
        format!("#!{}\nnot executed", bin.join("python3").display()),
    )
    .unwrap();
    fs::set_permissions(bin.join("pip3"), fs::Permissions::from_mode(0o755)).unwrap();
    fs::write(
        metadata.join("METADATA"),
        "Name: pip\nVersion: 24.1\nOther: ignored\n\nbody ignored",
    )
    .unwrap();
    let mut config = paths(root);
    config.path = vec![bin.clone()];
    let report = scan(&config, false);
    let pip = report
        .resources
        .iter()
        .find(|r| r.canonical_tool_id == "pip")
        .unwrap();
    assert_eq!(pip.version.as_deref(), Some("24.1"));
    assert!(!serde_json::to_string(&report).unwrap().contains("ignored"));
    fs::write(bin.join("pip3"), "#!/usr/bin/env python3\nnot executed").unwrap();
    let report = scan(&config, false);
    assert_eq!(
        report
            .resources
            .iter()
            .find(|r| r.canonical_tool_id == "pip")
            .unwrap()
            .version,
        None
    );
}

#[cfg(target_os = "macos")]
#[test]
fn opening_without_arguments_starts_a_scan() {
    let home = tempfile::tempdir().unwrap();
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_devcloud-agent"))
        .env("HOME", home.path())
        .env("PATH", "")
        .output()
        .unwrap();
    assert!(output.status.success());
    assert!(String::from_utf8_lossy(&output.stdout).starts_with("macos "));
    assert!(output.stderr.is_empty());
}

#[cfg(unix)]
#[test]
fn reports_node_manager_provenance_and_pnpm_version() {
    use std::os::unix::fs::{symlink, PermissionsExt};
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let package = root.join("home/.nvm/versions/node/v22.0.0/lib/node_modules/pnpm");
    fs::create_dir_all(package.join("bin")).unwrap();
    fs::create_dir_all(root.join("bin")).unwrap();
    fs::write(
        package.join("package.json"),
        r#"{"name":"pnpm","version":"10.3.0"}"#,
    )
    .unwrap();
    fs::write(package.join("bin/pnpm.cjs"), "not executed").unwrap();
    fs::set_permissions(
        package.join("bin/pnpm.cjs"),
        fs::Permissions::from_mode(0o755),
    )
    .unwrap();
    symlink(package.join("bin/pnpm.cjs"), root.join("bin/pnpm")).unwrap();
    let report = scan(&paths(root), false);
    let pnpm = report
        .resources
        .iter()
        .find(|r| r.canonical_tool_id == "pnpm")
        .unwrap();
    assert_eq!(pnpm.version.as_deref(), Some("10.3.0"));
    assert_eq!(pnpm.installation_provider.as_deref(), Some("nvm"));
    assert!(pnpm
        .evidence
        .iter()
        .any(|e| e == "executable in version manager directory"));
}

#[test]
fn ignores_relative_path_entries() {
    let temp = tempfile::tempdir().unwrap();
    let mut config = paths(temp.path());
    config.path = vec![".".into(), "bin".into()];
    let report = scan(&config, false);
    assert!(report.resources.is_empty());
    assert!(report
        .warnings
        .iter()
        .any(|w| w == "Skipped a relative PATH entry"));
}

#[test]
fn reads_platform_suffixed_extension_names() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    fs::create_dir_all(root.join("home/.vscode/extensions/acme.my-extension-1.2.3-darwin-arm64"))
        .unwrap();
    fs::create_dir_all(root.join("home/.vscode/extensions/acme.other-2.3.4-beta.1")).unwrap();
    let report = scan(&paths(root), false);
    let extension = report
        .resources
        .iter()
        .find(|r| r.canonical_tool_id == "vscode-extension:acme.my-extension")
        .unwrap();
    assert_eq!(extension.version.as_deref(), Some("1.2.3"));
    assert!(report
        .resources
        .iter()
        .any(|r| r.canonical_tool_id == "vscode-extension:acme.other"
            && r.version.as_deref() == Some("2.3.4-beta.1")));
}

#[test]
fn focused_tool_filter_keeps_known_tools_and_excludes_libraries() {
    use devcloud_agent::discovery::is_developer_tool;
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    for package in ["node@24", "git", "openssl@3", "postgresql@16"] {
        fs::create_dir_all(root.join("brew/Cellar").join(package).join("1.2.3")).unwrap();
    }
    let report = scan(&paths(root), false);
    let selected: Vec<_> = report
        .resources
        .iter()
        .filter(|r| is_developer_tool(r))
        .map(|r| r.canonical_tool_id.as_str())
        .collect();
    assert!(selected.contains(&"nodejs"));
    assert!(selected.contains(&"git"));
    assert!(selected.contains(&"postgresql@16"));
    assert!(!selected.contains(&"openssl@3"));
}

#[cfg(target_os = "macos")]
#[test]
fn cli_filters_tools_and_includes_requested_paths() {
    use std::os::unix::fs::PermissionsExt;
    let temp = tempfile::tempdir().unwrap();
    let home = temp.path().join("home");
    let bin = temp.path().join("bin");
    fs::create_dir_all(home.join(".vscode/extensions/acme.test-1.0.0")).unwrap();
    fs::create_dir_all(&bin).unwrap();
    fs::write(bin.join("git"), "not executed").unwrap();
    fs::set_permissions(bin.join("git"), fs::Permissions::from_mode(0o755)).unwrap();
    let run = |args: &[&str]| {
        std::process::Command::new(env!("CARGO_BIN_EXE_devcloud-agent"))
            .args(args)
            .env("HOME", &home)
            .env("PATH", &bin)
            .output()
            .unwrap()
    };
    let filtered = run(&["scan", "--tools", "--format", "json"]);
    assert!(filtered.status.success());
    let report: serde_json::Value = serde_json::from_slice(&filtered.stdout).unwrap();
    let resources = report["resources"].as_array().unwrap();
    assert!(resources.iter().any(|r| r["canonical_tool_id"] == "git"));
    assert!(!resources.iter().any(|r| r["kind"] == "editor_extension"));
    let paths = run(&["scan", "--tools", "--include-paths"]);
    assert!(paths.status.success());
    assert!(String::from_utf8_lossy(&paths.stdout).contains(bin.to_str().unwrap()));
}

#[test]
fn help_explains_scan_options() {
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_devcloud-agent"))
        .arg("--help")
        .output()
        .unwrap();
    assert!(output.status.success());
    assert!(String::from_utf8_lossy(&output.stdout).contains("--tools"));
}

#[cfg(unix)]
#[test]
fn xcode_and_apple_tools_use_bundle_metadata_without_execution() {
    use std::os::unix::fs::PermissionsExt;
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let app = root.join("Applications/Xcode.app");
    let developer_bin = app.join("Contents/Developer/usr/bin");
    fs::create_dir_all(&developer_bin).unwrap();
    fs::write(app.join("Contents/Info.plist"), "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleShortVersionString</key><string>26.2</string></dict></plist>").unwrap();
    for tool in ["swift", "xcodebuild"] {
        fs::write(developer_bin.join(tool), "must not execute").unwrap();
        fs::set_permissions(developer_bin.join(tool), fs::Permissions::from_mode(0o755)).unwrap();
    }
    let mut config = paths(root);
    config.path = vec![developer_bin];
    let report = scan(&config, false);
    let xcode = report
        .resources
        .iter()
        .find(|r| r.canonical_tool_id == "xcode")
        .unwrap();
    assert_eq!(xcode.version.as_deref(), Some("26.2"));
    for tool in ["swift", "xcodebuild"] {
        let resource = report
            .resources
            .iter()
            .find(|r| r.canonical_tool_id == tool)
            .unwrap();
        assert_eq!(resource.version.as_deref(), Some("26.2"));
        assert_eq!(resource.installation_provider.as_deref(), Some("xcode"));
    }
}

#[test]
fn help_points_to_the_desktop_application() {
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_devcloud-agent"))
        .args(["--help"])
        .output()
        .unwrap();
    assert!(output.status.success());
    let text = String::from_utf8_lossy(&output.stdout);
    assert!(text.contains("DevCloud.app"));
    assert!(text.contains("macOS"));
}
