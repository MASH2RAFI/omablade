This file was written by an agent.

# Install as an Omarchy plugin

Set everything up with one line:

```sh
curl -fsSL https://raw.githubusercontent.com/MASH2RAFI/omablade/main/tools/plugin-setup | bash
```

`tools/plugin-setup` adds and enables the plugin (or updates a git install),
disables the FileBlade plugin if it is installed, links the `omablade` command
into `~/.local/bin`, and turns on Omablade's reversible Hyprland bindings role,
unless `~/.config/hypr/bindings.lua` already calls Omablade. Running it again
is safe.

The plugin also adds its keys by itself: the first time it starts it turns on
the same role, which writes `~/.config/hypr/omablade-bindings.lua` and one
`dofile` line in `bindings.lua`, links `~/.local/bin/omablade` if that command
is missing, and says so in the Files pane. Bindings that already mention
Omablade or FileBlade are left alone, and the choice is made once; turn the keys
on or off later in Settings → Desktop integration → Hyprland bindings (see
[keybindings](../../docs/agent-written/keybindings.md#hyprland-bindings)). Pass options after `bash -s --`: `--dry-run` shows what
would change, `--no-bindings` leaves `bindings.lua` untouched,
`--force-bindings` adds the defaults anyway, and `--keep-fileblade` leaves
FileBlade enabled. `tests/plugin_setup.rs` runs the script against stand-in
`omarchy` and `hyprctl` commands.

The same steps by hand: Omarchy clones the repository into
`~/.config/omarchy/plugins/mash2rafi.omablade/`, validates the manifest and
enables it, and the shell starts Omablade's service and bar widget.

```sh
omarchy plugin add https://github.com/MASH2RAFI/omablade.git --enable
ln -s ~/.config/omarchy/plugins/mash2rafi.omablade/omablade ~/.local/bin/omablade
omarchy plugin update mash2rafi.omablade
omarchy plugin remove mash2rafi.omablade
```

Omarchy never runs plugin code while installing, so the keys arrive when the
plugin first starts rather than during `omarchy plugin add`.

Demonstration: The plugin installs disabled-then-enabled, its blades open, and
`omarchy plugin list` shows it.

The plugin runs the bundled x86-64 backend `omablade-bin`. Disable the original
FileBlade plugin (`data-goblin.fileblade`) first; both claim the same keys.
