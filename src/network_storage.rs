use crate::command::{CommandSpec, which};
use crate::common::expanded_path;
use crate::mounts::mountinfo::{MountRecord, MountTable};
use crate::{AppError, AppResult};
use clap::{Args, Subcommand};
use rustix::process::{Pid, Signal, kill_process_group, test_kill_process_group};
use serde_json::{Value, json};
use std::fs;
use std::io::Read;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

const NETWORK_FILESYSTEMS: [&str; 16] = [
    "cifs",
    "smb",
    "smb3",
    "smbfs",
    "nfs",
    "nfs4",
    "fuse.sshfs",
    "fuse.gvfsd-fuse",
    "fuse.rclone",
    "9p",
    "afpfs",
    "davfs",
    "davfs2",
    "glusterfs",
    "ceph",
    "fuse.ceph",
];
const GIO_TIMEOUT: Duration = Duration::from_secs(20);
const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(8);
const MAX_DISCOVERED: usize = 32;
const MOUNT_TIMEOUT: Duration = Duration::from_secs(180);
const RSYNC_DRY_RUN_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_LISTED: usize = 2000;
const MAX_URI: usize = 2048;
const MAX_SAVED: usize = 64;

#[derive(Clone, Debug, Args)]
pub struct NetworkStorageArgs {
    #[command(subcommand)]
    pub command: NetworkStorageCommand,
}

#[derive(Clone, Debug, Subcommand)]
pub enum NetworkStorageCommand {
    Shares,
    Saved,
    Discover,
    Browse {
        uri: String,
    },
    Connect {
        uri: String,
    },
    Forget {
        uri: String,
    },
    Remember {
        uri: String,
    },
    Disconnect {
        path: String,
    },
    List {
        path: String,
    },
    Status {
        path: String,
    },
    Check {
        path: String,
    },
    Sync {
        paths: Vec<String>,
    },
    Unsync {
        paths: Vec<String>,
    },
    Pause,
    Resume,
    Cancel,
    Active,
    #[command(hide = true)]
    RunQueue,
}

pub fn run(
    args: NetworkStorageArgs,
    cancelled: &AtomicBool,
    progress: &mut dyn FnMut(Value) -> AppResult<()>,
) -> AppResult<Value> {
    match args.command {
        NetworkStorageCommand::Shares => shares(),
        NetworkStorageCommand::Saved => Ok(json!({"ok": true, "servers": saved()})),
        NetworkStorageCommand::Discover => discover(cancelled),
        NetworkStorageCommand::Browse { uri } => {
            let uri = checked_uri(&uri)?;
            Ok(
                json!({"ok": true, "uri": uri, "shares": gio_children(&uri, GIO_TIMEOUT, cancelled)?}),
            )
        }
        NetworkStorageCommand::Connect { uri } => connect(&checked_uri(&uri)?, cancelled),
        NetworkStorageCommand::Forget { uri } => {
            forget(&uri)?;
            Ok(json!({"ok": true, "servers": saved()}))
        }
        NetworkStorageCommand::Remember { uri } => {
            let servers = remember(&checked_uri(&uri)?)?;
            Ok(json!({"ok": true, "servers": servers}))
        }
        NetworkStorageCommand::Disconnect { path } => disconnect(&checked_path(&path)?, cancelled),
        NetworkStorageCommand::List { path } => list(&checked_path(&path)?),
        NetworkStorageCommand::Status { path } => {
            let path = checked_path(&path)?;
            let synced = fs::symlink_metadata(local_copy(&path)?).is_ok();
            Ok(json!({"ok": true, "path": path, "synced": synced}))
        }
        NetworkStorageCommand::Check { path } => {
            let path = checked_path(&path)?;
            Ok(json!({"ok": true, "path": path, "state": sync_state(&path, cancelled)?}))
        }
        NetworkStorageCommand::Sync { paths } => {
            let paths = checked_paths(&paths)?;
            outside_sync_root(&paths)?;
            sync(&paths, cancelled, progress)
        }
        NetworkStorageCommand::Unsync { paths } => unsync(&checked_paths(&paths)?),
        NetworkStorageCommand::Pause => signal_transfer(&[Signal::STOP], "paused"),
        NetworkStorageCommand::Resume => signal_transfer(&[Signal::CONT], "resumed"),
        NetworkStorageCommand::Cancel => cancel(),
        NetworkStorageCommand::Active => Ok(active()),
        NetworkStorageCommand::RunQueue => run_queue(),
    }
}

fn state_dir() -> PathBuf {
    crate::paths::xdg_home("XDG_STATE_HOME", "~/.local/state")
        .join("omarchy/omablade/networkstorage")
}

fn sync_root() -> PathBuf {
    expanded_path("~/.sync")
}

fn gvfs_root() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .unwrap_or_else(|| {
            PathBuf::from(format!("/run/user/{}", rustix::process::getuid().as_raw()))
        })
        .join("gvfs")
}

fn checked_uri(raw: &str) -> AppResult<String> {
    let uri = raw.trim();
    let scheme = uri
        .split_once("://")
        .map(|(scheme, _)| scheme)
        .unwrap_or("");
    if uri.is_empty()
        || uri.len() > MAX_URI
        || uri.starts_with('-')
        || uri.chars().any(char::is_control)
        || scheme.is_empty()
        || !scheme
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || "+-.".contains(character))
    {
        return Err(AppError::invalid(format!("not a server address: {raw}")));
    }
    Ok(uri.to_string())
}

fn checked_path(raw: &str) -> AppResult<PathBuf> {
    let path = PathBuf::from(raw.trim_end_matches('/'));
    if !path.is_absolute()
        || path
            .components()
            .any(|component| matches!(component, Component::ParentDir | Component::CurDir))
    {
        return Err(AppError::invalid(format!("not an absolute path: {raw}")));
    }
    Ok(path)
}

fn checked_paths(raw: &[String]) -> AppResult<Vec<PathBuf>> {
    if raw.is_empty() {
        return Err(AppError::invalid("no paths given"));
    }
    raw.iter().map(|path| checked_path(path)).collect()
}

fn outside_sync_root(paths: &[PathBuf]) -> AppResult<()> {
    let root = sync_root();
    let root = fs::canonicalize(&root).unwrap_or(root);
    for path in paths {
        let resolved = fs::canonicalize(path).unwrap_or_else(|_| path.clone());
        if resolved.starts_with(&root) || root.starts_with(&resolved) {
            return Err(AppError::invalid(format!(
                "refusing to sync {}: it is or holds the sync folder {}",
                path.display(),
                root.display()
            )));
        }
    }
    Ok(())
}

fn mount_of(table: &MountTable, path: &Path) -> Option<MountRecord> {
    table
        .records()
        .iter()
        .filter(|record| path.starts_with(&record.mountpoint))
        .max_by_key(|record| record.mountpoint.as_os_str().len())
        .cloned()
}

fn is_network(record: &MountRecord) -> bool {
    NETWORK_FILESYSTEMS.contains(&record.filesystem.as_str())
}

fn share_root(table: &MountTable, path: &Path) -> Option<PathBuf> {
    let record = mount_of(table, path).filter(is_network)?;
    let gvfs = gvfs_root();
    if record.mountpoint == gvfs {
        let first = path.strip_prefix(&gvfs).ok()?.components().next()?;
        return Some(gvfs.join(first));
    }
    Some(record.mountpoint)
}

fn local_copy_in(table: &MountTable, path: &Path) -> AppResult<PathBuf> {
    let root = sync_root();
    let name = path
        .file_name()
        .ok_or_else(|| AppError::invalid(format!("no name: {}", path.display())))?;
    Ok(match share_root(table, path) {
        Some(share) => {
            let id = share
                .file_name()
                .ok_or_else(|| AppError::invalid(format!("no share name: {}", share.display())))?;
            match path.strip_prefix(&share) {
                Ok(rest) if !rest.as_os_str().is_empty() => root.join(id).join(rest),
                _ => root.join(id),
            }
        }
        None => {
            let _ = name;
            root.join("_local")
                .join(path.strip_prefix("/").unwrap_or(path))
        }
    })
}

fn no_symlink_below_root(copy: &Path, include_last: bool) -> AppResult<()> {
    let root = sync_root();
    let rest = copy
        .strip_prefix(&root)
        .map_err(|_| AppError::invalid(format!("refusing {}: outside ~/.sync", copy.display())))?;
    let mut current = root.clone();
    let parts: Vec<_> = rest.components().collect();
    for (index, part) in parts.iter().enumerate() {
        current.push(part);
        if index + 1 == parts.len() && !include_last {
            break;
        }
        match fs::symlink_metadata(&current) {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                return Err(AppError::invalid(format!(
                    "refusing {}: {} is a symbolic link",
                    copy.display(),
                    current.display()
                )));
            }
            Ok(_) => {}
            Err(_) => break,
        }
    }
    Ok(())
}

fn local_copy(path: &Path) -> AppResult<PathBuf> {
    local_copy_in(&MountTable::read()?, path)
}

fn gio() -> AppResult<PathBuf> {
    which("gio").ok_or_else(|| AppError::command("gio is not installed (glib2)"))
}

fn gio_run(
    arguments: &[&str],
    timeout: Duration,
    cancelled: &AtomicBool,
) -> AppResult<(bool, String, String)> {
    let output = CommandSpec::new(gio()?)
        .args(arguments.iter().copied())
        .timeout(timeout)
        .run_cancellable(cancelled)?;
    Ok((
        output.status.success(),
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).trim().to_string(),
    ))
}

fn gio_children(uri: &str, timeout: Duration, cancelled: &AtomicBool) -> AppResult<Vec<Value>> {
    let (ok, stdout, stderr) = gio_run(
        &[
            "list",
            "-a",
            "standard::display-name,standard::target-uri",
            "--",
            uri,
        ],
        timeout,
        cancelled,
    )?;
    if !ok {
        return Err(AppError::command(if stderr.is_empty() {
            format!("could not browse {uri}")
        } else {
            stderr.trim_start_matches("gio: ").to_string()
        }));
    }
    let mut rows = Vec::new();
    for line in stdout.lines().take(MAX_LISTED) {
        let mut name = line.split('\t').next().unwrap_or("").to_string();
        let mut target = String::new();
        for field in line.split_whitespace() {
            if let Some(value) = field.strip_prefix("standard::target-uri=") {
                target = value.to_string();
            }
        }
        if let Some((_, display)) = line.split_once("standard::display-name=") {
            let display = display.split(" standard::").next().unwrap_or("").trim();
            if !display.is_empty() {
                name = display.to_string();
            }
        }
        if name.is_empty() {
            continue;
        }
        if target.is_empty() {
            target = format!("{}/{}", uri.trim_end_matches('/'), name);
        }
        rows.push(json!({"name": name, "uri": target}));
    }
    Ok(rows)
}

fn server_root(uri: &str) -> Option<String> {
    let (scheme, rest) = uri.split_once("://")?;
    let authority = rest.split('/').next().filter(|host| !host.is_empty())?;
    Some(format!("{scheme}://{authority}/"))
}

fn tailnet_servers(cancelled: &AtomicBool) -> Vec<(String, String, &'static str)> {
    let Some(program) = which("tailscale") else {
        return Vec::new();
    };
    let Ok(output) = CommandSpec::new(program)
        .args(["status", "--json"])
        .timeout(Duration::from_secs(3))
        .limits(8 * 1024 * 1024, 8192)
        .stop_on_output_limit()
        .run_cancellable(cancelled)
    else {
        return Vec::new();
    };
    let Ok(status) = serde_json::from_slice::<Value>(&output.stdout) else {
        return Vec::new();
    };
    let Ok(peers) = crate::locations::tailnet::candidates(&status) else {
        return Vec::new();
    };
    let address = |host: &str| -> Option<String> {
        status["Peer"].as_object()?.values().find_map(|peer| {
            let name = peer["DNSName"].as_str()?.trim_end_matches('.');
            if name != host {
                return None;
            }
            peer["TailscaleIPs"]
                .as_array()?
                .iter()
                .filter_map(|ip| ip.as_str()?.parse::<std::net::Ipv4Addr>().ok())
                .next()
                .map(|ip| ip.to_string())
        })
    };
    peers
        .into_iter()
        .filter(|peer| peer.online)
        .map(|peer| {
            let host = address(&peer.host).unwrap_or(peer.host);
            (
                peer.location.label.clone(),
                format!("smb://{host}/"),
                "tailnet",
            )
        })
        .collect()
}

fn discover(cancelled: &AtomicBool) -> AppResult<Value> {
    let mut candidates: Vec<(String, String, &'static str)> = Vec::new();
    if let Ok(found) = gio_children("network:///", DISCOVERY_TIMEOUT, cancelled) {
        for server in found {
            let uri = server["uri"].as_str().unwrap_or("").to_string();
            let name = server["name"].as_str().unwrap_or("").to_string();
            candidates.push((name, uri, "network"));
        }
    }
    if let Ok(connected) = shares() {
        for share in connected["shares"].as_array().into_iter().flatten() {
            if let Some(root) = share["uri"].as_str().and_then(server_root) {
                let host = root
                    .split("://")
                    .nth(1)
                    .unwrap_or("")
                    .trim_end_matches('/')
                    .to_string();
                candidates.push((host, root, "connected"));
            }
        }
    }
    candidates.extend(tailnet_servers(cancelled));
    let mut seen = std::collections::BTreeMap::new();
    for (name, uri, source) in candidates {
        let key = uri.trim_end_matches('/').to_string();
        if key.is_empty() || checked_uri(&uri).is_err() {
            continue;
        }
        let entry = seen.entry(key).or_insert((name.clone(), uri, source));
        if source == "tailnet" && !name.is_empty() {
            entry.0 = name;
            entry.2 = source;
        }
    }
    let servers: Vec<_> = seen.into_values().take(MAX_DISCOVERED).collect();
    let browsed: Vec<Option<Vec<Value>>> = thread::scope(|scope| {
        let handles: Vec<_> = servers
            .iter()
            .map(|(_, uri, _)| {
                scope.spawn(move || gio_children(uri, DISCOVERY_TIMEOUT, cancelled).ok())
            })
            .collect();
        handles
            .into_iter()
            .map(|handle| handle.join().ok().flatten())
            .collect()
    });
    let mut rows = Vec::new();
    for ((name, uri, source), shares) in servers.into_iter().zip(browsed) {
        let Some(shares) = shares.filter(|shares| !shares.is_empty()) else {
            continue;
        };
        rows.push(json!({"name": name, "uri": uri, "source": source, "shares": shares}));
    }
    rows.sort_by_cached_key(|row| row["name"].as_str().unwrap_or("").to_lowercase());
    Ok(json!({"ok": true, "servers": rows}))
}

fn gvfs_uri(name: &str) -> Option<String> {
    let (scheme, rest) = name.split_once(':')?;
    let mut fields = std::collections::BTreeMap::new();
    for pair in rest.split(',') {
        let (key, value) = pair.split_once('=')?;
        fields.insert(key, value);
    }
    let host = fields.get("server").or_else(|| fields.get("host"))?;
    let user = fields
        .get("user")
        .map(|user| format!("{user}@"))
        .unwrap_or_default();
    let port = fields
        .get("port")
        .map(|port| format!(":{port}"))
        .unwrap_or_default();
    let scheme = match scheme {
        "smb-share" | "smb-server" => "smb",
        "dav" if fields.get("ssl") == Some(&"true") => "davs",
        other => other,
    };
    let tail = fields
        .get("share")
        .or_else(|| fields.get("prefix"))
        .map(|value| format!("/{}", value.trim_start_matches('/')))
        .unwrap_or_default();
    Some(format!("{scheme}://{user}{host}{port}{tail}"))
}

const LOCAL_GVFS_SCHEMES: [&str; 10] = [
    "mtp", "gphoto2", "afc", "cdda", "burn", "archive", "computer", "trash", "recent", "admin",
];

fn network_gvfs(name: &str) -> bool {
    let scheme = name.split(':').next().unwrap_or("");
    !scheme.is_empty() && !LOCAL_GVFS_SCHEMES.contains(&scheme)
}

fn kernel_uri(record: &MountRecord) -> String {
    let source = record.source.as_str();
    if let Some(rest) = source.strip_prefix("//") {
        return format!("smb://{rest}");
    }
    if record.filesystem.starts_with("nfs")
        && let Some((host, path)) = source.split_once(':')
        && !host.is_empty()
        && path.starts_with('/')
    {
        return format!("nfs://{host}{path}");
    }
    if source.contains("://") {
        return source.to_string();
    }
    String::new()
}

fn shares() -> AppResult<Value> {
    let mut rows = Vec::new();
    let gvfs = gvfs_root();
    if let Ok(entries) = fs::read_dir(&gvfs) {
        let mut names: Vec<String> = entries
            .flatten()
            .filter(|entry| entry.path().is_dir())
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .filter(|name| network_gvfs(name))
            .collect();
        names.sort();
        for name in names {
            rows.push(json!({
                "path": gvfs.join(&name),
                "name": name,
                "uri": gvfs_uri(&name).unwrap_or_default(),
            }));
        }
    }
    let table = MountTable::read()?;
    for record in table.records() {
        if !is_network(record)
            || record.filesystem == "fuse.gvfsd-fuse"
            || record.mountpoint.starts_with(&gvfs)
        {
            continue;
        }
        rows.push(json!({
            "path": record.mountpoint,
            "name": record.mountpoint.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_else(|| record.mountpoint.display().to_string()),
            "uri": kernel_uri(record),
        }));
    }
    Ok(json!({"ok": true, "shares": rows}))
}

fn saved_path() -> PathBuf {
    state_dir().join("saved-shares")
}

fn saved() -> Vec<String> {
    fs::read_to_string(saved_path())
        .unwrap_or_default()
        .lines()
        .map(str::trim)
        .filter(|line| checked_uri(line).is_ok())
        .take(MAX_SAVED)
        .map(str::to_string)
        .collect()
}

fn write_saved(servers: &[String]) -> AppResult<()> {
    let path = saved_path();
    fs::create_dir_all(state_dir())?;
    let staged = path.with_extension("tmp");
    let mut text = servers.join("\n");
    if !text.is_empty() {
        text.push('\n');
    }
    fs::write(&staged, text)?;
    fs::rename(staged, path)?;
    Ok(())
}

fn same_server(left: &str, right: &str) -> bool {
    left.trim().trim_end_matches('/') == right.trim().trim_end_matches('/')
}

fn forget(uri: &str) -> AppResult<()> {
    let servers: Vec<String> = saved()
        .into_iter()
        .filter(|saved| !same_server(saved, uri))
        .collect();
    write_saved(&servers)
}

fn remember(uri: &str) -> AppResult<Vec<String>> {
    let mut servers: Vec<String> = saved()
        .into_iter()
        .filter(|saved| !same_server(saved, uri))
        .collect();
    servers.insert(0, uri.to_string());
    servers.truncate(MAX_SAVED);
    write_saved(&servers)?;
    Ok(servers)
}

fn connect(uri: &str, cancelled: &AtomicBool) -> AppResult<Value> {
    let (ok, stdout, stderr) = gio_run(&["mount", "--", uri], MOUNT_TIMEOUT, cancelled)?;
    let message = format!("{stdout} {stderr}");
    if !ok && !message.contains("already mounted") {
        if message.contains("Authentication Required") || message.contains("assword") {
            return Err(AppError::command(format!(
                "{uri} needs a user name and password; save them by connecting once from Files with \"Remember forever\", or put the user in the address (smb://user@server/share)"
            )));
        }
        return Err(AppError::command(if stderr.is_empty() {
            format!("could not connect to {uri}")
        } else {
            stderr.trim_start_matches("gio: ").to_string()
        }));
    }
    let servers = remember(uri)?;
    Ok(json!({"ok": true, "uri": uri, "servers": servers}))
}

fn disconnect(path: &Path, cancelled: &AtomicBool) -> AppResult<Value> {
    let target = path.to_string_lossy();
    let (ok, _, stderr) = gio_run(&["mount", "-u", "--", &target], MOUNT_TIMEOUT, cancelled)?;
    if !ok {
        return Err(AppError::command(if stderr.is_empty() {
            format!("could not disconnect {target}")
        } else {
            stderr.trim_start_matches("gio: ").to_string()
        }));
    }
    Ok(json!({"ok": true, "path": path}))
}

fn list(directory: &Path) -> AppResult<Value> {
    if !directory.is_dir() {
        return Err(AppError::invalid(format!(
            "not a directory: {}",
            directory.display()
        )));
    }
    let table = MountTable::read()?;
    let mut entries: Vec<_> = fs::read_dir(directory)?
        .flatten()
        .map(|entry| {
            let folder = entry.path().is_dir();
            (entry, folder)
        })
        .collect();
    entries.sort_by_cached_key(|(entry, folder)| {
        (!*folder, entry.file_name().to_string_lossy().to_lowercase())
    });
    let total = entries.len();
    let mut rows = Vec::new();
    for (entry, folder) in entries.into_iter().take(MAX_LISTED) {
        let path = entry.path();
        let synced = local_copy_in(&table, &path)
            .map(|copy| fs::symlink_metadata(copy).is_ok())
            .unwrap_or(false);
        rows.push(json!({
            "name": entry.file_name().to_string_lossy(),
            "kind": if folder { "d" } else { "f" },
            "synced": synced,
        }));
    }
    Ok(json!({"ok": true, "path": directory, "entries": rows, "total": total}))
}

fn sync_state(path: &Path, cancelled: &AtomicBool) -> AppResult<&'static str> {
    let copy = local_copy(path)?;
    if fs::symlink_metadata(&copy).is_err() {
        return Ok("not-synced");
    }
    if !path.is_dir() {
        return Ok("synced");
    }
    let rsync = which("rsync").ok_or_else(|| AppError::command("rsync is not installed"))?;
    let output = CommandSpec::new(rsync)
        .args([
            "-a".into(),
            "--dry-run".into(),
            "-i".into(),
            format!("{}/", path.display()),
            format!("{}/", copy.display()),
        ])
        .timeout(RSYNC_DRY_RUN_TIMEOUT)
        .limits(64 * 1024, 64 * 1024)
        .run_cancellable(cancelled)?;
    Ok(
        if output.stdout.iter().any(|byte| !byte.is_ascii_whitespace()) {
            "partial"
        } else {
            "synced"
        },
    )
}

fn unsync(paths: &[PathBuf]) -> AppResult<Value> {
    if transfer_group().is_some() {
        return Err(AppError::invalid(
            "a sync is running; cancel it before removing local copies",
        ));
    }
    let table = MountTable::read()?;
    let root = sync_root();
    let mut results = Vec::new();
    for path in paths {
        let outcome = match local_copy_in(&table, path) {
            Ok(copy) if copy.starts_with(&root) && copy != root => {
                match no_symlink_below_root(&copy, false) {
                    Err(error) => json!({"path": path, "error": error.to_string()}),
                    Ok(()) => match fs::symlink_metadata(&copy) {
                        Err(_) => json!({"path": path, "state": "not-synced"}),
                        Ok(metadata) => {
                            let removed = if metadata.is_dir() {
                                fs::remove_dir_all(&copy)
                            } else {
                                fs::remove_file(&copy)
                            };
                            match removed {
                                Ok(()) => json!({"path": path, "state": "unsynced"}),
                                Err(error) => {
                                    json!({"path": path, "error": format!("could not remove {}: {error}", copy.display())})
                                }
                            }
                        }
                    },
                }
            }
            Ok(copy) => {
                json!({"path": path, "error": format!("refusing to remove {}", copy.display())})
            }
            Err(error) => json!({"path": path, "error": error.to_string()}),
        };
        results.push(outcome);
    }
    let ok = results.iter().all(|result| result.get("error").is_none());
    Ok(json!({"ok": ok, "results": results}))
}

fn transfer_file(name: &str) -> PathBuf {
    state_dir().join(name)
}

fn write_state(name: &str, value: &Value) {
    let path = transfer_file(name);
    let staged = path.with_extension("tmp");
    if fs::write(&staged, value.to_string()).is_ok() {
        let _ = fs::rename(staged, path);
    }
}

fn read_state(name: &str) -> Option<Value> {
    serde_json::from_str(&fs::read_to_string(transfer_file(name)).ok()?).ok()
}

fn transfer_group() -> Option<Pid> {
    let raw = fs::read_to_string(transfer_file("runner.pid")).ok()?;
    let pid = Pid::from_raw(raw.trim().parse().ok()?)?;
    let alive = test_kill_process_group(pid).is_ok() && !group_exited(pid) && is_runner(pid);
    alive.then_some(pid)
}

fn is_runner(pid: Pid) -> bool {
    let Ok(raw) = fs::read(format!("/proc/{}/cmdline", pid.as_raw_nonzero())) else {
        return false;
    };
    let arguments: Vec<&[u8]> = raw.split(|byte| *byte == 0).collect();
    arguments
        .windows(2)
        .any(|pair| pair == [b"network-storage".as_slice(), b"run-queue".as_slice()])
}

fn start_lock() -> AppResult<fs::File> {
    fs::create_dir_all(state_dir())?;
    let lock = fs::File::create(transfer_file("lock"))?;
    lock.lock()
        .map_err(|error| AppError::command(format!("could not lock the sync state: {error}")))?;
    Ok(lock)
}

fn group_exited(pid: Pid) -> bool {
    process_state(pid).is_none_or(|state| state == 'Z' || state == 'X')
}

fn process_state(pid: Pid) -> Option<char> {
    let stat = fs::read_to_string(format!("/proc/{}/stat", pid.as_raw_nonzero())).ok()?;
    stat.rsplit_once(") ")?.1.chars().next()
}

fn clear_transfer() {
    for name in ["runner.pid", "queue", "target", "progress"] {
        let _ = fs::remove_file(transfer_file(name));
    }
}

fn group_stopped(pid: Pid) -> bool {
    process_state(pid).is_some_and(|state| state == 'T' || state == 't')
}

fn signal_transfer(signals: &[Signal], state: &str) -> AppResult<Value> {
    let pid = transfer_group().ok_or_else(|| AppError::invalid("nothing is syncing"))?;
    for signal in signals {
        kill_process_group(pid, *signal).map_err(|error| {
            AppError::command(format!("could not signal the transfer: {error}"))
        })?;
    }
    Ok(json!({"ok": true, "state": state}))
}

fn cancel() -> AppResult<Value> {
    let paths = read_state("queue").unwrap_or(Value::Null);
    let result = signal_transfer(&[Signal::CONT, Signal::TERM], "cancelled")?;
    clear_transfer();
    write_state(
        "result",
        &json!({"ok": false, "cancelled": true, "error": "cancelled", "paths": paths}),
    );
    Ok(result)
}

fn active() -> Value {
    let Some(pid) = transfer_group() else {
        return json!({"ok": true, "active": false, "last": read_state("result").unwrap_or(Value::Null)});
    };
    json!({
        "ok": true,
        "active": true,
        "path": fs::read_to_string(transfer_file("target")).unwrap_or_default(),
        "paths": read_state("queue").unwrap_or(Value::Null),
        "paused": group_stopped(pid),
        "progress": read_state("progress").unwrap_or(Value::Null),
    })
}

fn progress_fields(chunk: &str) -> Option<(u64, String, String, String)> {
    let tokens: Vec<&str> = chunk.split_whitespace().collect();
    let index = tokens.iter().rposition(|token| token.ends_with('%'))?;
    let percent = tokens[index].trim_end_matches('%').parse().ok()?;
    let bytes = index
        .checked_sub(1)
        .map(|at| tokens[at].to_string())
        .unwrap_or_default();
    let rate = tokens
        .get(index + 1)
        .filter(|token| token.ends_with("/s"))
        .map(|token| token.to_string())
        .unwrap_or_default();
    let eta = tokens
        .get(index + 2)
        .filter(|token| token.contains(':'))
        .map(|token| token.to_string())
        .unwrap_or_default();
    Some((percent, bytes, rate, eta))
}

fn transfer_one(rsync: &Path, source: &Path, copy: &Path, share: (u64, u64)) -> AppResult<()> {
    let (done, total) = share;
    no_symlink_below_root(copy, true)?;
    if let Some(parent) = copy.parent() {
        no_symlink_below_root(&parent.join(".rsync-partial"), true)?;
    }
    let parent = copy
        .parent()
        .ok_or_else(|| AppError::invalid("no destination folder"))?;
    fs::create_dir_all(parent)?;
    let mut arguments = vec![
        "-a".to_string(),
        "--partial".into(),
        "--partial-dir=.rsync-partial".into(),
        "--info=progress2".into(),
        "--outbuf=L".into(),
    ];
    let partials = parent.join(".rsync-partial");
    let partial = copy.file_name().map(|name| partials.join(name));
    let resumable = partial.as_ref().filter(|partial| {
        let have = fs::metadata(partial)
            .map(|metadata| metadata.len())
            .unwrap_or(0);
        let want = fs::metadata(source)
            .map(|metadata| metadata.len())
            .unwrap_or(0);
        !source.is_dir() && have > 0 && have < want
    });
    if source.is_dir() {
        arguments.push(format!("{}/", source.display()));
        arguments.push(format!("{}/", copy.display()));
    } else if resumable.is_some() {
        arguments = vec![
            "-a".to_string(),
            "--append".into(),
            "--info=progress2".into(),
            "--outbuf=L".into(),
            source.display().to_string(),
            format!("{}/", partials.display()),
        ];
    } else {
        arguments.push(source.display().to_string());
        arguments.push(format!("{}/", parent.display()));
    }
    let mut child = std::process::Command::new(rsync)
        .args(&arguments)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|error| AppError::command(format!("could not start rsync: {error}")))?;
    fs::write(transfer_file("target"), source.display().to_string())?;
    let mut stderr = child.stderr.take();
    let errors = thread::spawn(move || {
        let mut text = String::new();
        if let Some(stderr) = stderr.as_mut() {
            let _ = stderr.take(64 * 1024).read_to_string(&mut text);
        }
        text
    });
    if let Some(mut stdout) = child.stdout.take() {
        let mut buffer = [0u8; 4096];
        let mut pending = String::new();
        while let Ok(count) = stdout.read(&mut buffer) {
            if count == 0 {
                break;
            }
            pending.push_str(&String::from_utf8_lossy(&buffer[..count]));
            while let Some(at) = pending.find(['\r', '\n']) {
                let line: String = pending.drain(..=at).collect();
                if let Some((percent, bytes, rate, eta)) = progress_fields(&line) {
                    let overall = (done * 100 + percent.min(100)) / total;
                    write_state(
                        "progress",
                        &json!({"percent": overall, "bytes": bytes, "rate": rate, "eta": eta, "path": source}),
                    );
                }
            }
        }
    }
    let status = child.wait()?;
    let message = errors.join().unwrap_or_default();
    if !status.success() {
        let reason = message
            .lines()
            .rev()
            .find(|line| !line.trim().is_empty())
            .unwrap_or("")
            .trim()
            .to_string();
        return Err(AppError::command(if reason.is_empty() {
            format!("rsync failed on {}", source.display())
        } else {
            format!("rsync failed on {}: {reason}", source.display())
        }));
    }
    if let Some(partial) = resumable {
        fs::rename(partial, copy)?;
        let _ = fs::remove_dir(&partials);
    }
    Ok(())
}

fn run_queue() -> AppResult<Value> {
    let own = std::process::id();
    if let Some(pid) = transfer_group()
        && pid.as_raw_nonzero().get() as u32 != own
    {
        return Err(AppError::invalid("a sync is already running"));
    }
    if std::env::var_os("OMABLADE_SYNC_RUNNER").is_none() {
        return Err(AppError::invalid(
            "run-queue is started by sync; use `network-storage sync`",
        ));
    }
    let paths: Vec<PathBuf> = read_state("queue")
        .and_then(|queue| serde_json::from_value(queue).ok())
        .ok_or_else(|| AppError::invalid("no queued sync"))?;
    let outcome = (|| -> AppResult<()> {
        let rsync = which("rsync").ok_or_else(|| AppError::command("rsync is not installed"))?;
        fs::create_dir_all(sync_root())?;
        let table = MountTable::read()?;
        let total = paths.len().max(1) as u64;
        for (finished, path) in paths.iter().enumerate() {
            let copy = local_copy_in(&table, path)?;
            transfer_one(&rsync, path, &copy, (finished as u64, total))?;
            write_state(
                "progress",
                &json!({"percent": (finished as u64 + 1) * 100 / total, "bytes": "", "rate": "", "eta": "", "path": path}),
            );
        }
        Ok(())
    })();
    let result = match &outcome {
        Ok(()) => json!({"ok": true, "synced": paths}),
        Err(error) => json!({"ok": false, "error": error.to_string(), "paths": paths}),
    };
    write_state("result", &result);
    clear_transfer();
    Ok(result)
}

fn sync(
    paths: &[PathBuf],
    cancelled: &AtomicBool,
    progress: &mut dyn FnMut(Value) -> AppResult<()>,
) -> AppResult<Value> {
    which("rsync").ok_or_else(|| AppError::command("rsync is not installed"))?;
    let lock = start_lock()?;
    if transfer_group().is_some() {
        return Err(AppError::invalid("a sync is already running"));
    }
    clear_transfer();
    let _ = fs::remove_file(transfer_file("result"));
    write_state("queue", &json!(paths));
    let executable = std::env::current_exe()
        .map_err(|error| AppError::command(format!("could not locate omablade: {error}")))?;
    let pid = CommandSpec::new(executable)
        .args(["_backend", "network-storage", "run-queue"])
        .env("OMABLADE_SYNC_RUNNER", "1")
        .spawn_detached()?;
    fs::write(transfer_file("runner.pid"), pid.to_string())?;
    drop(lock);
    let mut last = String::new();
    loop {
        if let Ok(text) = fs::read_to_string(transfer_file("progress"))
            && text != last
            && let Ok(update) = serde_json::from_str::<Value>(&text)
        {
            last = text;
            let _ = progress(update);
        }
        if let Some(result) = read_state("result") {
            if result["ok"] == true {
                let _ = progress(
                    json!({"percent": 100, "bytes": "", "rate": "", "eta": "", "path": paths.last()}),
                );
                return Ok(result);
            }
            if result["cancelled"] == true {
                return Err(AppError::Cancelled);
            }
            return Err(AppError::command(
                result["error"]
                    .as_str()
                    .unwrap_or("sync failed")
                    .to_string(),
            ));
        }
        if transfer_group().is_none() {
            thread::sleep(Duration::from_millis(100));
            if read_state("result").is_none() {
                clear_transfer();
                return Err(AppError::command("the sync stopped unexpectedly"));
            }
            continue;
        }
        if cancelled.load(Ordering::Relaxed) {
            return Err(AppError::Cancelled);
        }
        thread::sleep(Duration::from_millis(250));
    }
}
