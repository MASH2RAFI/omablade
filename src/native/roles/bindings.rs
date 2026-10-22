use super::entry::{MARKER, Planned};
use std::path::Path;
use std::time::Duration;

const SNIPPET: &str = include_str!("../../../examples/omablade-bindings.lua");

fn command(launcher: &Path) -> String {
    let path = launcher.to_string_lossy();
    if path.chars().any(char::is_control) {
        return "omablade".to_string();
    }
    let quoted = format!("'{}'", path.replace('\'', "'\\''"));
    quoted.replace('\\', "\\\\").replace('"', "\\\"")
}

pub fn snippet(launcher: &Path) -> String {
    SNIPPET.replace(
        "timeout 0.4s omablade control ",
        &format!("timeout 0.4s {} control ", command(launcher)),
    )
}

pub fn plan(launcher: &Path, config: &Path) -> Vec<Planned> {
    vec![
        Planned::whole(config.join("hypr/omablade-bindings.lua"), snippet(launcher)),
        Planned::marker(
            config.join("hypr/bindings.lua"),
            format!(
                "dofile(os.getenv(\"HOME\") .. \"/.config/hypr/omablade-bindings.lua\") {MARKER}"
            ),
        ),
    ]
}

pub fn after() -> String {
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none_or(|value| value.is_empty()) {
        return String::new();
    }
    let result = crate::command::CommandSpec::new("hyprctl")
        .args(["reload"])
        .timeout(Duration::from_secs(10))
        .limits(64 * 1024, 64 * 1024)
        .run();
    match result {
        Ok(output) if output.status.success() => String::new(),
        Ok(output) => format!(
            "hyprctl reload failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ),
        Err(error) => format!("hyprctl reload failed: {error}"),
    }
}

const LEGACY_TARGET: &str = "data-goblin.fileblade.control";
const TARGET: &str = "mash2rafi.omablade.control";

pub fn migrate_legacy(config: &Path) -> crate::AppResult<serde_json::Value> {
    let link = config.join("hypr/bindings.lua");
    let path = match std::fs::canonicalize(&link) {
        Ok(path) => path,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(serde_json::json!({"ok": true, "migrated": 0, "path": link}));
        }
        Err(error) => return Err(error.into()),
    };
    let text = std::fs::read_to_string(&path)?;
    let count = text.matches(LEGACY_TARGET).count();
    if count == 0 {
        return Ok(serde_json::json!({"ok": true, "migrated": 0, "path": path}));
    }
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(0);
    let backup = path.with_file_name(format!("bindings.lua.bak-omablade-{stamp}"));
    std::fs::copy(&path, &backup)?;
    let staged = path.with_file_name(format!(".bindings.lua.omablade-{stamp}"));
    std::fs::write(&staged, text.replace(LEGACY_TARGET, TARGET))?;
    std::fs::set_permissions(&staged, std::fs::metadata(&path)?.permissions())?;
    std::fs::rename(&staged, &path)?;
    Ok(serde_json::json!({
        "ok": true,
        "migrated": count,
        "path": path,
        "backup": backup,
        "reload_error": after(),
    }))
}
