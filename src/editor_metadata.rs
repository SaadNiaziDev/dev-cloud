use crate::safe_file::read_bounded_regular;
use serde::Serialize;
use std::{
    io,
    path::{Path, PathBuf},
};

const MAX_SETTINGS_BYTES: u64 = 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct EditorSetting {
    pub application: String,
    pub key: String,
    pub value: String,
}

pub fn known_settings_paths() -> Vec<(PathBuf, &'static str)> {
    let mut paths = Vec::new();
    #[cfg(target_os = "macos")]
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
        paths.push((
            home.join("Library/Application Support/Code/User/settings.json"),
            "VS Code",
        ));
        paths.push((
            home.join("Library/Application Support/Cursor/User/settings.json"),
            "Cursor",
        ));
    }
    #[cfg(target_os = "windows")]
    if let Some(appdata) = std::env::var_os("APPDATA").map(PathBuf::from) {
        paths.push((appdata.join("Code/User/settings.json"), "VS Code"));
        paths.push((appdata.join("Cursor/User/settings.json"), "Cursor"));
    }
    paths
}

pub fn inspect_known_settings() -> (Vec<EditorSetting>, bool) {
    let mut settings = Vec::new();
    let mut warning = false;
    for (path, application) in known_settings_paths() {
        match inspect_settings(&path, application) {
            Ok(entries) => settings.extend(entries),
            Err(_) => warning = true,
        }
    }
    (settings, warning)
}

pub fn inspect_settings(path: &Path, application: &str) -> io::Result<Vec<EditorSetting>> {
    let Some(contents) = read_bounded_regular(path, MAX_SETTINGS_BYTES)? else {
        return Ok(Vec::new());
    };
    let Ok(document) = serde_json::from_slice::<serde_json::Value>(&contents) else {
        return Ok(Vec::new());
    };
    let mut settings = Vec::new();
    for key in [
        "editor.tabSize",
        "editor.insertSpaces",
        "editor.wordWrap",
        "files.autoSave",
        "editor.fontSize",
    ] {
        if let Some(value) = document
            .get(key)
            .and_then(|value| allowed_value(key, value))
        {
            settings.push(EditorSetting {
                application: application.to_owned(),
                key: key.to_owned(),
                value,
            });
        }
    }
    if let Some(value) = document
        .get("editor.minimap.enabled")
        .and_then(|value| allowed_value("editor.minimap.enabled", value))
    {
        settings.push(EditorSetting {
            application: application.to_owned(),
            key: "editor.minimap.enabled".to_owned(),
            value,
        });
    }
    Ok(settings)
}

fn allowed_value(key: &str, value: &serde_json::Value) -> Option<String> {
    match key {
        "editor.tabSize" => value
            .as_u64()
            .filter(|n| (1..=8).contains(n))
            .map(|n| n.to_string()),
        "editor.fontSize" => value
            .as_u64()
            .filter(|n| (6..=40).contains(n))
            .map(|n| n.to_string()),
        "editor.insertSpaces" | "editor.minimap.enabled" => value.as_bool().map(|v| v.to_string()),
        "editor.wordWrap" => value
            .as_str()
            .filter(|v| matches!(*v, "off" | "on" | "wordWrapColumn" | "bounded"))
            .map(str::to_owned),
        "files.autoSave" => value
            .as_str()
            .filter(|v| {
                matches!(
                    *v,
                    "off" | "afterDelay" | "onFocusChange" | "onWindowChange"
                )
            })
            .map(str::to_owned),
        _ => None,
    }
}
