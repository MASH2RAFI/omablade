# Keybindings

This file was written by an agent.

Create `~/.config/omarchy/omablade/keybindings.json` (or
`$XDG_CONFIG_HOME/omarchy/omablade/keybindings.json`). It is user-owned:
Omablade preserves your bindings and adds schema `version` and `omabladeVersion`
metadata through the bounded backend. Unsupported versions are preserved and refused.
Changes reload automatically.

```json
{
  "version": 1,
  "bindings": {
    "open": ["l", "Right", "o"],
    "up": ["h", "Left", "Alt+Up"],
    "expand": ["z o"],
    "collapse": ["z c"],
    "expand-recursive": ["z O", "Shift+Right"],
    "collapse-recursive": ["z C", "Shift+Left"],
    "expand-all": ["z R"],
    "collapse-all": ["z M"],
    "page-previous": ["Ctrl+B", "Ctrl+U", "PageUp"]
  }
}
```

Only include actions you want to change. An array replaces all bindings for
that action; `[]` disables it. Omitted actions retain their defaults. To restore
defaults, remove the file or use `{"version":1,"bindings":{}}`.

## Versions

The file carries two version fields. `version` is the format, currently 1;
`omabladeVersion` is the Omablade that last wrote the file. The backend adds
both when they are missing and moves `omabladeVersion` forward when an older
Omablade wrote the file. It never moves it backward: a file written by a newer
Omablade is read but left byte-identical, and the `keybindings-prepare` answer
reports `writtenBy` and `newerWriter: true` so the shell can say so. A `version`
other than 1 is refused and preserved.

Within version 1 the reader is forward tolerant. An action this Omablade does
not know, a binding it cannot parse, or a value that is not an array is
dropped with a problem message and the rest of the file still applies, so a
file shared between two Omablade versions keeps working in both. The problems
appear in the keybindings error the Files tree reports. Two custom bindings
that conflict with each other are still refused as a whole, since that is a
mistake in the file rather than a version difference.

`settings.json` carries the same two fields. A read never rewrites it; a
settings change stamps `omabladeVersion` with the Omablade that made the
change, whichever version that is, because the stamp names the last writer.
`preferences-read` and `preferences-set` report `writtenBy` and `newerWriter`.

For example, `"expand": ["l", "Right"]` restores IDE-style expansion on
those keys; `o` still opens the selected folder. Custom bindings take priority
over defaults, including defaults whose sequences would conflict. Two custom
bindings that conflict are rejected rather than resolved by file order.

## Syntax

- Separate sequential presses with spaces: `"z o"`, `"g g"`.
- Use `+` for modifiers: `"Ctrl+B"`, `"Alt+Right"`, `"Ctrl+Shift+B"`.
- A bare uppercase letter means Shift: `"z O"` is z, then Shift+O.
  In modifier chords, letter case is conventional: `"Ctrl+B"` is not
  Ctrl+Shift+B.
- Named keys include arrows, `Home`, `End`, `PageUp`, `PageDown`, `Enter`,
  `Escape`, `Space`, `Tab`, `Backspace`, `Delete`, `Insert`, and `F1`–`F35`.
  Printable ASCII keys work directly; use `Plus` for the plus key.
- A binding has at most four presses; an action has at most eight bindings.
  Escape always cancels an unfinished sequence. Focus changes and config
  reloads also cancel it. Held keys do not repeat completed sequences.

## Actions and defaults

| Action | Default bindings |
| --- | --- |
| `next` / `previous` | `j`, Down / `k`, Up |
| `first` / `last` | `g`, Home / `G`, End |
| `page-next` | Ctrl+D, PageDown |
| `page-previous` | Ctrl+B, Ctrl+U, PageUp |
| `up` | `h`, Left, Alt+Up |
| `open` | `l`, Right, `o` |
| `activate` | Enter |
| `expand` / `collapse` | `z o` / `z c` |
| `expand-recursive` / `collapse-recursive` | `z O`, Shift+Right / `z C`, Shift+Left |
| `expand-all` / `collapse-all` | `z R` / `z M` |
| `quicknav` | Shift+Z |
| `picker` | Ctrl+P |
| `layout` | Ctrl+Shift+B |
| `deep` | Ctrl+F |
| `search` | `/` |
| `help` | `?` |

Navigation, activation, folding, search and help are shared by Files and the
satellite artifact trees. Inventory `up` selects the enclosing group/folder;
Files `up` changes the root to its parent. Properties inherits movement,
page-up/down, opening and help; `h`/Left returns to the tree. Fold commands
apply only in a tree. Quick navigation, the picker, search layout and deep
search are Files-only.

These are pane-navigation bindings, not global Hyprland shortcuts or editor
input mappings. Text fields, Notes editing, dialogs and module-specific
mutation commands retain their own keys. The Files shortcut guide displays
the effective bindings, including disabled actions.

## Errors and reloads

Malformed JSON, unknown actions/keys, ambiguous custom sequences, oversized
files (over 64 KiB), symlinks and non-regular files are rejected. The previous
valid configuration remains active; at startup that is the default map.
The Files status line and `omablade status` report the error.

To request a reread explicitly, use:

```sh
omablade native ipc -- mash2rafi.omablade.control reloadKeybindings
```

This rereads the keymap without restarting Omablade.

## Text zoom

`Ctrl+=`, `Ctrl++` and `Ctrl+KP_Add` raise the Font size one step (5%),
`Ctrl+-`, `Ctrl+_` and `Ctrl+KP_Subtract` lower it, `Ctrl+0` returns to 100%.
The blade surface handles them after every pane, so they work from any
focused control; they are not part of the user keymap file and cannot be
rebound. Plain `+` and `-` remain the tree density and media tile size keys.

## Hyprland bindings

The desktop keys that open and focus blades (`Super+B`, `Super+Shift+B`, the
blade-aware `Super+arrows`, `Super+W`, `Super+T` and the resize keys) come
from `examples/omablade-bindings.lua`. The `bindings` desktop role installs it:
it writes `~/.config/hypr/omablade-bindings.lua` with the launcher's absolute,
quoted path, adds one `dofile(...) -- omablade desktop role` line to
`~/.config/hypr/bindings.lua`, reloads Hyprland, and keeps a receipt so turning
it off restores both files byte for byte.

A plugin install turns the role on by itself the first time it starts, unless
`bindings.lua` is missing or already mentions Omablade or FileBlade (your own
bindings win). It records that decision in `state.json` as `bindingsSetup`
(`added`, `kept`, `skipped` or `failed`) and never asks again, so switching the
keys off in Settings → Desktop integration → Hyprland bindings stays off. For
a plugin the role links `~/.local/bin/omablade` to the plugin's launcher when
that command does not exist yet; an existing command is never replaced, and a
source checkout outside `~/.config/omarchy/plugins/` is never linked.
`tools/plugin-setup` uses the same role.

