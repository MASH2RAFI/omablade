This file was written by an agent.

# Omablade release notes

## 0.3.3 (unreleased)

The first Omablade version, a fork of FileBlade 0.3.2.

- Installs like any Omarchy plugin: `omarchy plugin add https://github.com/MASH2RAFI/omablade.git --enable`.
- Docked blades look like your Hyprland windows: rounding, border width and active and inactive colours (gradients too), opacity and gaps, and they follow every Hyprland reload or Omarchy theme switch without a restart. `omablade status` reports them under `hyprLook`.
- Writing modules is quicker: `omablade module new ID --add right` writes a working module, `omablade module reload` shows QML edits in place, `omablade extension install DIR --add left` installs an extension, and `omablade extension template ID --install` scaffolds straight into the extension folder.
- `omablade extension check` lists every problem at once and works on hand-written extensions and `blade.json` modules; a module whose manifest lacks `"provider"` says exactly how to fix it.
- Settings is split into folding sections: General, Layout, Module settings, Desktop integration, and About & reset.
- Right-clicking the empty space below the rows in Files opens the actions menu for the open folder, with New file and New folder.
- A Network Storage example extension lists mounted shares and keeps offline copies with rsync.
- The backend frees a request's slot before answering it, so a client that sends its next request at once is no longer refused.
- `tools/test-all` runs every check with one summary; `--live` adds an end-to-end CLI suite in a sealed nested Hyprland.
- Opening a deleted folder falls back to its parent, and a late finish or cancel no longer clears a newer selection.
- `omablade blade move-slot` works again, and `--tab` moves a single tab.
- `omablade blade set` moves a module from the other blade instead of silently emptying the blade it names; unknown or repeated modules are refused.
- A `--wait` that times out cancels its operation, so it never runs later; `copy-to`, `move-to` and `paste` take `--on-conflict ask|keep-both|replace|skip`.
- A timed-out `pick` closes its picker, a cut is used up by its paste, and `clear-clipboard` empties the clipboard Omablade wrote.
- `omablade log` and `omablade list` work in the native application; `popout` names the missing bar widget.
- Blade commands sent while Omablade is still loading its layout wait for it instead of being overwritten, and closing the left blade while the first-run Trash question is open says so instead of reporting it closed.
- Extracted and newly created archives are named as such in undo history; archive errors no longer show raw bsdtar output.
- Smaller fixes: `columns` and `git-details` reject unknown values, `screenshots` fails when no folder is known, removing an agent integration leaves its settings as they were, `hidden on|off`, icons for Create archive and Permissions, and files bat treats as binary preview as binary.
