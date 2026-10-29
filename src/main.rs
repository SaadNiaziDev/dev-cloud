use devcloud_agent::{
    discovery::{curated_command_names, is_developer_tool, scan, scan_with_progress, ScanPaths},
    editor_metadata::{self, EditorSetting},
    history::{self, Changes},
    mcp_metadata::{self, McpServer},
    model::Report,
    path_extras::{self, PathExecutable},
    workspace::{self, Workspace},
};
use serde::Serialize;
use std::{
    env,
    fs::OpenOptions,
    io::{self, Write},
    path::PathBuf,
    process::ExitCode,
};

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("{message}");
            ExitCode::from(2)
        }
    }
}

fn run() -> Result<(), String> {
    let mut args = env::args().skip(1);
    let command = args.next().unwrap_or_else(|| "scan".to_owned());
    if command == "--help" || command == "help" {
        print_help();
        return Ok(());
    }
    if command == "doctor" {
        if args.next().is_some() {
            return Err("doctor takes no options".into());
        }
        println!(
            "platform: {}\narchitecture: {}",
            env::consts::OS,
            env::consts::ARCH
        );
        return Ok(());
    }
    if command != "scan" {
        return Err(format!("unknown command: {command}"));
    }
    let mut json = false;
    let mut include_paths = false;
    let mut tools_only = false;
    let mut show_progress = false;
    let mut include_local = false;
    let mut inspect_mcp = false;
    let mut inspect_editor_settings = false;
    let mut inspect_path_tools = false;
    let mut approved_roots = Vec::new();
    let mut history_dir = None;
    let mut output = None;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--help" => {
                print_help();
                return Ok(());
            }
            "--format" => {
                if args.next().as_deref() != Some("json") {
                    return Err("--format supports json".into());
                }
                json = true;
            }
            "--include-paths" => include_paths = true,
            "--tools" => tools_only = true,
            "--progress" => show_progress = true,
            "--local" => include_local = true,
            "--inspect-mcp" => inspect_mcp = true,
            "--inspect-editor-settings" => inspect_editor_settings = true,
            "--inspect-path-tools" => inspect_path_tools = true,
            "--approved-root" => {
                let path = args.next().ok_or("--approved-root requires a path")?;
                approved_roots.push(PathBuf::from(path));
            }
            "--history-dir" => {
                let path = args.next().ok_or("--history-dir requires a path")?;
                history_dir = Some(PathBuf::from(path));
            }
            "--output" => output = Some(args.next().ok_or("--output requires a path")?),
            _ => return Err(format!("unknown option: {arg}")),
        }
    }
    if include_local && !json {
        return Err("--local requires --format json".into());
    }
    if !include_local
        && (inspect_mcp
            || inspect_editor_settings
            || inspect_path_tools
            || !approved_roots.is_empty()
            || history_dir.is_some())
    {
        return Err("local metadata options require --local".into());
    }
    let paths = ScanPaths::current();
    let mut report = if show_progress {
        scan_with_progress(&paths, include_paths, |progress| {
            eprintln!(
                "DEVCLOUD_PROGRESS|{}|{}|{}",
                progress.completed, progress.total, progress.message
            );
        })
    } else {
        scan(&paths, include_paths)
    };
    if tools_only {
        report.resources.retain(is_developer_tool);
    }
    let local = if include_local {
        Some(inspect_local_metadata(
            &paths,
            &approved_roots,
            include_paths,
            inspect_mcp,
            inspect_editor_settings,
            inspect_path_tools,
            show_progress,
        ))
    } else {
        None
    };
    let (changes, history_error) = match &history_dir {
        Some(dir) => match history::record(dir, &report) {
            Ok(changes) => (changes, false),
            Err(_) => (None, true),
        },
        None => (None, false),
    };
    let text = if json && include_local {
        serde_json::to_string_pretty(&ScanEnvelope {
            report,
            local,
            changes,
            history_error,
        })
        .map_err(|e| e.to_string())?
    } else if json {
        serde_json::to_string_pretty(&report).map_err(|e| e.to_string())?
    } else {
        let mut text = format!(
            "{} {} ({})\n",
            report.host.platform,
            report.host.os_version.as_deref().unwrap_or("unknown"),
            report.host.architecture
        );
        for item in &report.resources {
            text.push_str(&format!(
                "{}  {}  {}{}{}\n",
                item.display_name,
                item.version.as_deref().unwrap_or("version unknown"),
                item.installation_provider
                    .as_deref()
                    .unwrap_or("source unknown"),
                match item.path_status {
                    Some(devcloud_agent::model::PathStatus::FirstOnPath) => "  [first on PATH]",
                    Some(devcloud_agent::model::PathStatus::AlsoOnPath) => "  [also on PATH]",
                    None => "",
                },
                item.installation_path
                    .as_ref()
                    .map(|p| format!("  {p}"))
                    .unwrap_or_default()
            ));
        }
        for warning in &report.warnings {
            text.push_str(&format!("Warning: {warning}\n"));
        }
        text
    };
    if let Some(path) = output {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
            .map_err(|e| e.to_string())?;
        writeln!(file, "{text}").map_err(|e| e.to_string())?;
    } else {
        writeln!(io::stdout(), "{text}").map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[derive(Serialize)]
struct ScanEnvelope {
    report: Report,
    local: Option<LocalMetadata>,
    changes: Option<Changes>,
    history_error: bool,
}

#[derive(Serialize)]
struct LocalMetadata {
    workspaces: Vec<Workspace>,
    workspace_warnings: Vec<String>,
    mcp_servers: Vec<McpServer>,
    mcp_warning: bool,
    editor_settings: Vec<EditorSetting>,
    editor_warning: bool,
    unknown_path_tools: Vec<PathExecutable>,
}

fn inspect_local_metadata(
    paths: &ScanPaths,
    approved_roots: &[PathBuf],
    include_paths: bool,
    inspect_mcp: bool,
    inspect_editor_settings: bool,
    inspect_path_tools: bool,
    show_progress: bool,
) -> LocalMetadata {
    if show_progress {
        eprintln!("DEVCLOUD_PROGRESS|0|0|Checking approved workspaces");
    }
    let mut workspaces = Vec::new();
    let mut workspace_warnings = Vec::new();
    for root in approved_roots {
        match workspace::inspect(root, include_paths) {
            Ok(Some(entry)) => workspaces.push(entry),
            Ok(None) => {}
            Err(_) => workspace_warnings
                .push("Some approved workspace metadata could not be read".to_owned()),
        }
    }
    if show_progress {
        eprintln!("DEVCLOUD_PROGRESS|0|0|Inspecting optional MCP metadata");
    }
    let (mcp_servers, mcp_warning) = if inspect_mcp {
        mcp_metadata::inspect_known_configs()
    } else {
        (Vec::new(), false)
    };
    if show_progress {
        eprintln!("DEVCLOUD_PROGRESS|0|0|Inspecting optional editor preferences");
    }
    let (editor_settings, editor_warning) = if inspect_editor_settings {
        editor_metadata::inspect_known_settings()
    } else {
        (Vec::new(), false)
    };
    if show_progress {
        eprintln!("DEVCLOUD_PROGRESS|0|0|Checking optional PATH tools");
    }
    let unknown_path_tools = if inspect_path_tools {
        path_extras::inspect(&paths.path, &curated_command_names())
    } else {
        Vec::new()
    };
    LocalMetadata {
        workspaces,
        workspace_warnings,
        mcp_servers,
        mcp_warning,
        editor_settings,
        editor_warning,
        unknown_path_tools,
    }
}

fn print_help() {
    println!("Usage: devcloud-agent [scan] [--tools] [--format json] [--include-paths] [--progress] [--local] [--output FILE]\n       devcloud-agent doctor\n\n--tools          Show recognized developer tools and editors\n--format json    Output JSON\n--include-paths  Include installation paths\n--progress       Write scan progress to stderr\n--local          Include opt-in local-only metadata (JSON only)\n--history-dir D  Save the scan in D and report changes (needs --local)\n--output FILE    Create a report file\n--help           Show this help\n\nLaunch DevCloud.app (macOS) for the desktop interface.");
}
