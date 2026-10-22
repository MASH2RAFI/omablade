use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use tempfile::tempdir;

const ROLE: &str = "omablade _backend roles-set --role bindings --on";

struct Setup {
    home: PathBuf,
    log: PathBuf,
    bin: PathBuf,
}

fn setup(root: &Path) -> Setup {
    let home = root.join("home");
    let bin = root.join("fake-bin");
    let log = root.join("calls.log");
    fs::create_dir_all(home.join(".config/hypr")).unwrap();
    fs::create_dir_all(&bin).unwrap();
    fs::write(
        home.join(".config/hypr/bindings.lua"),
        "o.bind(\"SUPER + RETURN\", \"Terminal\", { launch = \"alacritty\" })\n",
    )
    .unwrap();
    let omarchy = format!(
        "#!/bin/sh\necho \"omarchy $*\" >> '{log}'\nif [ \"$1 $2\" = \"plugin add\" ]; then\n  plugin=\"$HOME/.config/omarchy/plugins/mash2rafi.omablade\"\n  mkdir -p \"$plugin\"\n  printf '#!/bin/sh\\necho \"omablade $*\" >> \"%s\"\\n' '{log}' > \"$plugin/omablade\"\n  chmod +x \"$plugin/omablade\"\nfi\n",
        log = log.display(),
    );
    let path = bin.join("omarchy");
    fs::write(&path, omarchy).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    Setup { home, log, bin }
}

fn run(setup: &Setup, args: &[&str]) -> (bool, String) {
    let script = Path::new(env!("CARGO_MANIFEST_DIR")).join("tools/plugin-setup");
    let output = Command::new("bash")
        .arg(script)
        .args(args)
        .env_clear()
        .env("HOME", &setup.home)
        .env("PATH", format!("{}:/usr/bin:/bin", setup.bin.display()))
        .output()
        .unwrap();
    (
        output.status.success(),
        String::from_utf8_lossy(&output.stdout).into_owned()
            + &String::from_utf8_lossy(&output.stderr),
    )
}

fn calls(setup: &Setup) -> String {
    fs::read_to_string(&setup.log).unwrap_or_default()
}

fn bindings(setup: &Setup) -> String {
    fs::read_to_string(setup.home.join(".config/hypr/bindings.lua")).unwrap()
}

#[test]
fn one_run_installs_enables_links_and_turns_on_the_bindings_role() {
    let temporary = tempdir().unwrap();
    let setup = setup(temporary.path());
    let before = bindings(&setup);
    let (ok, out) = run(&setup, &[]);
    assert!(ok, "{out}");
    let log = calls(&setup);
    assert!(
        log.contains("omarchy plugin add https://github.com/MASH2RAFI/omablade.git --enable --yes"),
        "{log}"
    );
    assert!(log.contains(ROLE), "{log}");
    assert_eq!(
        bindings(&setup),
        before,
        "the script leaves bindings.lua to the reversible role"
    );
    let link = setup.home.join(".local/bin/omablade");
    assert_eq!(
        fs::read_link(&link).unwrap(),
        setup
            .home
            .join(".config/omarchy/plugins/mash2rafi.omablade/omablade")
    );

    let (ok, out) = run(&setup, &[]);
    assert!(ok, "{out}");
    assert!(out.contains("not a git checkout"), "{out}");
    assert!(calls(&setup).contains("omarchy plugin enable mash2rafi.omablade"));
}

#[test]
fn existing_omablade_bindings_are_kept_unless_forced_and_no_bindings_skips_the_role() {
    let temporary = tempdir().unwrap();
    let setup = setup(temporary.path());
    let own = "o.bind(\"SUPER + SHIFT + F\", \"Blade\", \"omarchy-shell mash2rafi.omablade.control toggleBladeFocus left\")\n";
    fs::write(setup.home.join(".config/hypr/bindings.lua"), own).unwrap();
    let (ok, out) = run(&setup, &[]);
    assert!(ok, "{out}");
    assert!(out.contains("keeping your bindings"), "{out}");
    assert!(!calls(&setup).contains(ROLE));

    let (ok, out) = run(&setup, &["--force-bindings"]);
    assert!(ok, "{out}");
    assert!(calls(&setup).contains(ROLE));
    assert_eq!(bindings(&setup), own);

    let quiet_root = tempdir().unwrap();
    let quiet = self::setup(quiet_root.path());
    let (ok, out) = run(&quiet, &["--no-bindings"]);
    assert!(ok, "{out}");
    assert!(!calls(&quiet).contains(ROLE));
}

#[test]
fn a_dry_run_changes_nothing_and_fileblade_is_disabled_for_real_runs() {
    let temporary = tempdir().unwrap();
    let setup = setup(temporary.path());
    fs::create_dir_all(
        setup
            .home
            .join(".config/omarchy/plugins/data-goblin.fileblade"),
    )
    .unwrap();
    let before = bindings(&setup);
    let (ok, out) = run(&setup, &["--dry-run"]);
    assert!(ok, "{out}");
    assert!(calls(&setup).is_empty(), "{}", calls(&setup));
    assert_eq!(bindings(&setup), before);
    assert!(!setup.home.join(".local/bin/omablade").exists());
    assert!(out.contains("would run: omarchy plugin add"), "{out}");

    let (ok, out) = run(&setup, &[]);
    assert!(ok, "{out}");
    assert!(calls(&setup).contains("omarchy plugin disable data-goblin.fileblade"));
    let (ok, _) = run(&setup, &["--keep-fileblade"]);
    assert!(ok);
    assert_eq!(
        calls(&setup)
            .matches("plugin disable data-goblin.fileblade")
            .count(),
        1
    );
}

#[test]
fn a_command_that_is_not_ours_is_never_replaced() {
    let temporary = tempdir().unwrap();
    let setup = setup(temporary.path());
    let link = setup.home.join(".local/bin/omablade");
    fs::create_dir_all(link.parent().unwrap()).unwrap();
    fs::write(&link, "#!/bin/sh\necho mine\n").unwrap();
    let (ok, out) = run(&setup, &["--no-bindings"]);
    assert!(ok, "{out}");
    assert_eq!(fs::read_to_string(&link).unwrap(), "#!/bin/sh\necho mine\n");
    assert!(out.contains("is not a link"), "{out}");
}

#[test]
fn unknown_options_are_refused() {
    let temporary = tempdir().unwrap();
    let setup = setup(temporary.path());
    let (ok, out) = run(&setup, &["--yolo"]);
    assert!(!ok);
    assert!(out.contains("unknown option"), "{out}");
    assert!(calls(&setup).is_empty());
}

#[test]
fn fileblade_era_bindings_are_migrated_instead_of_replaced() {
    let temporary = tempdir().unwrap();
    let setup = setup(temporary.path());
    fs::write(
        setup.home.join(".config/hypr/bindings.lua"),
        "local call = \"OMARCHY_SHELL_IPC_TIMEOUT=0.4s omarchy-shell data-goblin.fileblade.control \" .. method\n",
    )
    .unwrap();
    let (ok, out) = run(&setup, &[]);
    assert!(ok, "{out}");
    assert!(
        calls(&setup).contains("omablade _backend bindings-migrate"),
        "{}",
        calls(&setup)
    );
    assert!(!calls(&setup).contains(ROLE));
}
