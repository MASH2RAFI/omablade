use serde_json::Value;
use std::fs;
use std::path::Path;
use std::process::Command;
use tempfile::tempdir;

fn backend(root: &Path, args: &[&str]) -> (bool, Value, String) {
    let output = Command::new(env!("CARGO_BIN_EXE_omablade"))
        .args(["_backend", "network-storage"])
        .args(args)
        .env("HOME", root.join("home"))
        .env("XDG_STATE_HOME", root.join("state"))
        .env("XDG_RUNTIME_DIR", root.join("runtime"))
        .output()
        .unwrap();
    let stdout = String::from_utf8_lossy(&output.stdout);
    let document = stdout
        .lines()
        .rev()
        .find(|line| !line.trim().is_empty())
        .and_then(|line| serde_json::from_str(line).ok())
        .unwrap_or(Value::Null);
    (
        output.status.success(),
        document,
        String::from_utf8_lossy(&output.stderr).into_owned(),
    )
}

fn slow_rsync(root: &Path, pause: &str) -> Option<String> {
    use std::os::unix::fs::PermissionsExt;
    let found = Command::new("sh")
        .args(["-c", "command -v rsync"])
        .output()
        .ok()?;
    let real = String::from_utf8(found.stdout).ok()?;
    if real.trim().is_empty() {
        return None;
    }
    let bin = root.join("bin");
    fs::create_dir_all(&bin).unwrap();
    let fake = bin.join("rsync");
    fs::write(
        &fake,
        format!("#!/bin/sh\nprintf '     1,024  50%%    1.00MB/s    0:00:02\\r'\nsleep {pause}\nexec {} \"$@\"\n", real.trim()),
    )
    .unwrap();
    fs::set_permissions(&fake, fs::Permissions::from_mode(0o755)).unwrap();
    Some(format!(
        "{}:{}",
        bin.display(),
        std::env::var("PATH").unwrap_or_default()
    ))
}

fn mirror(root: &Path, relative: &str) -> std::path::PathBuf {
    root.join("home/.sync/_local")
        .join(root.strip_prefix("/").unwrap())
        .join(relative)
}

fn local_folder(root: &Path) -> String {
    let source = root.join("reports");
    fs::create_dir_all(source.join("2026")).unwrap();
    fs::write(source.join("summary.txt"), "quarterly").unwrap();
    fs::write(source.join("2026/october.csv"), "a,b\n1,2\n").unwrap();
    source.to_str().unwrap().to_string()
}

#[test]
fn a_synced_folder_is_listed_checked_and_unsynced_without_touching_the_original() {
    if Command::new("rsync").arg("--version").output().is_err() {
        return;
    }
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let source = local_folder(root);
    let copy = mirror(root, "reports");

    let (_, before, _) = backend(root, &["status", "--", &source]);
    assert_eq!(before["synced"], false, "{before}");

    let (ok, synced, stderr) = backend(root, &["sync", "--", &source]);
    assert!(ok, "{stderr}");
    assert_eq!(synced["ok"], true, "{synced}");
    assert_eq!(
        fs::read_to_string(copy.join("2026/october.csv")).unwrap(),
        "a,b\n1,2\n"
    );

    let (_, status, _) = backend(root, &["status", "--", &source]);
    assert_eq!(status["synced"], true, "{status}");
    let (_, check, _) = backend(root, &["check", "--", &source]);
    assert_eq!(check["state"], "synced", "{check}");

    fs::write(Path::new(&source).join("late.txt"), "new").unwrap();
    let (_, partial, _) = backend(root, &["check", "--", &source]);
    assert_eq!(partial["state"], "partial", "{partial}");

    let (_, listing, _) = backend(root, &["list", "--", root.to_str().unwrap()]);
    let reports = listing["entries"]
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["name"] == "reports")
        .cloned()
        .unwrap();
    assert_eq!(reports["kind"], "d");
    assert_eq!(reports["synced"], true, "{listing}");

    let (_, active, _) = backend(root, &["active"]);
    assert_eq!(active["active"], false, "{active}");

    let (ok, removed, stderr) = backend(root, &["unsync", "--", &source]);
    assert!(ok, "{stderr}");
    assert_eq!(removed["results"][0]["state"], "unsynced", "{removed}");
    assert!(!copy.exists());
    assert!(Path::new(&source).join("summary.txt").is_file());

    let (_, again, _) = backend(root, &["unsync", "--", &source]);
    assert_eq!(again["results"][0]["state"], "not-synced", "{again}");
}

#[test]
fn bad_addresses_and_paths_are_refused_and_saved_servers_can_be_forgotten() {
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    for address in ["", "-o", "no-scheme", "smb://bad\nhost"] {
        let (ok, _, stderr) = backend(root, &["connect", "--", address]);
        assert!(!ok, "accepted {address:?}");
        assert!(stderr.contains("not a server address"), "{stderr}");
    }
    for path in ["relative/path", "/tmp/../etc"] {
        let (ok, _, stderr) = backend(root, &["unsync", "--", path]);
        assert!(!ok, "accepted {path:?}");
        assert!(stderr.contains("not an absolute path"), "{stderr}");
    }

    let saved = root.join("state/omarchy/omablade/networkstorage/saved-shares");
    fs::create_dir_all(saved.parent().unwrap()).unwrap();
    fs::write(&saved, "smb://nas.local/media\nsftp://user@host/home\n").unwrap();
    let (_, listed, _) = backend(root, &["saved"]);
    assert_eq!(
        listed["servers"],
        serde_json::json!(["smb://nas.local/media", "sftp://user@host/home"])
    );
    let (_, forgotten, _) = backend(root, &["forget", "--", "smb://nas.local/media"]);
    assert_eq!(
        forgotten["servers"],
        serde_json::json!(["sftp://user@host/home"])
    );

    let (ok, _, stderr) = backend(root, &["pause"]);
    assert!(!ok);
    assert!(stderr.contains("nothing is syncing"), "{stderr}");
}

#[test]
fn gvfs_mounts_are_reported_with_their_server_address() {
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let share = root.join("runtime/gvfs/smb-share:server=nas.local,share=media");
    fs::create_dir_all(&share).unwrap();
    let (ok, shares, stderr) = backend(root, &["shares"]);
    assert!(ok, "{stderr}");
    let found = shares["shares"]
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["path"] == share.to_str().unwrap())
        .cloned()
        .unwrap();
    assert_eq!(found["uri"], "smb://nas.local/media");
}

#[test]
fn listings_put_folders_first_and_phones_are_not_network_storage() {
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let folder = root.join("listing");
    fs::create_dir_all(folder.join("beta")).unwrap();
    fs::create_dir_all(folder.join("Alpha")).unwrap();
    fs::write(folder.join("aardvark.txt"), "x").unwrap();
    fs::write(folder.join(".hidden"), "x").unwrap();
    let (_, listing, _) = backend(root, &["list", "--", folder.to_str().unwrap()]);
    let names: Vec<&str> = listing["entries"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| entry["name"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["Alpha", "beta", ".hidden", "aardvark.txt"]);

    fs::create_dir_all(root.join("runtime/gvfs/mtp:host=Phone_1234")).unwrap();
    fs::create_dir_all(root.join("runtime/gvfs/sftp:host=box.local,user=me")).unwrap();
    let (_, shares, _) = backend(root, &["shares"]);
    let uris: Vec<&str> = shares["shares"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| entry["uri"].as_str().unwrap())
        .collect();
    assert_eq!(uris, ["sftp://me@box.local"]);
}

#[test]
fn remembering_a_server_twice_keeps_one_entry_at_the_top() {
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    backend(root, &["remember", "--", "smb://nas.local/"]);
    backend(root, &["remember", "--", "sftp://box.local/home"]);
    let (_, saved, _) = backend(root, &["remember", "--", "smb://nas.local"]);
    assert_eq!(
        saved["servers"],
        serde_json::json!(["smb://nas.local", "sftp://box.local/home"])
    );
    let (_, forgotten, _) = backend(root, &["forget", "--", "smb://nas.local/"]);
    assert_eq!(
        forgotten["servers"],
        serde_json::json!(["sftp://box.local/home"])
    );
}

#[test]
fn a_running_transfer_can_be_paused_resumed_and_cancelled_and_blocks_unsync() {
    use std::os::unix::process::CommandExt;
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let state = root.join("state/omarchy/omablade/networkstorage");
    fs::create_dir_all(&state).unwrap();
    let mut transfer = Command::new("sh")
        .args(["-c", "sleep 30; :", "network-storage", "run-queue"])
        .process_group(0)
        .spawn()
        .unwrap();
    fs::write(state.join("runner.pid"), transfer.id().to_string()).unwrap();
    fs::write(state.join("target"), "/srv/share/movies").unwrap();
    fs::write(
        state.join("progress"),
        r#"{"percent":42,"bytes":"1,024","rate":"1.0MB/s","eta":"0:00:09"}"#,
    )
    .unwrap();

    let (_, active, _) = backend(root, &["active"]);
    assert_eq!(active["active"], true, "{active}");
    assert_eq!(active["path"], "/srv/share/movies");
    assert_eq!(active["paused"], false);
    assert_eq!(active["progress"]["percent"], 42);

    let (ok, _, stderr) = backend(root, &["unsync", "--", "/srv/share/movies"]);
    assert!(!ok);
    assert!(stderr.contains("a sync is running"), "{stderr}");
    let (ok, _, stderr) = backend(root, &["sync", "--", "/srv/share/movies"]);
    assert!(!ok);
    assert!(stderr.contains("already running"), "{stderr}");

    let (ok, paused, stderr) = backend(root, &["pause"]);
    assert!(ok, "{stderr}");
    assert_eq!(paused["state"], "paused");
    let mut stopped = false;
    for _ in 0..50 {
        let (_, active, _) = backend(root, &["active"]);
        if active["paused"] == true {
            stopped = true;
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert!(stopped, "pause did not stop the transfer");

    let (ok, _, stderr) = backend(root, &["resume"]);
    assert!(ok, "{stderr}");
    let (ok, cancelled, stderr) = backend(root, &["cancel"]);
    assert!(ok, "{stderr}");
    assert_eq!(cancelled["state"], "cancelled");
    let status = transfer.wait().unwrap();
    assert!(!status.success());
    assert!(!state.join("runner.pid").exists());
    let (_, idle, _) = backend(root, &["active"]);
    assert_eq!(idle["active"], false, "{idle}");
}

#[test]
fn syncing_several_paths_reports_one_rising_percentage() {
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let Some(search) = slow_rsync(root, "1") else {
        return;
    };
    let mut paths = Vec::new();
    for name in ["first", "second"] {
        let folder = root.join(name);
        fs::create_dir_all(&folder).unwrap();
        fs::write(folder.join("data.bin"), vec![7u8; 512 * 1024]).unwrap();
        paths.push(folder.to_str().unwrap().to_string());
    }
    let output = Command::new(env!("CARGO_BIN_EXE_omablade"))
        .args(["_backend", "network-storage", "sync", "--"])
        .args(&paths)
        .env("HOME", root.join("home"))
        .env("XDG_STATE_HOME", root.join("state"))
        .env("XDG_RUNTIME_DIR", root.join("runtime"))
        .env("PATH", &search)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let percents: Vec<u64> = String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter_map(|line| serde_json::from_str::<Value>(line).ok())
        .filter_map(|frame| frame["percent"].as_u64())
        .collect();
    assert!(!percents.is_empty());
    assert!(
        percents.windows(2).all(|pair| pair[0] <= pair[1]),
        "{percents:?}"
    );
    assert_eq!(*percents.last().unwrap(), 100);
    assert!(percents.contains(&25), "{percents:?}");
    assert!(percents.contains(&75), "{percents:?}");
    assert!(mirror(root, "second/data.bin").is_file());
}

#[test]
fn a_sync_keeps_running_and_reports_its_result_after_the_backend_dies() {
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let Some(path) = slow_rsync(root, "2") else {
        return;
    };
    let source = local_folder(root);
    let mut request = Command::new(env!("CARGO_BIN_EXE_omablade"))
        .args(["_backend", "network-storage", "sync", "--", &source])
        .env("HOME", root.join("home"))
        .env("XDG_STATE_HOME", root.join("state"))
        .env("XDG_RUNTIME_DIR", root.join("runtime"))
        .env("PATH", &path)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .unwrap();
    let mut seen = Value::Null;
    for _ in 0..200 {
        let (_, active, _) = backend(root, &["active"]);
        if active["progress"]["percent"] == 50 {
            seen = active;
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    assert_eq!(seen["active"], true, "{seen}");
    assert_eq!(seen["path"], source.as_str());
    request.kill().unwrap();
    request.wait().unwrap();

    let (_, still, _) = backend(root, &["active"]);
    assert_eq!(
        still["active"], true,
        "the transfer died with its request: {still}"
    );
    let mut finished = Value::Null;
    for _ in 0..500 {
        let (_, active, _) = backend(root, &["active"]);
        if active["active"] == false {
            finished = active;
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert_eq!(finished["last"]["ok"], true, "{finished}");
    assert!(mirror(root, "reports/2026/october.csv").is_file());
}

#[test]
fn an_interrupted_file_resumes_from_its_partial_copy() {
    if Command::new("rsync").arg("--version").output().is_err() {
        return;
    }
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let source = root.join("film.mkv");
    let body: Vec<u8> = (0..1_000_000u32).map(|index| (index % 251) as u8).collect();
    fs::write(&source, &body).unwrap();
    let partials = mirror(root, ".rsync-partial");
    fs::create_dir_all(&partials).unwrap();
    fs::write(partials.join("film.mkv"), vec![0u8; 400_000]).unwrap();

    let (ok, synced, stderr) = backend(root, &["sync", "--", source.to_str().unwrap()]);
    assert!(ok, "{stderr}");
    assert_eq!(synced["ok"], true, "{synced}");
    let copy = fs::read(mirror(root, "film.mkv")).unwrap();
    assert_eq!(copy.len(), body.len());
    assert!(
        copy[..400_000].iter().all(|byte| *byte == 0),
        "the kept part was copied again instead of resumed"
    );
    assert_eq!(&copy[400_000..], &body[400_000..]);
    assert!(!partials.exists());
}

#[test]
fn unsync_never_follows_a_symlink_out_of_the_sync_folder() {
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let precious = root.join("precious");
    fs::create_dir_all(precious.join("Documents")).unwrap();
    fs::write(precious.join("Documents/thesis.tex"), "years of work").unwrap();
    let source = root.join("share/evil/Documents");
    fs::create_dir_all(&source).unwrap();
    let mirrored = root
        .join("home/.sync/_local")
        .join(root.join("share").strip_prefix("/").unwrap());
    fs::create_dir_all(&mirrored).unwrap();
    std::os::unix::fs::symlink(&precious, mirrored.join("evil")).unwrap();

    for verb in ["unsync", "sync"] {
        let (ok, document, stderr) = backend(root, &[verb, "--", source.to_str().unwrap()]);
        assert!(
            !ok || document["results"][0]["error"].is_string(),
            "{verb} went through a symlink: {document} {stderr}"
        );
    }
    assert_eq!(
        fs::read_to_string(precious.join("Documents/thesis.tex")).unwrap(),
        "years of work"
    );
}

#[test]
fn a_stale_runner_id_never_signals_an_unrelated_process() {
    use std::os::unix::process::CommandExt;
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let state = root.join("state/omarchy/omablade/networkstorage");
    fs::create_dir_all(&state).unwrap();
    let mut bystander = Command::new("sleep")
        .arg("30")
        .process_group(0)
        .spawn()
        .unwrap();
    fs::write(state.join("runner.pid"), bystander.id().to_string()).unwrap();
    let (_, active, _) = backend(root, &["active"]);
    assert_eq!(active["active"], false, "{active}");
    for verb in ["pause", "cancel"] {
        let (ok, _, _) = backend(root, &[verb]);
        assert!(!ok, "{verb} signalled a process that is not a sync");
    }
    std::thread::sleep(std::time::Duration::from_millis(100));
    assert!(
        bystander.try_wait().unwrap().is_none(),
        "the bystander was killed"
    );
    bystander.kill().unwrap();
    bystander.wait().unwrap();
}

#[test]
fn two_local_folders_with_the_same_name_keep_separate_copies() {
    if Command::new("rsync").arg("--version").output().is_err() {
        return;
    }
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    for (folder, body) in [("one/docs", "first"), ("two/docs", "second")] {
        fs::create_dir_all(root.join(folder)).unwrap();
        fs::write(root.join(folder).join("note.txt"), body).unwrap();
    }
    for folder in ["one/docs", "two/docs"] {
        let (ok, _, stderr) = backend(root, &["sync", "--", root.join(folder).to_str().unwrap()]);
        assert!(ok, "{stderr}");
    }
    let (_, removed, _) = backend(
        root,
        &["unsync", "--", root.join("one/docs").to_str().unwrap()],
    );
    assert_eq!(removed["results"][0]["state"], "unsynced", "{removed}");
    let (_, second, _) = backend(
        root,
        &["status", "--", root.join("two/docs").to_str().unwrap()],
    );
    assert_eq!(
        second["synced"], true,
        "un-syncing one folder removed the other's copy"
    );
}

#[test]
fn only_one_sync_runs_when_several_start_at_once_and_the_runner_refuses_a_second_start() {
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let Some(search) = slow_rsync(root, "2") else {
        return;
    };
    let source = local_folder(root);
    let mut children: Vec<_> = (0..4)
        .map(|_| {
            Command::new(env!("CARGO_BIN_EXE_omablade"))
                .args(["_backend", "network-storage", "sync", "--", &source])
                .env("HOME", root.join("home"))
                .env("XDG_STATE_HOME", root.join("state"))
                .env("XDG_RUNTIME_DIR", root.join("runtime"))
                .env("PATH", &search)
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::piped())
                .spawn()
                .unwrap()
        })
        .collect();
    std::thread::sleep(std::time::Duration::from_millis(500));
    let runners = Command::new("pgrep")
        .args(["-f", "network-storage run-queue"])
        .output()
        .unwrap();
    let ours = String::from_utf8_lossy(&runners.stdout)
        .lines()
        .filter(|pid| {
            fs::read_to_string(format!("/proc/{pid}/environ"))
                .map(|environ| environ.contains(root.to_str().unwrap()))
                .unwrap_or(false)
        })
        .count();
    let (ok, _, stderr) = backend(root, &["run-queue"]);
    assert!(!ok, "a second runner started");
    assert!(stderr.contains("already running"), "{stderr}");
    let outcomes: Vec<bool> = children
        .iter_mut()
        .map(|child| child.wait().unwrap().success())
        .collect();
    assert_eq!(ours, 1, "{ours} runners for one folder");
    assert_eq!(outcomes.iter().filter(|ok| **ok).count(), 1, "{outcomes:?}");
}

#[test]
fn garbage_in_the_state_folder_is_survived() {
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let state = root.join("state/omarchy/omablade/networkstorage");
    fs::create_dir_all(&state).unwrap();
    for (name, body) in [
        ("runner.pid", "not a pid"),
        ("queue", "{\"oops\":"),
        ("result", "\u{0}\u{1}binary"),
        ("progress", "[]"),
        (
            "saved-shares",
            "smb://ok/share\n\u{0}\n-oProxyCommand=evil\n",
        ),
    ] {
        fs::write(state.join(name), body).unwrap();
    }
    let (ok, active, stderr) = backend(root, &["active"]);
    assert!(ok, "{stderr}");
    assert_eq!(active["active"], false);
    let (ok, saved, _) = backend(root, &["saved"]);
    assert!(ok);
    assert_eq!(saved["servers"], serde_json::json!(["smb://ok/share"]));
    let (ok, _, stderr) = backend(root, &["run-queue"]);
    assert!(!ok);
    assert!(!stderr.contains("panicked"), "{stderr}");
}

#[test]
fn a_folder_holding_the_sync_folder_is_never_copied_into_itself() {
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    fs::create_dir_all(root.join("home/.sync")).unwrap();
    fs::write(root.join("home/notes.txt"), "x").unwrap();
    for target in [root.join("home"), root.join("home/.sync"), "/".into()] {
        let (ok, _, stderr) = backend(root, &["sync", "--", target.to_str().unwrap()]);
        assert!(!ok, "synced {}", target.display());
        assert!(
            stderr.contains("sync folder") || stderr.contains("not an absolute path"),
            "{stderr}"
        );
    }
    assert!(
        fs::read_dir(root.join("home/.sync"))
            .unwrap()
            .next()
            .is_none()
    );
}
