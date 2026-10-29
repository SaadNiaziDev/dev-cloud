use serde::Serialize;

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PathStatus {
    FirstOnPath,
    AlsoOnPath,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct Resource {
    pub canonical_tool_id: String,
    pub display_name: String,
    pub kind: String,
    pub version: Option<String>,
    pub installation_provider: Option<String>,
    pub provider_package_id: Option<String>,
    pub installation_instance_id: String,
    pub discovery_adapter: String,
    pub evidence: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path_status: Option<PathStatus>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub installation_path: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Host {
    pub platform: &'static str,
    pub architecture: &'static str,
    pub os_version: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Report {
    pub schema_version: u32,
    pub observed_at_unix_seconds: u64,
    pub host: Host,
    pub resources: Vec<Resource>,
    pub warnings: Vec<String>,
}

impl Report {
    pub fn normalize(&mut self) {
        for resource in &mut self.resources {
            resource.evidence.sort();
            resource.evidence.dedup();
        }
        self.resources.sort_by(|a, b| {
            (
                &a.canonical_tool_id,
                &a.installation_instance_id,
                &a.discovery_adapter,
            )
                .cmp(&(
                    &b.canonical_tool_id,
                    &b.installation_instance_id,
                    &b.discovery_adapter,
                ))
        });
        self.resources.dedup();
        self.warnings.sort();
        self.warnings.dedup();
    }
}
