This file was written by an agent.

# Look like your Hyprland windows

A docked blade takes its corner rounding, border width, active and inactive
border colours (gradients included), active and inactive opacity and gaps from
Hyprland. Change any of them and reload Hyprland, or switch Omarchy theme; open
blades follow without a restart.

```sh
omablade status -o json | jq .hyprLook
hyprctl reload
```

Demonstration: The blade frame turns from grey to the active colour when the
blade takes focus, then follows a changed `col.active_border` after a reload.

A blade turned into a window is decorated by Hyprland itself.
