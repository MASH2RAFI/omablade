This file was written by an agent.

# Network Storage

A native Omablade extension that adds a **Network Storage** blade module. It
shows every connected network share as its own expandable tree and keeps an
offline copy of any folder or file you choose.

## What it does

- Lists shares mounted through gvfs (`gio mount`, the file manager's "Connect
  to server") and kernel network mounts such as cifs, nfs and sshfs.
- Connects a new share from a URI (`smb://server/share`, `sftp://…`, `nfs://…`)
  and remembers it for one-click reconnect. Disconnect and Forget are separate.
- Syncs a folder or file to `~/.sync/<share>/<path>` with rsync, with live
  progress, pause, resume and cancel. A cancelled sync resumes where it stopped.
- Un-syncs removes only the local copy, never anything on the share, and refuses
  any path outside `~/.sync`.
- Ctrl or Shift+click selects several rows to sync or un-sync together.

## Install

```bash
omablade extension install examples/mash2rafi.omablade-networkstorage --add right
```

This copies it into Omablade's extension folder, rescans, and places the
module on the right blade. After editing the installed copy, run
`omablade module reload`.

It needs `gio` (glib2), `rsync`, `findmnt` (util-linux) and `stdbuf`
(coreutils), all present on a standard Omarchy install.

## How it is built

`blades/Module.qml` is the view. `omablade-networkstorage` is a bash helper
that does the work: `shares`, `saved-shares`, `add-share`, `remove-share`,
`disconnect`, `list`, `status`, `check`, `sync`, `unsync`, `pause`, `resume`,
`cancel` and `active`. Transfer state lives in
`~/.local/state/omarchy/omablade/networkstorage`, so a restarted view
reattaches to a running sync.

The module runs the helper through its own Quickshell `Process` objects.
Omablade's built-in modules never do this; they go through the resident
backend. Omablade now ships a built-in Network Storage pane that does exactly
that (see [ARCHITECTURE.md](../../ARCHITECTURE.md#network-storage)); this copy
stays under `examples/` as a third-party extension that owns its processes,
which is why `tests/source_contract.rs` exempts `examples/` from the single
process-owner rule. Review it as you would any extension before enabling it;
see [EXTENSIONS.md](../../EXTENSIONS.md) and [SECURITY.md](../../SECURITY.md).
