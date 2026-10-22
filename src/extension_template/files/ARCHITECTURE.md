This file was written by an agent.

# {{PLUGIN_NAME}} architecture

The native Omablade app hosts this extension. Registration under
`~/.config/omablade/extensions/{{PLUGIN_ID}}` makes its manifest discoverable.
Omablade owns one `Provider.qml` runtime and loads `blades/Module.qml` for each
slot and screen that displays it. Installed as an Omarchy plugin instead, the
shell builds `Service.qml`, which is the same provider, and Omablade hands that
object to the module as `context.providerService`.

## Ownership

```yaml
Provider.qml:       shared scanners, caches, watchers and mutations; attachment starts work and shutdown releases it
blades/Module.qml:  presentation, plain-text rendering, shared focus commands and per-tab context.state
manifest.json:      module identity, entry, provider, hostContract and settings schema
HostGuard.qml, .js: host availability checks; no automatic download
Service.qml:        the provider again for Omarchy plugin installs, plus the host guard loader; keep it a Provider so modules read the same state in both shapes
tests/:             generated local gate and offline Commons fixtures
assets/:            generated extension wordmark and host icon
```

## Where state lives

- `context.state` is per tab and saved with the blade layout; keep it small
- `context.stateDir` and `context.configDir` are
  `~/.local/state/omarchy/omablade/modules/{{PLUGIN_ID}}+{{MODULE_ID}}/` and
  `~/.config/omarchy/omablade/config/{{PLUGIN_ID}}+{{MODULE_ID}}/`, created
  `0700` by the Omablade backend when the module loads
- settings declared in the manifest schema are ordinary `context.state` keys
  read through `context.settings.get(key)`; blade settings renders the form

## What the host does not do

Omablade validates the definition and namespaces the module id; it does not
sandbox the QML. Render filesystem values as plain text, bound every model, do
not start a `Process` of your own, and leave Omablade through the shared
primitives (`openDefault`, `openInEditor`, `revealInFileManager`) so focus
hand-off stays consistent. Omablade's SECURITY.md carries the review checklist.
