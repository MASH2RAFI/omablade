use serde_json::Value;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use tempfile::tempdir;

const USER_BINDINGS: &str =
    "o.bind(\"SUPER + RETURN\", \"Terminal\", { launch = \"alacritty\" })\n";

fn plugin_root(home: &Path) -> PathBuf {
    let root = home.join(".config/omarchy/plugins/mash2rafi.omablade");
    fs::create_dir_all(root.join("app")).unwrap();
    fs::write(root.join("manifest.json"), "{}").unwrap();
    fs::write(root.join("app/shell.qml"), "").unwrap();
    let launcher = root.join("omablade");
    fs::write(&launcher, "#!/bin/sh\n").unwrap();
    fs::set_permissions(&launcher, fs::Permissions::from_mode(0o755)).unwrap();
    root
}

fn roles(home: &Path, app_root: &Path, args: &[&str]) -> Value {
    let output = Command::new(env!("CARGO_BIN_EXE_omablade"))
        .args(["_backend", "roles-set", "--role", "bindings"])
        .args(args)
        .args(["-o", "json"])
        .env_clear()
        .env("PATH", "/usr/bin:/bin")
        .env("HOME", home)
        .env("XDG_CONFIG_HOME", home.join(".config"))
        .env("XDG_STATE_HOME", home.join(".local/state"))
        .env("XDG_DATA_HOME", home.join(".local/share"))
        .env("OMABLADE_APP_ROOT", app_root)
        .output()
        .unwrap();
    serde_json::from_slice(&output.stdout).unwrap_or(Value::Null)
}

#[test]
fn a_plugin_install_links_its_launcher_and_binds_keys_reversibly() {
    let temporary = tempdir().unwrap();
    let home = temporary.path().join("home with 'quotes' and $dollar");
    fs::create_dir_all(home.join(".config/hypr")).unwrap();
    fs::write(home.join(".config/hypr/bindings.lua"), USER_BINDINGS).unwrap();
    let root = plugin_root(&home);

    let on = roles(&home, &root, &["--on"]);
    assert_eq!(on["roles"]["bindings"]["status"], "enabled", "{on}");
    let link = home.join(".local/bin/omablade");
    assert_eq!(fs::read_link(&link).unwrap(), root.join("omablade"));
    let user = fs::read_to_string(home.join(".config/hypr/bindings.lua")).unwrap();
    assert!(user.starts_with(USER_BINDINGS));
    assert!(
        user.contains("dofile(os.getenv(\"HOME\") .. \"/.config/hypr/omablade-bindings.lua\")")
    );
    let snippet = fs::read_to_string(home.join(".config/hypr/omablade-bindings.lua")).unwrap();
    let quoted = format!("'{}'", link.display().to_string().replace('\'', "'\\''"));
    let lua = quoted.replace('\\', "\\\\").replace('"', "\\\"");
    assert!(
        snippet.contains(&format!("timeout 0.4s {lua} control ")),
        "{snippet}"
    );
    assert!(!snippet.contains("timeout 0.4s omablade control"));

    let off = roles(&home, &root, &[]);
    assert_eq!(off["roles"]["bindings"]["status"], "restored", "{off}");
    assert_eq!(
        fs::read_to_string(home.join(".config/hypr/bindings.lua")).unwrap(),
        USER_BINDINGS
    );
    assert!(!home.join(".config/hypr/omablade-bindings.lua").exists());
}

#[test]
fn a_checkout_outside_the_plugins_folder_is_never_linked() {
    let temporary = tempdir().unwrap();
    let home = temporary.path().join("home");
    fs::create_dir_all(home.join(".config/hypr")).unwrap();
    fs::write(home.join(".config/hypr/bindings.lua"), USER_BINDINGS).unwrap();
    let checkout = temporary.path().join("projects/omablade");
    fs::create_dir_all(checkout.join("app")).unwrap();
    fs::write(checkout.join("manifest.json"), "{}").unwrap();
    fs::write(checkout.join("app/shell.qml"), "").unwrap();
    fs::write(checkout.join("omablade"), "#!/bin/sh\n").unwrap();

    let on = roles(&home, &checkout, &["--on"]);
    assert_eq!(on["roles"]["bindings"]["status"], "refused", "{on}");
    assert!(!home.join(".local/bin/omablade").exists());
    assert_eq!(
        fs::read_to_string(home.join(".config/hypr/bindings.lua")).unwrap(),
        USER_BINDINGS
    );
}

#[test]
fn an_existing_command_is_never_replaced_by_the_plugin_link() {
    let temporary = tempdir().unwrap();
    let home = temporary.path().join("home");
    fs::create_dir_all(home.join(".config/hypr")).unwrap();
    fs::create_dir_all(home.join(".local/bin")).unwrap();
    fs::write(home.join(".config/hypr/bindings.lua"), USER_BINDINGS).unwrap();
    fs::write(home.join(".local/bin/omablade"), "#!/bin/sh\necho mine\n").unwrap();
    let root = plugin_root(&home);
    let on = roles(&home, &root, &["--on"]);
    assert_eq!(on["roles"]["bindings"]["status"], "refused", "{on}");
    assert_eq!(
        fs::read_to_string(home.join(".local/bin/omablade")).unwrap(),
        "#!/bin/sh\necho mine\n"
    );
}
