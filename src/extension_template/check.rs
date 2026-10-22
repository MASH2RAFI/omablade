use super::{image, read_bounded};
use crate::{AppError, AppResult};
use regex::Regex;
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

const SOCKET: &str = "mash2rafi.omablade/blade";
const MANIFEST_LIMIT: u64 = 1024 * 1024;
const DEFINITION_LIMIT: u64 = 16 * 1024;
const SOURCE_LIMIT: u64 = 1024 * 1024;
const SETTING_TYPES: [&str; 6] = ["string", "integer", "number", "boolean", "enum", "path"];

pub enum Kind {
    Template,
    Extension,
    UserModule,
}

pub struct Report {
    pub kind: Kind,
    pub id: String,
    pub modules: Vec<String>,
    pub checks: Vec<&'static str>,
}

fn plugin_id() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| Regex::new(r"^[a-z0-9_-]+\.[a-z0-9_-]+$").unwrap())
}

fn module_id() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| Regex::new(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$").unwrap())
}

fn setting_key() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| Regex::new(r"^[A-Za-z_][A-Za-z0-9_]{0,63}$").unwrap())
}

#[derive(Default)]
struct Problems(Vec<String>);

impl Problems {
    fn check(&mut self, condition: bool, message: impl Into<String>) {
        if !condition {
            self.0.push(message.into());
        }
    }
}

fn json(path: &Path, limit: u64) -> AppResult<Value> {
    let bytes = read_bounded(path, limit)?;
    serde_json::from_slice(&bytes)
        .map_err(|error| AppError::invalid(format!("cannot read {}: {error}", path.display())))
}

fn is_file(root: &Path, relative: &str) -> bool {
    root.join(relative).is_file()
}

fn safe_relative(path: &str) -> bool {
    !path.is_empty() && !path.starts_with('/') && !path.split('/').any(|part| part == "..")
}

fn manifest_identity(root: &Path, document: &Value, template: bool, problems: &mut Problems) {
    problems.check(document["schemaVersion"] == 1, "schemaVersion must be 1");
    problems.check(
        plugin_id().is_match(document["id"].as_str().unwrap_or_default()),
        "id must be publisher.name in lowercase",
    );
    problems.check(
        !document["name"]
            .as_str()
            .unwrap_or_default()
            .trim()
            .is_empty(),
        "name is required",
    );
    if template {
        problems.check(
            document["version"] == "0.1.0",
            "stay at 0.1.0 until the first release",
        );
    } else {
        problems.check(
            !document["version"]
                .as_str()
                .unwrap_or_default()
                .trim()
                .is_empty(),
            "version is required, for example \"0.1.0\"",
        );
    }
    problems.check(
        document["kinds"]
            .as_array()
            .is_some_and(|kinds| kinds.iter().any(|kind| kind == "service")),
        "kinds must include service",
    );
    let service = document["entryPoints"]["service"]
        .as_str()
        .unwrap_or_default();
    problems.check(
        !service.is_empty() && is_file(root, service),
        "the service entry point must exist",
    );
}

fn module_definition(root: &Path, module: &Value, manifest: bool, problems: &mut Problems) {
    let id = module["id"].as_str().unwrap_or_default();
    let label = if id.is_empty() { "a module" } else { id };
    problems.check(
        module_id().is_match(id),
        format!("module id {id:?} is invalid"),
    );
    problems.check(
        !module["name"]
            .as_str()
            .unwrap_or_default()
            .trim()
            .is_empty(),
        format!("module {label} needs a name"),
    );
    let entry = module["entry"].as_str().unwrap_or("Module.qml");
    if safe_relative(entry) {
        problems.check(is_file(root, entry), format!("entry {entry} must exist"));
    } else {
        problems.check(false, "entry must be a safe relative path");
    }
    let contract = module
        .get("hostContract")
        .cloned()
        .unwrap_or(Value::from(1));
    problems.check(
        contract == 1 || contract == 2,
        "hostContract must be 1 or 2",
    );
    let height = module.get("minHeight").map_or(Some(0), Value::as_i64);
    problems.check(
        height.is_some_and(|height| (0..=4096).contains(&height)),
        "minHeight must be 0 to 4096",
    );
    problems.check(
        module
            .get("defaultPlacement")
            .is_none_or(|placement| placement == "beside-files"),
        "defaultPlacement must be beside-files when present",
    );
    if manifest {
        match module.get("provider") {
            None => problems.check(
                false,
                format!(
                    "module {label} has no \"provider\": add \"provider\": null if it keeps no shared state, or the path to its Provider.qml"
                ),
            ),
            Some(Value::Null) => {}
            Some(Value::String(provider)) if safe_relative(provider) => problems.check(
                is_file(root, provider),
                format!("provider {provider} must exist"),
            ),
            Some(_) => problems.check(
                false,
                format!("module {label}: \"provider\" must be null or a relative path to a QML file"),
            ),
        }
    }
}

fn blade_modules(root: &Path, document: &Value, problems: &mut Problems) -> Vec<Value> {
    let modules = match document["extensions"][SOCKET].as_array() {
        Some(modules) if (1..=128).contains(&modules.len()) => modules.clone(),
        _ => {
            problems.check(
                false,
                format!("declare at least one blade module under extensions.\"{SOCKET}\""),
            );
            return Vec::new();
        }
    };
    for module in &modules {
        module_definition(root, module, true, problems);
    }
    modules
}

fn module_settings(modules: &[Value], problems: &mut Problems) {
    for module in modules {
        let settings = match module.get("settings") {
            Some(Value::Null) | None => continue,
            Some(settings) => settings,
        };
        let schema = settings["schema"].as_array().cloned().unwrap_or_default();
        let keys: Vec<&str> = schema
            .iter()
            .map(|row| row["key"].as_str().unwrap_or_default())
            .collect();
        let mut unique = keys.clone();
        unique.sort_unstable();
        unique.dedup();
        problems.check(
            unique.len() == keys.len() && keys.len() <= 32,
            "setting keys must be unique and at most 32",
        );
        for row in &schema {
            problems.check(
                setting_key().is_match(row["key"].as_str().unwrap_or_default()),
                "setting key is invalid",
            );
            let kind = row["type"].as_str().unwrap_or_default();
            problems.check(
                SETTING_TYPES.contains(&kind),
                format!("unknown setting type {kind}"),
            );
        }
        for key in settings["defaults"]
            .as_object()
            .into_iter()
            .flat_map(|defaults| defaults.keys())
        {
            problems.check(
                keys.contains(&key.as_str()),
                format!("default {key} has no schema row"),
            );
        }
    }
}

fn host_guard(root: &Path, problems: &mut Problems) -> AppResult<()> {
    let bytes = read_bounded(&root.join("HostGuard.js"), SOURCE_LIMIT)?;
    let source = String::from_utf8_lossy(&bytes).to_string();
    problems.check(
        source.contains(&format!("var HOST_ID = \"{}\"", super::HOST_ID)),
        "HostGuard.js must name the Omablade host",
    );
    problems.check(
        source.contains("https://github.com/mash2rafi/omablade"),
        "HostGuard.js must identify the Omablade repository",
    );
    problems.check(
        !source.contains("omarchy plugin add"),
        "the host guard must never install Omablade",
    );
    problems.check(
        is_file(root, "assets/omablade-logo.png"),
        "the host guard needs assets/omablade-logo.png",
    );
    Ok(())
}

fn banner(document: &Value, problems: &mut Problems) -> AppResult<()> {
    let name = document["name"].as_str().unwrap_or_default().trim();
    let name = name.strip_prefix(image::NAME_PREFIX).unwrap_or(name);
    let svg = image::banner_svg(name, None)?;
    problems.check(svg.contains("viewBox=\"0 0 960 272\""), "banner viewBox");
    problems.check(
        svg.contains(&format!("id=\"{}\"", image::BANNER_MASK)),
        "banner mask id",
    );
    problems.check(
        svg.contains(&format!("fill=\"{}\"", image::AMBER)),
        "banner subtitle colour",
    );
    problems.check(
        svg.contains(&format!(
            "aria-label=\"Omablade {} extension\"",
            image::escape(&name.to_lowercase())
        )),
        "banner label",
    );
    Ok(())
}

fn finish(problems: Problems, report: Report) -> AppResult<Report> {
    match problems.0.len() {
        0 => Ok(report),
        1 => Err(AppError::invalid(problems.0[0].clone())),
        count => Err(AppError::invalid(format!(
            "{count} problems:\n  {}",
            problems.0.join("\n  ")
        ))),
    }
}

pub fn run(directory: &Path) -> AppResult<Report> {
    let root = absolute(directory)?;
    if !root.is_dir() {
        return Err(AppError::invalid(format!(
            "{} is not a directory",
            root.display()
        )));
    }
    let mut problems = Problems::default();
    if !root.join("manifest.json").exists() && root.join("blade.json").exists() {
        let definition = json(&root.join("blade.json"), DEFINITION_LIMIT)?;
        module_definition(&root, &definition, false, &mut problems);
        module_settings(std::slice::from_ref(&definition), &mut problems);
        let id = definition["id"].as_str().unwrap_or_default().to_string();
        return finish(
            problems,
            Report {
                kind: Kind::UserModule,
                modules: vec![id.clone()],
                id,
                checks: vec!["blade module", "module settings"],
            },
        );
    }
    let document = json(&root.join("manifest.json"), MANIFEST_LIMIT)?;
    let template = root.join("HostGuard.js").exists();
    manifest_identity(&root, &document, template, &mut problems);
    let modules = blade_modules(&root, &document, &mut problems);
    module_settings(&modules, &mut problems);
    let mut checks = vec!["manifest identity", "blade modules", "module settings"];
    if template {
        host_guard(&root, &mut problems)?;
        banner(&document, &mut problems)?;
        checks.extend(["host guard", "banner"]);
    }
    let id = document["id"].as_str().unwrap_or_default().to_string();
    finish(
        problems,
        Report {
            kind: if template {
                Kind::Template
            } else {
                Kind::Extension
            },
            modules: modules
                .iter()
                .map(|module| module["id"].as_str().unwrap_or_default().to_string())
                .collect(),
            id,
            checks,
        },
    )
}

fn absolute(directory: &Path) -> AppResult<PathBuf> {
    if directory.is_absolute() {
        Ok(directory.to_path_buf())
    } else {
        Ok(std::env::current_dir()?.join(directory))
    }
}
