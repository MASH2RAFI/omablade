use std::fs;

fn scratch(name: &str) -> std::path::PathBuf {
    let root = std::env::temp_dir().join(format!("omablade-paths-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&root);
    fs::create_dir_all(&root).unwrap();
    root
}

#[test]
fn a_replaced_binary_path_drops_the_deleted_suffix_when_the_file_exists() {
    let dir = tempfile::tempdir().unwrap();
    let binary = dir.path().join("omablade");
    std::fs::write(&binary, b"").unwrap();
    let deleted = std::path::PathBuf::from(format!("{} (deleted)", binary.display()));
    assert_eq!(omablade::common::replaced_binary_path(&deleted), binary);
    let missing =
        std::path::PathBuf::from(format!("{} (deleted)", dir.path().join("gone").display()));
    assert_eq!(omablade::common::replaced_binary_path(&missing), missing);
    assert_eq!(omablade::common::replaced_binary_path(&binary), binary);
}

#[test]
fn a_declared_app_root_must_carry_the_manifest_and_the_shell() {
    let root = scratch("app-root");
    unsafe { std::env::set_var("OMABLADE_APP_ROOT", &root) };
    assert!(omablade::paths::app_root().is_err());

    fs::write(root.join("manifest.json"), "{}").unwrap();
    fs::write(root.join("Service.qml"), "").unwrap();
    assert!(omablade::paths::app_root().is_err());

    fs::create_dir_all(root.join("app")).unwrap();
    fs::write(root.join("app/shell.qml"), "").unwrap();
    assert_eq!(omablade::paths::app_root().unwrap(), root);

    unsafe { std::env::set_var("OMABLADE_APP_ROOT", "relative/root") };
    assert!(omablade::paths::app_root().is_err());

    unsafe { std::env::remove_var("OMABLADE_APP_ROOT") };
    if let Ok(found) = omablade::paths::app_root() {
        assert!(found.join("manifest.json").symlink_metadata().is_ok());
        assert!(found.join("app/shell.qml").symlink_metadata().is_ok());
        assert!(std::env::current_exe().unwrap().starts_with(&found));
    }

    let _ = fs::remove_dir_all(&root);
}
