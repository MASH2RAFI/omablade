This file was written by an agent.

# Omablade {{PLUGIN_NAME}}

A native Omablade extension providing the `{{MODULE_ID}}` blade module.
{{DESCRIPTION}}

## Installation

Install and start Omablade, then register this trusted checkout:

```bash
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/omablade/extensions"
git clone {{REPOSITORY}} "${XDG_CONFIG_HOME:-$HOME/.config}/omablade/extensions/{{PLUGIN_ID}}"
omablade rescan-modules
```

The module declares `"defaultPlacement": "beside-files"`, so Omablade adds it
as a tab in the section that holds the Omablade tab the first time it is
discovered, and never again once you move or close it. Remove that key to make
people place it themselves from blade settings or with `omablade blade add`.
The module declares `hostContract: 2`. Omablade lists but refuses a module
whose contract is newer than its own. Review the extension before registration:
its QML executes with your desktop user's authority.

To remove it, close its tabs, remove its registration from the native extension
directory and run `omablade rescan-modules`. When the registration is a symlink,
remove that link to preserve the source checkout.

## Layout

```yaml
manifest.json:                         extension identity and the blade module definition
Provider.qml:                          shared provider runtime owned by Omablade
Service.qml:                           the provider again for Omarchy plugin installs, plus the host guard loader
HostGuard.qml, HostGuard.js:           the missing-host guard
blades/Module.qml:                     the blade module
assets/:                               omablade-extension-logo.svg (README banner), omablade-logo.png (host guard)
tests/run:                             local gate
tests/imports/qs/Commons/:             offline stub of the shell's Style, Color and Util singletons
docs/agent-guidelines.md:              rules for coding agents working in this extension
docs/agent-written/README.md:          this guide
ARCHITECTURE.md:                       ownership and state
```

## Settings

```yaml
caption:        string, up to 64 characters, shown under the selection; empty shows the key hint
showSelection:  boolean, show the selected path's name
```

Both rows render in the blade settings sheet from the manifest schema and are
read with `context.settings.get(key)`.

## Keys

```yaml
Enter:            open the selected path with its default application (folders navigate the Files blade)
e:                open the selected path in the editor
Tab, Shift+Tab:   next and previous slot
Esc:              close the blade
?:                Omablade's shortcut overlay, fed by the module's shortcuts property
```

## Developing

1. Link a trusted checkout under the native extension directory and run
   `omablade rescan-modules`.
2. Use `omablade modules` to confirm discovery; the module's `placed` field
   shows the tab Omablade added beside Files.
3. Work in an isolated desktop. After changing QML, drain the native runtime
   with `omablade native drain` and start `omablade` again.
4. Run `tests/run` and `omablade extension check .` before committing.
5. After a rename, regenerate the banner with `omablade extension image --png`.

## Going further

- Inventory-style blades load `context.ui.url("ArtifactTree")` and the shared
  `ArtifactInventory` runtime; see "Satellites and artifact bins" in
  Omablade's EXTENSIONS.md
- Script actions in the file menu are `mash2rafi.omablade/action` entries in
  the manifest and need no QML
- Bounded helpers (`mash2rafi.omablade/helper`) run a bundled executable
  through Omablade's resident backend with capped input, output and time
