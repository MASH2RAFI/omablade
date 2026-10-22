use serde_json::{Value, json};
use std::fs;
use std::path::Path;
use std::process::Command;

fn omablade() -> Command {
    Command::new(env!("CARGO_BIN_EXE_omablade"))
}

fn scaffold(directory: &Path) {
    let output = omablade()
        .args(["extension", "template", "acme.omablade-weather"])
        .arg(directory)
        .args(["--author", "Jane Doe"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

fn check(directory: &Path) -> std::process::Output {
    omablade()
        .args(["extension", "check", "."])
        .current_dir(directory)
        .output()
        .unwrap()
}

fn manifest(directory: &Path) -> Value {
    serde_json::from_slice(&fs::read(directory.join("manifest.json")).unwrap()).unwrap()
}

fn write_manifest(directory: &Path, document: &Value) {
    fs::write(
        directory.join("manifest.json"),
        serde_json::to_vec_pretty(document).unwrap(),
    )
    .unwrap();
}

#[test]
fn a_scaffolded_extension_passes_and_reports_its_checks() {
    let temporary = tempfile::tempdir().unwrap();
    let target = temporary.path().join("weather");
    scaffold(&target);
    let output = omablade()
        .args(["--output", "json", "extension", "check"])
        .arg(&target)
        .output()
        .unwrap();
    assert!(output.status.success());
    let document: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(document["ok"], true);
    assert_eq!(document["checks"].as_array().unwrap().len(), 5);
    let text = check(&target);
    assert!(String::from_utf8_lossy(&text.stdout).contains("contract: 5 checks ok"));
}

#[test]
fn a_broken_extension_is_refused_with_the_failing_rule() {
    let temporary = tempfile::tempdir().unwrap();
    let target = temporary.path().join("weather");
    scaffold(&target);

    type Case = (&'static str, fn(&mut Value), &'static str);
    let cases: [Case; 7] = [
        (
            "version",
            |document| document["version"] = json!("1.0.0"),
            "stay at 0.1.0 until the first release",
        ),
        (
            "id",
            |document| document["id"] = json!("Acme.Weather"),
            "id must be publisher.name in lowercase",
        ),
        (
            "service",
            |document| document["entryPoints"]["service"] = json!("Missing.qml"),
            "the service entry point must exist",
        ),
        (
            "entry",
            |document| {
                document["extensions"]["mash2rafi.omablade/blade"][0]["entry"] =
                    json!("../outside/Module.qml")
            },
            "entry must be a safe relative path",
        ),
        (
            "setting type",
            |document| {
                document["extensions"]["mash2rafi.omablade/blade"][0]["settings"]["schema"][0]["type"] =
                    json!("colour")
            },
            "unknown setting type colour",
        ),
        (
            "default",
            |document| {
                document["extensions"]["mash2rafi.omablade/blade"][0]["settings"]["defaults"]["stray"] =
                    json!(1)
            },
            "default stray has no schema row",
        ),
        (
            "placement",
            |document| {
                document["extensions"]["mash2rafi.omablade/blade"][0]["defaultPlacement"] =
                    json!("top-right")
            },
            "defaultPlacement must be beside-files when present",
        ),
    ];
    let original = manifest(&target);
    for (name, mutate, message) in cases {
        let mut document = original.clone();
        mutate(&mut document);
        write_manifest(&target, &document);
        let output = check(&target);
        assert!(!output.status.success(), "{name} must be refused");
        assert!(
            String::from_utf8_lossy(&output.stderr).contains(message),
            "{name}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
    write_manifest(&target, &original);
    assert!(check(&target).status.success());

    fs::remove_file(target.join("assets/omablade-logo.png")).unwrap();
    let output = check(&target);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("needs assets/omablade-logo.png"));

    fs::write(
        target.join("HostGuard.js"),
        "var HOST_ID = \"acme.other\"\n",
    )
    .unwrap();
    let output = check(&target);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("must name the Omablade host"));
}

fn isolated(home: &Path) -> Command {
    let mut command = omablade();
    command
        .env_clear()
        .env("PATH", home.join("bin"))
        .env("HOME", home)
        .env("XDG_RUNTIME_DIR", home)
        .env("XDG_CONFIG_HOME", home.join("config"))
        .env("XDG_STATE_HOME", home.join("state"));
    command
}

fn example() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("examples/mash2rafi.omablade-networkstorage")
}

fn copy(source: &Path, target: &Path) {
    fs::create_dir_all(target).unwrap();
    for entry in fs::read_dir(source).unwrap() {
        let entry = entry.unwrap();
        let to = target.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy(&entry.path(), &to);
        } else {
            fs::copy(entry.path(), to).unwrap();
        }
    }
}

#[test]
fn a_hand_written_extension_passes_without_the_template_checks() {
    let output = omablade()
        .args(["--output", "json", "extension", "check"])
        .arg(example())
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let document: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(document["kind"], "extension");
    assert_eq!(document["id"], "mash2rafi.omablade-networkstorage");
    assert_eq!(document["modules"], json!(["networkstorage"]));
    assert_eq!(document["checks"].as_array().unwrap().len(), 3);
}

#[test]
fn every_problem_is_listed_and_a_missing_provider_names_its_fix() {
    let temporary = tempfile::tempdir().unwrap();
    let target = temporary.path().join("broken");
    copy(&example(), &target);
    let mut document = manifest(&target);
    document.as_object_mut().unwrap().remove("version");
    let module = &mut document["extensions"]["mash2rafi.omablade/blade"][0];
    module.as_object_mut().unwrap().remove("provider");
    module["entry"] = json!("blades/Missing.qml");
    write_manifest(&target, &document);
    let output = check(&target);
    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("3 problems"), "{stderr}");
    assert!(stderr.contains("version is required"), "{stderr}");
    assert!(
        stderr.contains("entry blades/Missing.qml must exist"),
        "{stderr}"
    );
    assert!(
        stderr.contains("module networkstorage has no \"provider\": add \"provider\": null"),
        "{stderr}"
    );
}

#[test]
fn a_new_module_is_written_where_omablade_reads_it_and_passes_the_check() {
    let temporary = tempfile::tempdir().unwrap();
    fs::create_dir_all(temporary.path().join("bin")).unwrap();
    let output = isolated(temporary.path())
        .args(["module", "new", "todo-list"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        stdout.contains("Created module todo-list (Todo List)"),
        "{stdout}"
    );
    assert!(stdout.contains("Omablade is not running"), "{stdout}");
    let directory = temporary
        .path()
        .join("config/omarchy/omablade/modules/todo-list");
    let definition: Value =
        serde_json::from_slice(&fs::read(directory.join("blade.json")).unwrap()).unwrap();
    assert_eq!(definition["id"], "todo-list");
    assert_eq!(definition["name"], "Todo List");
    let source = fs::read_to_string(directory.join("Module.qml")).unwrap();
    assert!(source.contains("readonly property string title: \"Todo List\""));
    assert!(!source.contains("{{"));
    assert!(check(&directory).status.success());

    let again = isolated(temporary.path())
        .args(["module", "new", "todo-list"])
        .output()
        .unwrap();
    assert!(!again.status.success());
    assert!(String::from_utf8_lossy(&again.stderr).contains("pass --force"));
    let bad = isolated(temporary.path())
        .args(["module", "new", "Bad Id"])
        .output()
        .unwrap();
    assert!(!bad.status.success());
}

#[test]
fn install_copies_a_checked_extension_and_refuses_a_second_copy_or_a_broken_one() {
    let temporary = tempfile::tempdir().unwrap();
    fs::create_dir_all(temporary.path().join("bin")).unwrap();
    let install = |extra: &[&str], source: &Path| {
        isolated(temporary.path())
            .args(["extension", "install"])
            .arg(source)
            .args(extra)
            .output()
            .unwrap()
    };
    let output = install(&[], &example());
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let installed = temporary
        .path()
        .join("config/omablade/extensions/mash2rafi.omablade-networkstorage");
    assert!(installed.join("manifest.json").is_file());
    assert!(installed.join("blades/Module.qml").is_file());
    assert!(installed.join("omablade-networkstorage").is_file());

    let output = install(&[], &example());
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("pass --replace"));
    assert!(install(&["--replace"], &example()).status.success());

    let broken = temporary.path().join("broken");
    copy(&example(), &broken);
    let mut document = manifest(&broken);
    document["extensions"]["mash2rafi.omablade/blade"][0]
        .as_object_mut()
        .unwrap()
        .remove("provider");
    write_manifest(&broken, &document);
    let output = install(&["--replace"], &broken);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("has no \"provider\""));

    let linked = temporary.path().join("linked");
    copy(&example(), &linked);
    std::os::unix::fs::symlink("/etc/hostname", linked.join("leak")).unwrap();
    let output = install(&["--replace"], &linked);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("may not contain links"));
    assert!(installed.join("manifest.json").is_file());
}
