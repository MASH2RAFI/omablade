This file was written by an agent.

# Agent-written documentation

Technical documentation maintained by coding agents. The project `README.md`
is maintained separately.

## Documents

- [Feature documentation](../../features/index.md): observable workflows,
  logically grouped by workspace, pane, operation, integration and delivery,
  with screenshot and short video coverage tracked for each feature
- [Release notes](../../features/release/release-notes.md): changes in each Omablade version.
- [Feature evidence standard](../../features/evidence.md): capture geometry, SVG branding, visual review, and provenance
- [Extension-system design](design.md): native discovery, provider ownership,
  shared services and trust boundaries
- [Architecture](../../ARCHITECTURE.md): how the whole application is split up
  and how data moves through it
- [Keybindings](keybindings.md): user configuration for pane navigation and the Hyprland blade keys,
  folding, search and help
- [Git status](git-status.md): status markers and repository summary preferences
- [Agent usage history](agent-usage.md): how the Skills and MCP blades record
  skill and MCP use, the private store, helper methods, the `omablade usage`
  CLI and known limits
- [Skills usage counting](skills/usage-counting.md): what counts as a skill use,
  the 2026-09-17 audit, the refresh policy, the heatmap tooltip and day filter
- [MCP usage counting](mcp/usage-counting.md): what counts as an MCP call and how
  servers are matched
- [Hooks module](hooks/README.md): what the Hooks blade reads and changes; nothing is counted
- [Memory module](memory/README.md): what the Memory blade reads; nothing is counted
- [Extensions](../../EXTENSIONS.md): the public contract for blade modules and
  other Omablade extension points, including image galleries, file-menu actions
  and showing a module's own item in Properties
- [Network Storage example](../../examples/mash2rafi.omablade-networkstorage/README.md):
  an installable extension for network shares and offline sync, and why it owns processes
- [Security](../../SECURITY.md): trust boundaries, filesystem protections,
  command execution, previews, IPC, and known limits
- [Contributing](../../CONTRIBUTING.md): repository layout and development
  workflow
- [Third-party notices](../../THIRD_PARTY_NOTICES.html): generated dependency
  licenses and source links accompanying the bundled backend
- [UI expectations](../../tests/EXPECTATIONS.md): behavior checked in the
  headless desktop test
- [Agent guidelines](../../AGENTS.md): rules coding agents must follow in
  this repository

## Filename convention

Lowercase `design.md` means **technical product design**: behavior, ownership,
boundaries, decisions, and tradeoffs.

Uppercase `DESIGN.md` is reserved for a **visual design system** if Omablade
ever needs one: colors, typography, spacing, components, and writing style.
Omablade does not currently have that separate document.
