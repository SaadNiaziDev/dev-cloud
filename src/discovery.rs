use crate::model::{Host, PathStatus, Report, Resource};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    io::Read,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

#[cfg(target_os = "macos")]
const TOOLS: &[(&str, &str, &str)] = &[
    ("git", "Git", "tool"),
    ("node", "Node.js", "runtime"),
    ("python3", "Python", "runtime"),
    ("brew", "Homebrew", "package_manager"),
    ("npm", "npm", "package_manager"),
    ("pip3", "pip", "package_manager"),
    ("pnpm", "pnpm", "package_manager"),
    ("yarn", "Yarn", "package_manager"),
    ("uv", "uv", "package_manager"),
    ("cargo", "Cargo", "package_manager"),
    ("go", "Go", "runtime"),
    ("docker", "Docker CLI", "tool"),
    ("nvm", "nvm", "version_manager"),
    ("fnm", "fnm", "version_manager"),
    ("volta", "Volta", "version_manager"),
    ("pyenv", "pyenv", "version_manager"),
    ("rustc", "Rust", "runtime"),
    ("bun", "Bun", "runtime"),
    ("java", "Java", "runtime"),
    ("swift", "Swift", "runtime"),
    ("gh", "GitHub CLI", "tool"),
    ("terraform", "Terraform", "tool"),
    ("kubectl", "kubectl", "tool"),
    ("code", "VS Code CLI", "tool"),
    ("cursor", "Cursor CLI", "tool"),
    ("xcodebuild", "Xcode Build Tools", "tool"),
    ("xcrun", "Xcode Tool Runner", "tool"),
    ("clang", "Clang", "tool"),
    ("cmake", "CMake", "tool"),
    ("ninja", "Ninja", "tool"),
    ("make", "Make", "tool"),
];

#[cfg(target_os = "windows")]
const TOOLS: &[(&str, &str, &str)] = &[
    ("git", "Git", "tool"),
    ("node", "Node.js", "runtime"),
    ("python3", "Python", "runtime"),
    ("npm", "npm", "package_manager"),
    ("pip3", "pip", "package_manager"),
    ("pnpm", "pnpm", "package_manager"),
    ("yarn", "Yarn", "package_manager"),
    ("uv", "uv", "package_manager"),
    ("cargo", "Cargo", "package_manager"),
    ("go", "Go", "runtime"),
    ("docker", "Docker CLI", "tool"),
    ("rustc", "Rust", "runtime"),
    ("bun", "Bun", "runtime"),
    ("java", "Java", "runtime"),
    ("gh", "GitHub CLI", "tool"),
    ("terraform", "Terraform", "tool"),
    ("kubectl", "kubectl", "tool"),
    ("code", "VS Code CLI", "tool"),
    ("cursor", "Cursor CLI", "tool"),
    ("cmake", "CMake", "tool"),
    ("ninja", "Ninja", "tool"),
    ("make", "Make", "tool"),
    ("winget", "WinGet", "package_manager"),
    ("choco", "Chocolatey", "package_manager"),
    ("scoop", "Scoop", "package_manager"),
    ("dotnet", ".NET SDK", "runtime"),
    ("wsl", "Windows Subsystem for Linux", "tool"),
];

#[derive(Clone)]
pub struct ScanPaths {
    pub home: Option<PathBuf>,
    pub path: Vec<PathBuf>,
    pub brew_prefixes: Vec<PathBuf>,
    pub system_version: PathBuf,
    pub application_dirs: Vec<PathBuf>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ScanProgress {
    pub message: &'static str,
    pub completed: usize,
    pub total: usize,
}

pub fn curated_command_names() -> Vec<&'static str> {
    TOOLS.iter().map(|(command, _, _)| *command).collect()
}

impl ScanPaths {
    pub fn current() -> Self {
        #[cfg(target_os = "windows")]
        {
            let home = std::env::var_os("USERPROFILE").map(PathBuf::from);
            let local = std::env::var_os("LOCALAPPDATA").map(PathBuf::from);
            let program_files = std::env::var_os("ProgramFiles")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from(r"C:\Program Files"));
            let mut application_dirs = vec![
                program_files.join("Microsoft VS Code"),
                program_files.join("Cursor"),
            ];
            if let Some(local) = &local {
                application_dirs.extend([
                    local.join("Programs/Microsoft VS Code"),
                    local.join("Programs/Cursor"),
                ]);
            }
            return Self {
                home,
                path: std::env::var_os("PATH")
                    .map(|p| std::env::split_paths(&p).collect())
                    .unwrap_or_default(),
                brew_prefixes: Vec::new(),
                system_version: PathBuf::new(),
                application_dirs,
            };
        }
        #[cfg(not(target_os = "windows"))]
        {
            let home = std::env::var_os("HOME").map(PathBuf::from);
            let mut application_dirs = vec![PathBuf::from("/Applications")];
            if let Some(home) = &home {
                application_dirs.push(home.join("Applications"));
            }
            Self {
                home,
                path: std::env::var_os("PATH")
                    .map(|p| std::env::split_paths(&p).collect())
                    .unwrap_or_default(),
                brew_prefixes: vec!["/opt/homebrew".into(), "/usr/local".into()],
                system_version: "/System/Library/CoreServices/SystemVersion.plist".into(),
                application_dirs,
            }
        }
    }
}

pub fn scan(paths: &ScanPaths, include_paths: bool) -> Report {
    scan_with_progress(paths, include_paths, |_| {})
}

pub fn scan_with_progress<F>(paths: &ScanPaths, include_paths: bool, mut progress: F) -> Report
where
    F: FnMut(ScanProgress),
{
    progress(ScanProgress {
        message: "Preparing local scan",
        completed: 0,
        total: 0,
    });
    #[cfg(target_os = "macos")]
    let report = scan_macos(paths, include_paths, &mut progress);
    #[cfg(target_os = "windows")]
    let report = scan_windows(paths, include_paths, &mut progress);
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    let report = unsupported_report();
    progress(ScanProgress {
        message: "Scan complete",
        completed: 1,
        total: 1,
    });
    report
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn unsupported_report() -> Report {
    Report {
        schema_version: 1,
        observed_at_unix_seconds: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs(),
        host: Host {
            platform: std::env::consts::OS,
            architecture: std::env::consts::ARCH,
            os_version: None,
        },
        resources: Vec::new(),
        warnings: vec!["Discovery is supported on macOS and Windows".into()],
    }
}

#[cfg(target_os = "macos")]
fn scan_macos<F>(paths: &ScanPaths, include_paths: bool, progress: &mut F) -> Report
where
    F: FnMut(ScanProgress),
{
    let mut report = Report {
        schema_version: 1,
        observed_at_unix_seconds: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs(),
        host: Host {
            platform: "macos",
            architecture: std::env::consts::ARCH,
            os_version: system_version(&paths.system_version),
        },
        resources: Vec::new(),
        warnings: Vec::new(),
    };
    if report.host.os_version.is_none() {
        report
            .warnings
            .push("Unable to read macOS version metadata".into());
    }
    let mut found = BTreeMap::new();
    progress(ScanProgress {
        message: "Reading package manager inventory",
        completed: 0,
        total: 0,
    });
    for prefix in &paths.brew_prefixes {
        inventory(
            &prefix.join("Cellar"),
            "homebrew_formula",
            include_paths,
            &mut found,
            &mut report.warnings,
        );
        inventory(
            &prefix.join("Caskroom"),
            "homebrew_cask",
            include_paths,
            &mut found,
            &mut report.warnings,
        );
    }
    progress(ScanProgress {
        message: "Checking runtime managers and editor extensions",
        completed: 0,
        total: 0,
    });
    if let Some(home) = &paths.home {
        managed_versions(home, include_paths, &mut found, &mut report.warnings);
        extensions(home, include_paths, &mut found, &mut report.warnings);
    }
    let mut seen_commands = BTreeSet::new();
    let total_path_directories = paths.path.len();
    for (index, dir) in paths.path.iter().enumerate() {
        progress(ScanProgress {
            message: "Checking executable locations",
            completed: index + 1,
            total: total_path_directories,
        });
        if !dir.is_absolute() {
            report.warnings.push("Skipped a relative PATH entry".into());
            continue;
        }
        for &(name, label, kind) in TOOLS {
            let candidate = dir.join(name);
            if is_executable(&candidate) {
                let status = if seen_commands.insert(name) {
                    PathStatus::FirstOnPath
                } else {
                    PathStatus::AlsoOnPath
                };
                let resolved = fs::canonicalize(&candidate).unwrap_or(candidate);
                let known = resolved.ancestors().find_map(|ancestor| {
                    let key = (canonical(name).to_string(), identity(ancestor));
                    found.get_mut(&key).map(|resource: &mut Resource| {
                        mark_path(resource, status);
                    })
                });
                if known.is_some() {
                    continue;
                }
                let (brew_provider, package_id, _) = brew_origin(&resolved, &paths.brew_prefixes);
                let manager_provider = paths
                    .home
                    .as_deref()
                    .and_then(|home| managed_origin(&resolved, home));
                let xcode_version = xcode_origin(&resolved);
                let xcode_provider = xcode_version.as_ref().map(|_| "xcode");
                let provider = brew_provider
                    .or(manager_provider)
                    .or(xcode_provider)
                    .or_else(|| system_origin(&resolved));
                let id = identity(&resolved);
                let key = (canonical(name).to_string(), id.clone());
                if let Some(existing) = found.get_mut(&key) {
                    let existing: &mut Resource = existing;
                    mark_path(existing, status);
                    continue;
                }
                let version = match name {
                    "npm" | "pnpm" | "yarn" => node_package_version(&resolved, name),
                    "pip3" => pip_version(&resolved),
                    _ => xcode_version.clone(),
                };
                let mut evidence = vec!["executable present on PATH".into()];
                if manager_provider.is_some() {
                    evidence.push("executable in version manager directory".into());
                }
                if version.is_some() {
                    evidence.push(format!("{name} package metadata"));
                }
                let resource = Resource {
                    canonical_tool_id: canonical(name).into(),
                    display_name: label.into(),
                    kind: kind.into(),
                    version,
                    installation_provider: provider.map(str::to_owned),
                    provider_package_id: package_id,
                    installation_instance_id: id.clone(),
                    discovery_adapter: "path".into(),
                    evidence,
                    path_status: Some(status),
                    installation_path: path_value(&resolved, include_paths),
                };
                found
                    .entry((resource.canonical_tool_id.clone(), id))
                    .or_insert(resource);
            }
        }
    }
    progress(ScanProgress {
        message: "Finishing inventory",
        completed: 0,
        total: 0,
    });
    editors(paths, include_paths, &mut found);
    report.resources = found.into_values().collect();
    report.normalize();
    report
}

#[cfg(target_os = "windows")]
fn scan_windows<F>(paths: &ScanPaths, include_paths: bool, progress: &mut F) -> Report
where
    F: FnMut(ScanProgress),
{
    let mut report = Report {
        schema_version: 1,
        observed_at_unix_seconds: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs(),
        host: Host {
            platform: "windows",
            architecture: std::env::consts::ARCH,
            os_version: windows_system_version(),
        },
        resources: Vec::new(),
        warnings: Vec::new(),
    };
    if report.host.os_version.is_none() {
        report
            .warnings
            .push("Unable to read Windows version metadata".into());
    }

    let mut found = BTreeMap::new();
    progress(ScanProgress {
        message: "Checking runtime managers and editor extensions",
        completed: 0,
        total: 0,
    });
    if let Some(home) = &paths.home {
        windows_managed_versions(home, include_paths, &mut found, &mut report.warnings);
        extensions(home, include_paths, &mut found, &mut report.warnings);
    }

    let mut seen_commands = BTreeSet::new();
    let total_path_directories = paths.path.len();
    for (index, dir) in paths.path.iter().enumerate() {
        progress(ScanProgress {
            message: "Checking executable locations",
            completed: index + 1,
            total: total_path_directories,
        });
        if !dir.is_absolute() {
            report.warnings.push("Skipped a relative PATH entry".into());
            continue;
        }
        for &(name, label, kind) in TOOLS {
            let Some(candidate) = command_candidates(dir, name)
                .into_iter()
                .find(|candidate| is_executable(candidate))
            else {
                continue;
            };
            let status = if seen_commands.insert(name) {
                PathStatus::FirstOnPath
            } else {
                PathStatus::AlsoOnPath
            };
            let resolved = fs::canonicalize(&candidate).unwrap_or(candidate);
            let id = identity(&resolved);
            let key = (canonical(name).to_owned(), id.clone());
            if let Some(existing) = found.get_mut(&key) {
                mark_path(existing, status);
                continue;
            }
            let provider = windows_manager_origin(&resolved);
            let version = match name {
                "npm" | "pnpm" | "yarn" => node_package_version(&resolved, name),
                _ => None,
            };
            let mut evidence = vec!["executable present on PATH".into()];
            if version.is_some() {
                evidence.push("local package metadata".into());
            }
            let resource = Resource {
                canonical_tool_id: canonical(name).into(),
                display_name: label.into(),
                kind: kind.into(),
                version,
                installation_provider: provider.map(str::to_owned),
                provider_package_id: None,
                installation_instance_id: id.clone(),
                discovery_adapter: "path".into(),
                evidence,
                path_status: Some(status),
                installation_path: path_value(&resolved, include_paths),
            };
            found.insert((resource.canonical_tool_id.clone(), id), resource);
        }
    }
    progress(ScanProgress {
        message: "Finishing inventory",
        completed: 0,
        total: 0,
    });

    for dir in &paths.application_dirs {
        windows_editor(
            dir,
            "Code.exe",
            "vscode",
            "Visual Studio Code",
            include_paths,
            &mut found,
        );
        windows_editor(
            dir,
            "Cursor.exe",
            "cursor",
            "Cursor",
            include_paths,
            &mut found,
        );
    }
    windows_installed_apps(include_paths, &mut found, &mut report.warnings);
    report.resources = found.into_values().collect();
    report.normalize();
    report
}

#[cfg(target_os = "windows")]
fn command_candidates(dir: &Path, command: &str) -> Vec<PathBuf> {
    let names: &[&str] = match command {
        "python3" => &["python.exe", "python3.exe", "python3.cmd"],
        "pip3" => &["pip.exe", "pip3.exe", "pip3.cmd"],
        "npm" | "pnpm" | "yarn" => &[".cmd", ".exe"],
        "code" => &["code.cmd", "code.exe"],
        "cursor" => &["cursor.cmd", "cursor.exe"],
        "make" => &["make.exe", "mingw32-make.exe"],
        _ => &[],
    };
    if names.is_empty() {
        vec![
            dir.join(format!("{command}.exe")),
            dir.join(format!("{command}.cmd")),
        ]
    } else if matches!(command, "npm" | "pnpm" | "yarn") {
        names
            .iter()
            .map(|extension| dir.join(format!("{command}{extension}")))
            .collect()
    } else {
        names.iter().map(|name| dir.join(name)).collect()
    }
}

#[cfg(target_os = "windows")]
fn windows_manager_origin(path: &Path) -> Option<&'static str> {
    let value = path.to_string_lossy().to_lowercase();
    [
        ("\\chocolatey\\", "chocolatey"),
        ("\\scoop\\apps\\", "scoop"),
        ("\\.cargo\\bin\\", "rustup"),
        ("\\.volta\\", "volta"),
        ("\\.nvm\\", "nvm"),
        ("\\pyenv-win\\", "pyenv-win"),
        ("\\fnm\\", "fnm"),
    ]
    .iter()
    .find_map(|(needle, provider)| value.contains(needle).then_some(*provider))
}

#[cfg(target_os = "windows")]
fn windows_managed_versions(
    home: &Path,
    include_paths: bool,
    found: &mut BTreeMap<(String, String), Resource>,
    warnings: &mut Vec<String>,
) {
    for (relative, display, tool, provider) in [
        (".nvm/versions/node", "Node.js", "node", "nvm"),
        ("AppData/Roaming/nvm", "Node.js", "node", "nvm-windows"),
        (".volta/tools/image/node", "Node.js", "node", "volta"),
        ("AppData/Local/fnm/node-versions", "Node.js", "node", "fnm"),
        (
            "AppData/Roaming/fnm/node-versions",
            "Node.js",
            "node",
            "fnm",
        ),
        (
            ".pyenv/pyenv-win/versions",
            "Python",
            "python3",
            "pyenv-win",
        ),
    ] {
        for path in entries(&home.join(relative), warnings, provider) {
            if !path.is_dir() {
                continue;
            }
            let Some(version) = path.file_name().and_then(|name| name.to_str()) else {
                continue;
            };
            let id = identity(&path);
            let resource = Resource {
                canonical_tool_id: canonical(tool).into(),
                display_name: display.into(),
                kind: "runtime".into(),
                version: Some(version.trim_start_matches('v').into()),
                installation_provider: Some(provider.into()),
                provider_package_id: None,
                installation_instance_id: id.clone(),
                discovery_adapter: provider.into(),
                evidence: vec!["version manager directory".into()],
                path_status: None,
                installation_path: path_value(&path, include_paths),
            };
            found.insert((resource.canonical_tool_id.clone(), id), resource);
        }
    }
}

#[cfg(target_os = "windows")]
fn windows_editor(
    root: &Path,
    executable: &str,
    id: &str,
    label: &str,
    include_paths: bool,
    found: &mut BTreeMap<(String, String), Resource>,
) {
    if !root.join(executable).is_file() {
        return;
    }
    let version = package_json_version(&root.join("resources/app/package.json"));
    let instance = identity(root);
    let resource = Resource {
        canonical_tool_id: id.into(),
        display_name: label.into(),
        kind: "editor".into(),
        version,
        installation_provider: None,
        provider_package_id: None,
        installation_instance_id: instance.clone(),
        discovery_adapter: "application_directory".into(),
        evidence: vec!["application executable and local package metadata".into()],
        path_status: None,
        installation_path: path_value(root, include_paths),
    };
    found.insert((id.into(), instance), resource);
}

#[cfg(target_os = "windows")]
fn package_json_version(path: &Path) -> Option<String> {
    let mut bytes = Vec::new();
    fs::File::open(path)
        .ok()?
        .take(131_073)
        .read_to_end(&mut bytes)
        .ok()?;
    if bytes.len() > 131_072 {
        return None;
    }
    let value: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    valid_version(value.get("version")?.as_str()?)
}

#[cfg(target_os = "windows")]
fn windows_system_version() -> Option<String> {
    use winreg::{enums::KEY_READ, HKLM};
    let key = HKLM
        .open_subkey_with_flags(r"SOFTWARE\Microsoft\Windows NT\CurrentVersion", KEY_READ)
        .ok()?;
    let product: String = key.get_value("ProductName").ok()?;
    let version: String = key
        .get_value("DisplayVersion")
        .or_else(|_| key.get_value("ReleaseId"))
        .ok()?;
    let build: String = key
        .get_value("CurrentBuildNumber")
        .unwrap_or_else(|_| "unknown build".into());
    Some(format!("{product} {version} (Build {build})"))
}

#[cfg(target_os = "windows")]
fn windows_installed_apps(
    include_paths: bool,
    found: &mut BTreeMap<(String, String), Resource>,
    warnings: &mut Vec<String>,
) {
    use winreg::{enums::*, HKCU, HKLM};
    let roots = [("HKLM", HKLM), ("HKCU", HKCU)];
    let uninstall = r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";
    let mut readable_root = false;
    for (root_name, root) in roots {
        for (view_name, view) in [("64-bit", KEY_WOW64_64KEY), ("32-bit", KEY_WOW64_32KEY)] {
            let Ok(apps) = root.open_subkey_with_flags(uninstall, KEY_READ | view) else {
                continue;
            };
            readable_root = true;
            for key_name in apps.enum_keys().flatten().take(20_000) {
                let Ok(app) = apps.open_subkey_with_flags(&key_name, KEY_READ) else {
                    continue;
                };
                let Ok(name) = app.get_value::<String, _>("DisplayName") else {
                    continue;
                };
                let Some((canonical_id, kind)) = known_windows_app(&name) else {
                    continue;
                };
                let version = app
                    .get_value::<String, _>("DisplayVersion")
                    .ok()
                    .and_then(|value| valid_version(&value));
                let location = app
                    .get_value::<String, _>("InstallLocation")
                    .ok()
                    .map(PathBuf::from)
                    .filter(|path| !path.as_os_str().is_empty());
                let id = identity(&PathBuf::from(format!(
                    "{root_name}\\{view_name}\\{canonical_id}\\{key_name}"
                )));
                let resource = Resource {
                    canonical_tool_id: canonical_id.into(),
                    display_name: name,
                    kind: kind.into(),
                    version,
                    installation_provider: Some("windows_registry".into()),
                    provider_package_id: Some(key_name),
                    installation_instance_id: id.clone(),
                    discovery_adapter: "windows_uninstall_registry".into(),
                    evidence: vec!["installed application registry metadata".into()],
                    path_status: None,
                    installation_path: location
                        .as_deref()
                        .and_then(|path| path_value(path, include_paths)),
                };
                found
                    .entry((resource.canonical_tool_id.clone(), id))
                    .or_insert(resource);
            }
        }
    }
    if !readable_root {
        warnings.push("Unable to read installed application registry metadata".into());
    }
}

#[cfg(target_os = "windows")]
fn known_windows_app(name: &str) -> Option<(&'static str, &'static str)> {
    let value = name.to_lowercase();
    let known = [
        ("visual studio code", "vscode", "editor"),
        ("cursor", "cursor", "editor"),
        ("node.js", "nodejs", "runtime"),
        ("python", "python", "runtime"),
        ("git", "git", "tool"),
        ("docker desktop", "docker", "tool"),
        ("github cli", "gh", "tool"),
        ("terraform", "terraform", "tool"),
        ("kubectl", "kubectl", "tool"),
        ("golang", "go", "runtime"),
        ("go programming language", "go", "runtime"),
        ("openjdk", "java", "runtime"),
        ("temurin", "java", "runtime"),
        ("cmake", "cmake", "tool"),
        ("rustup", "rustup", "package_manager"),
        ("chocolatey", "chocolatey", "package_manager"),
        ("scoop", "scoop", "package_manager"),
    ];
    known
        .iter()
        .find_map(|(needle, id, kind)| value.contains(needle).then_some((*id, *kind)))
}

#[cfg(target_os = "windows")]
fn valid_version(value: &str) -> Option<String> {
    (value.len() <= 64
        && value.starts_with(|character: char| character.is_ascii_digit())
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b".-+_!".contains(&byte)))
    .then(|| value.to_owned())
}

#[cfg(target_os = "macos")]
fn system_version(path: &Path) -> Option<String> {
    let value = read_plist(path)?;
    value
        .as_dictionary()?
        .get("ProductVersion")?
        .as_string()
        .map(str::to_owned)
}

fn entries(path: &Path, warnings: &mut Vec<String>, label: &str) -> Vec<PathBuf> {
    match fs::read_dir(path) {
        Ok(entries) => {
            let mut paths = Vec::new();
            for entry in entries {
                if paths.len() == 20_000 {
                    warnings.push(format!("{label} inventory exceeded its entry limit"));
                    break;
                }
                match entry {
                    Ok(entry) => paths.push(entry.path()),
                    Err(_) => {
                        warnings.push(format!("Unable to read an entry in {label} inventory"))
                    }
                }
            }
            paths.sort();
            paths
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Vec::new(),
        Err(_) => {
            warnings.push(format!("Unable to read {label} inventory"));
            Vec::new()
        }
    }
}

#[cfg(target_os = "macos")]
fn inventory(
    root: &Path,
    provider: &str,
    include_paths: bool,
    found: &mut BTreeMap<(String, String), Resource>,
    warnings: &mut Vec<String>,
) {
    for package in entries(root, warnings, provider) {
        let Some(name) = package.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        for version_path in entries(&package, warnings, provider) {
            if !version_path.is_dir() {
                continue;
            }
            let Some(version) = version_path.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            if version.starts_with('.') {
                continue;
            }
            let id = identity(&version_path);
            let version = if provider == "homebrew_formula" {
                without_brew_revision(version)
            } else {
                version
            };
            let resource = Resource {
                canonical_tool_id: canonical(name).into(),
                display_name: known(canonical(name))
                    .map_or(name, |(label, _)| label)
                    .into(),
                kind: known(canonical(name))
                    .map_or_else(|| package_kind(name), |(_, kind)| kind)
                    .into(),
                version: Some(version.into()),
                installation_provider: Some(provider.into()),
                provider_package_id: Some(name.into()),
                installation_instance_id: id.clone(),
                discovery_adapter: provider.into(),
                evidence: vec!["installed package directory".into()],
                path_status: None,
                installation_path: path_value(&version_path, include_paths),
            };
            found.insert((resource.canonical_tool_id.clone(), id), resource);
        }
    }
}

#[cfg(target_os = "macos")]
fn managed_versions(
    home: &Path,
    include_paths: bool,
    found: &mut BTreeMap<(String, String), Resource>,
    warnings: &mut Vec<String>,
) {
    for (relative, tool, provider) in [
        (".nvm/versions/node", "node", "nvm"),
        (".pyenv/versions", "python3", "pyenv"),
        (".volta/tools/image/node", "node", "volta"),
        (".local/share/fnm/node-versions", "node", "fnm"),
    ] {
        for path in entries(&home.join(relative), warnings, provider) {
            if !path.is_dir() {
                continue;
            }
            let Some(version) = path.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            let id = identity(&path);
            let resource = Resource {
                canonical_tool_id: canonical(tool).into(),
                display_name: if tool == "node" { "Node.js" } else { "Python" }.into(),
                kind: "runtime".into(),
                version: Some(version.trim_start_matches('v').into()),
                installation_provider: Some(provider.into()),
                provider_package_id: None,
                installation_instance_id: id.clone(),
                discovery_adapter: provider.into(),
                evidence: vec!["version manager directory".into()],
                path_status: None,
                installation_path: path_value(&path, include_paths),
            };
            found.insert((resource.canonical_tool_id.clone(), id), resource);
        }
    }
}

#[cfg(target_os = "macos")]
fn editors(
    paths: &ScanPaths,
    include_paths: bool,
    found: &mut BTreeMap<(String, String), Resource>,
) {
    for dir in &paths.application_dirs {
        let mut applications = vec![
            ("Visual Studio Code.app".to_owned(), "vscode".to_owned()),
            ("Cursor.app".to_owned(), "cursor".to_owned()),
        ];
        applications.extend(
            fs::read_dir(dir)
                .into_iter()
                .flatten()
                .flatten()
                .filter_map(|entry| {
                    let name = entry.file_name().into_string().ok()?;
                    (name.starts_with("Xcode") && name.ends_with(".app"))
                        .then(|| (name, "xcode".to_owned()))
                }),
        );
        for (app, id) in applications {
            let path = dir.join(&app);
            if !path.is_dir() {
                continue;
            }
            let version = read_plist(&path.join("Contents/Info.plist")).and_then(|v| {
                v.as_dictionary()?
                    .get("CFBundleShortVersionString")?
                    .as_string()
                    .map(str::to_owned)
            });
            let instance = identity(&path);
            let resource = Resource {
                canonical_tool_id: id.clone(),
                display_name: app.trim_end_matches(".app").into(),
                kind: "editor".into(),
                version,
                installation_provider: None,
                provider_package_id: None,
                installation_instance_id: instance.clone(),
                discovery_adapter: "application_bundle".into(),
                evidence: vec!["application bundle".into()],
                path_status: None,
                installation_path: path_value(&path, include_paths),
            };
            found.insert((id, instance), resource);
        }
    }
}

fn extensions(
    home: &Path,
    include_paths: bool,
    found: &mut BTreeMap<(String, String), Resource>,
    warnings: &mut Vec<String>,
) {
    for (root, editor) in [
        (".vscode/extensions", "vscode"),
        (".cursor/extensions", "cursor"),
    ] {
        for path in entries(&home.join(root), warnings, "editor extensions") {
            if !path.is_dir() {
                continue;
            }
            let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            if name.starts_with('.') {
                continue;
            }
            let Some((extension, version)) = extension_name_and_version(name) else {
                continue;
            };
            let id = identity(&path);
            let canonical = format!("{editor}-extension:{extension}");
            let resource = Resource {
                canonical_tool_id: canonical.clone(),
                display_name: extension.into(),
                kind: "editor_extension".into(),
                version: Some(version.into()),
                installation_provider: Some(editor.into()),
                provider_package_id: Some(extension.into()),
                installation_instance_id: id.clone(),
                discovery_adapter: "editor_extensions".into(),
                evidence: vec!["extension directory name".into()],
                path_status: None,
                installation_path: path_value(&path, include_paths),
            };
            found.insert((canonical, id), resource);
        }
    }
}

#[cfg(target_os = "macos")]
fn brew_origin(
    path: &Path,
    prefixes: &[PathBuf],
) -> (Option<&'static str>, Option<String>, Option<PathBuf>) {
    for prefix in prefixes {
        let cellar = prefix.join("Cellar");
        let cellar = fs::canonicalize(&cellar).unwrap_or(cellar);
        if let Ok(relative) = path.strip_prefix(&cellar) {
            let mut parts = relative.components();
            if let (Some(package), Some(version)) = (parts.next(), parts.next()) {
                let root = cellar.join(package.as_os_str()).join(version.as_os_str());
                return (
                    Some("homebrew_formula"),
                    Some(package.as_os_str().to_string_lossy().into_owned()),
                    Some(root),
                );
            }
        }
    }
    (None, None, None)
}

#[cfg(target_os = "macos")]
fn known(canonical_id: &str) -> Option<(&'static str, &'static str)> {
    TOOLS
        .iter()
        .find(|(name, _, _)| canonical(name) == canonical_id)
        .map(|(_, label, kind)| (*label, *kind))
}

#[cfg(target_os = "macos")]
fn package_kind(name: &str) -> &'static str {
    let base = name.split('@').next().unwrap_or(name);
    match base {
        "openjdk" | "ruby" | "php" | "deno" | "erlang" | "elixir" | "kotlin" | "scala"
        | "dotnet" | "lua" | "perl" => "runtime",
        "postgresql" | "mysql" | "mariadb" | "redis" | "mongodb-community" | "sqlite"
        | "valkey" | "memcached" => "database",
        "colima" | "podman" | "minikube" | "kind" | "helm" | "awscli" | "azure-cli"
        | "google-cloud-sdk" | "flyctl" | "vercel-cli" | "ngrok" => "tool",
        "visual-studio-code" | "cursor" | "iterm2" | "warp" | "ghostty" | "docker"
        | "docker-desktop" | "postman" | "insomnia" | "android-studio" | "zed" | "sublime-text"
        | "jetbrains-toolbox" | "intellij-idea" | "pycharm" | "webstorm" | "tableplus"
        | "dbeaver-community" | "orbstack" => "application",
        _ => "package",
    }
}

#[cfg(target_os = "macos")]
fn without_brew_revision(version: &str) -> &str {
    match version.rsplit_once('_') {
        Some((base, revision))
            if !base.is_empty()
                && !revision.is_empty()
                && revision.bytes().all(|c| c.is_ascii_digit()) =>
        {
            base
        }
        _ => version,
    }
}

#[cfg(target_os = "macos")]
fn system_origin(path: &Path) -> Option<&'static str> {
    ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        .iter()
        .any(|dir| path.parent() == Some(Path::new(dir)))
        .then_some("macos_system")
}

fn canonical(name: &str) -> &str {
    match name {
        name if name.starts_with("node@") => "nodejs",
        name if name.starts_with("python@") => "python",
        "node" => "nodejs",
        "python3" | "python" => "python",
        "pip3" => "pip",
        other => other,
    }
}
fn path_value(path: &Path, include: bool) -> Option<String> {
    include.then(|| path.to_string_lossy().into_owned())
}
fn identity(path: &Path) -> String {
    let resolved = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let mut hash = 0xcbf29ce484222325u64;
    for byte in resolved.to_string_lossy().as_bytes() {
        hash = (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3);
    }
    format!("local-{hash:016x}")
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(path)
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(path: &Path) -> bool {
    path.is_file()
}

#[cfg(target_os = "macos")]
fn read_plist(path: &Path) -> Option<plist::Value> {
    let file = fs::File::open(path).ok()?;
    let mut bytes = Vec::new();
    file.take(1_048_577).read_to_end(&mut bytes).ok()?;
    if bytes.len() > 1_048_576 {
        return None;
    }
    plist::Value::from_reader(std::io::Cursor::new(bytes)).ok()
}

fn mark_path(resource: &mut Resource, status: PathStatus) {
    resource.evidence.push("executable present on PATH".into());
    if resource.path_status != Some(PathStatus::FirstOnPath) {
        resource.path_status = Some(status);
    }
}

fn node_package_version(executable: &Path, expected: &str) -> Option<String> {
    let filename = executable.file_name()?.to_str()?;
    let valid = match expected {
        "npm" => matches!(filename, "npm-cli.js" | "npm.cmd"),
        "pnpm" => matches!(filename, "pnpm.cjs" | "pnpm.js" | "pnpm.cmd"),
        "yarn" => matches!(filename, "yarn.js" | "yarn.cmd"),
        _ => false,
    };
    if !valid {
        return None;
    }
    let manifest = executable.parent()?.parent()?.join("package.json");
    let mut bytes = Vec::new();
    fs::File::open(manifest)
        .ok()?
        .take(131_073)
        .read_to_end(&mut bytes)
        .ok()?;
    if bytes.len() > 131_072 {
        return None;
    }
    let value: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    if value.get("name")?.as_str()? != expected {
        return None;
    }
    let version = value.get("version")?.as_str()?;
    if version.len() > 64
        || !version.starts_with(|c: char| c.is_ascii_digit())
        || !version
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b".-+".contains(&c))
    {
        return None;
    }
    Some(version.to_owned())
}

#[cfg(target_os = "macos")]
fn pip_version(executable: &Path) -> Option<String> {
    let prefix = executable.parent()?.parent()?;
    let mut script = Vec::new();
    fs::File::open(executable)
        .ok()?
        .take(4096)
        .read_to_end(&mut script)
        .ok()?;
    let line = script.split(|byte| *byte == b'\n').next()?;
    let shebang = std::str::from_utf8(line).ok()?.strip_prefix("#!")?.trim();
    let interpreter = shebang.split_whitespace().next()?;
    let python = fs::canonicalize(interpreter).ok()?;
    if !python.starts_with(fs::canonicalize(prefix).ok()?) {
        return None;
    }
    let mut versions = Vec::new();
    for python_dir in fs::read_dir(prefix.join("lib")).ok()?.take(128).flatten() {
        if !python_dir
            .file_name()
            .to_string_lossy()
            .starts_with("python3.")
        {
            continue;
        }
        let site = python_dir.path().join("site-packages");
        let Ok(entries) = fs::read_dir(site) else {
            continue;
        };
        for entry in entries.take(1024).flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if !name.starts_with("pip-") || !name.ends_with(".dist-info") {
                continue;
            }
            if let Some(version) = pip_metadata(&entry.path().join("METADATA")) {
                versions.push(version);
            }
        }
    }
    if versions.len() == 1 {
        versions.pop()
    } else {
        None
    }
}

#[cfg(target_os = "macos")]
fn pip_metadata(path: &Path) -> Option<String> {
    let mut bytes = Vec::new();
    fs::File::open(path)
        .ok()?
        .take(131_073)
        .read_to_end(&mut bytes)
        .ok()?;
    if bytes.len() > 131_072 {
        return None;
    }
    let headers = std::str::from_utf8(&bytes).ok()?.split("\n\n").next()?;
    let mut name = None;
    let mut version = None;
    for line in headers.lines() {
        if line.trim().is_empty() {
            break;
        }
        if let Some(value) = line.strip_prefix("Name: ") {
            name = Some(value.trim());
        }
        if let Some(value) = line.strip_prefix("Version: ") {
            version = Some(value.trim());
        }
    }
    let version = version?;
    if !name?.eq_ignore_ascii_case("pip")
        || version.len() > 64
        || !version.starts_with(|c: char| c.is_ascii_digit())
        || !version
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b".-+_!".contains(&c))
    {
        return None;
    }
    Some(version.to_owned())
}

#[cfg(target_os = "macos")]
fn managed_origin(path: &Path, home: &Path) -> Option<&'static str> {
    for (relative, provider) in [
        (".nvm/versions/node", "nvm"),
        (".pyenv/versions", "pyenv"),
        (".volta/tools/image/node", "volta"),
        (".local/share/fnm/node-versions", "fnm"),
    ] {
        let root = fs::canonicalize(home.join(relative)).ok();
        if root.as_deref().is_some_and(|root| {
            path.strip_prefix(root)
                .ok()
                .is_some_and(|rest| rest.components().count() >= 2)
        }) {
            return Some(provider);
        }
    }
    None
}

pub fn is_developer_tool(resource: &Resource) -> bool {
    if resource.kind == "editor_extension" {
        return false;
    }
    if resource.kind != "package" {
        return true;
    }
    let id = resource.canonical_tool_id.as_str();
    TOOLS.iter().any(|(name, _, _)| canonical(name) == id)
        || matches!(
            id,
            "openjdk"
                | "redis"
                | "mariadb"
                | "mongodb-community"
                | "colima"
                | "iterm2"
                | "visual-studio-code"
                | "cursor"
                | "xcode"
        )
        || ["openjdk@", "postgresql@", "mariadb@"]
            .iter()
            .any(|prefix| id.starts_with(prefix))
}

fn extension_name_and_version(name: &str) -> Option<(&str, &str)> {
    for (index, _) in name.match_indices('-').rev() {
        let extension = &name[..index];
        let rest = &name[index + 1..];
        let mut parts = rest.split('.');
        let (Some(major), Some(minor)) = (parts.next(), parts.next()) else {
            continue;
        };
        if !extension.contains('.')
            || major.is_empty()
            || minor.is_empty()
            || !major.bytes().all(|c| c.is_ascii_digit())
            || !minor.bytes().all(|c| c.is_ascii_digit())
        {
            continue;
        }
        let version = rest
            .split_once("-darwin-")
            .or_else(|| rest.split_once("-linux-"))
            .or_else(|| rest.split_once("-win32-"))
            .map_or(rest, |(version, _)| version);
        return Some((extension, version));
    }
    None
}

#[cfg(target_os = "macos")]
fn xcode_origin(path: &Path) -> Option<String> {
    for ancestor in path.ancestors() {
        let Some(name) = ancestor.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        if name.starts_with("Xcode") && name.ends_with(".app") {
            let value = read_plist(&ancestor.join("Contents/Info.plist"))?;
            let version = value
                .as_dictionary()?
                .get("CFBundleShortVersionString")?
                .as_string()?
                .to_owned();
            return Some(version);
        }
    }
    None
}
