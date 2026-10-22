This file was written by an agent.

<p align="center"><img src="assets/omablade-extension-logo.svg" alt="Omablade extension" width="640"></p>

---

**Omablade {{PLUGIN_NAME}}** adds a {{PLUGIN_NAME}} blade to [Omablade](https://github.com/mash2rafi/omablade), which gives you IDE-like sidebars for Omarchy.

{{DESCRIPTION}}

> [!NOTE]
> Replace this note with what the extension is for and what it supports. Add a
> screenshot of the blade to `assets/` and show it above this note, the way the
> other Omablade extensions do.

## Installation / Quick-start

Install and start the native Omablade app first, then register this trusted extension:

```bash
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/omablade/extensions"
git clone {{REPOSITORY}} "${XDG_CONFIG_HOME:-$HOME/.config}/omablade/extensions/{{PLUGIN_ID}}"
omablade rescan-modules
```

Omablade adds the blade as a tab beside the Omablade tab the first time it
discovers it. Move or close that tab like any other; Omablade remembers the
choice and does not put it back.

Customize this starter README to describe your extension. Full technical docs are in [docs/agent-written/README.md](docs/agent-written/README.md); design notes in [ARCHITECTURE.md](ARCHITECTURE.md).

Building your own extension is covered in Omablade's [EXTENSIONS.md](https://github.com/mash2rafi/omablade/blob/main/EXTENSIONS.md).

## License

MIT.
