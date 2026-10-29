use devcloud_agent::mcp_metadata::inspect_config;
use std::fs;

#[test]
fn extracts_only_allowlisted_server_metadata() {
    let directory = tempfile::tempdir().unwrap();
    let config = directory.path().join("mcp.json");
    fs::write(
        &config,
        r#"{
          "mcpServers": {
            "local-files": {
              "command": "/opt/private/bin/node",
              "args": ["SECRET_ARGUMENT_SENTINEL"],
              "env": {"TOKEN": "SECRET_ENV_SENTINEL"}
            },
            "remote": {
              "type": "http",
              "url": "https://secret.example/path?token=SECRET_URL_SENTINEL",
              "headers": {"Authorization": "SECRET_HEADER_SENTINEL"}
            },
            "unsupported": {"args": ["SECRET_ONLY_ARGS"]},
            "malformed-command": {"command": "node --token SECRET_COMMAND_SENTINEL"},
            "malformed-token-name": {"command": "--token=SECRET_EXECUTABLE_SENTINEL"}
          }
        }"#,
    )
    .unwrap();

    let servers = inspect_config(&config, "Cursor").unwrap();
    assert_eq!(servers.len(), 4);
    assert_eq!(servers[0].name, "local-files");
    assert_eq!(servers[0].transport, "stdio");
    assert_eq!(servers[0].executable.as_deref(), Some("node"));
    let remote = servers
        .iter()
        .find(|server| server.name == "remote")
        .unwrap();
    assert_eq!(remote.transport, "http");
    assert_eq!(remote.executable, None);
    let malformed = servers
        .iter()
        .find(|server| server.name == "malformed-command")
        .unwrap();
    assert_eq!(malformed.executable, None);
    let malformed_name = servers
        .iter()
        .find(|server| server.name == "malformed-token-name")
        .unwrap();
    assert_eq!(malformed_name.executable, None);
    assert!(servers
        .iter()
        .all(|server| server.config_source == "Cursor"));
    let output = format!("{servers:?}");
    for secret in [
        "SECRET_ARGUMENT_SENTINEL",
        "SECRET_ENV_SENTINEL",
        "SECRET_URL_SENTINEL",
        "SECRET_HEADER_SENTINEL",
        "SECRET_COMMAND_SENTINEL",
        "SECRET_EXECUTABLE_SENTINEL",
        "secret.example",
    ] {
        assert!(!output.contains(secret));
    }
}

#[test]
fn ignores_invalid_and_oversized_configurations() {
    let directory = tempfile::tempdir().unwrap();
    let config = directory.path().join("mcp.json");
    fs::write(&config, b"not json").unwrap();
    assert!(inspect_config(&config, "Cursor").unwrap().is_empty());
    fs::write(&config, vec![b' '; 1024 * 1024 + 1]).unwrap();
    assert!(inspect_config(&config, "Cursor").unwrap().is_empty());
}

#[cfg(unix)]
#[test]
fn ignores_symlinked_configuration() {
    use std::os::unix::fs::symlink;
    let directory = tempfile::tempdir().unwrap();
    let source = directory.path().join("source.json");
    let link = directory.path().join("mcp.json");
    fs::write(&source, r#"{"mcpServers":{"x":{"command":"node"}}}"#).unwrap();
    symlink(source, &link).unwrap();
    assert!(inspect_config(&link, "Cursor").unwrap().is_empty());
}
