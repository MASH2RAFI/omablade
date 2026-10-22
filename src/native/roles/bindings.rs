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
