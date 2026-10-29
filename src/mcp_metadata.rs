use crate::safe_file::read_bounded_regular;
use serde::Serialize;
use std::{
    io,
    path::{Path, PathBuf},
};

const MAX_CONFIG_BYTES: u64 = 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct McpServer {
    pub name: String,
    pub transport: String,
    pub executable: Option<String>,
    pub config_source: String,
}

pub fn known_config_paths() -> Vec<(PathBuf, &'static str)> {
    let mut paths = Vec::new();
    #[cfg(target_os = "macos")]
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
        paths.push((
            home.join("Library/Application Support/Claude/claude_desktop_config.json"),
            "Claude Desktop",
        ));
        paths.push((home.join(".cursor/mcp.json"), "Cursor"));
    }
    #[cfg(target_os = "windows")]
    {
        if let Some(appdata) = std::env::var_os("APPDATA").map(PathBuf::from) {
            paths.push((
                appdata.join("Claude/claude_desktop_config.json"),
                "Claude Desktop",
            ));
        }
        if let Some(home) = std::env::var_os("USERPROFILE").map(PathBuf::from) {
            paths.push((home.join(".cursor/mcp.json"), "Cursor"));
        }
    }
    paths
}

pub fn inspect_known_configs() -> (Vec<McpServer>, bool) {
    let mut servers = Vec::new();
    let mut warnings = false;
    for (path, source) in known_config_paths() {
        match inspect_config(&path, source) {
            Ok(entries) => servers.extend(entries),
            Err(_) => warnings = true,
        }
    }
    (servers, warnings)
}

pub fn inspect_config(path: &Path, source: &str) -> io::Result<Vec<McpServer>> {
    let Some(contents) = read_bounded_regular(path, MAX_CONFIG_BYTES)? else {
        return Ok(Vec::new());
    };
    let Ok(document) = serde_json::from_slice::<serde_json::Value>(&contents) else {
        return Ok(Vec::new());
    };
    let Some(servers) = document
        .get("mcpServers")
        .and_then(serde_json::Value::as_object)
    else {
        return Ok(Vec::new());
    };
    Ok(servers
        .iter()
        .filter_map(|(name, value)| summarize_server(name, value, source))
        .collect())
}

fn summarize_server(name: &str, value: &serde_json::Value, source: &str) -> Option<McpServer> {
    if name.trim().is_empty() || name.len() > 128 || name.chars().any(char::is_control) {
        return None;
    }
    let object = value.as_object()?;
    let command = object.get("command").and_then(serde_json::Value::as_str);
    let url = object
        .get("url")
        .or_else(|| object.get("serverUrl"))
        .and_then(serde_json::Value::as_str);
    let (transport, executable) = if let Some(command) = command {
        ("stdio".to_owned(), command_basename(command))
    } else if url.is_some() {
        let transport = object
            .get("type")
            .and_then(serde_json::Value::as_str)
            .filter(|kind| matches!(*kind, "http" | "sse"))
            .unwrap_or("remote");
        (transport.to_owned(), None)
    } else {
        return None;
    };
    Some(McpServer {
        name: name.to_owned(),
        transport,
        executable,
        config_source: source.to_owned(),
    })
}

fn command_basename(command: &str) -> Option<String> {
    let path = Path::new(command);
    let basename = path
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .or_else(|| command.rsplit(['/', '\\']).find(|name| !name.is_empty()))?;
    if basename.chars().any(char::is_whitespace)
        || basename.chars().any(char::is_control)
        || basename.len() > 128
        || !basename
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '+' | '-'))
    {
        return None;
    }
    Some(basename.to_owned())
}
