This file was written by an agent.

# Search nested folders

Click **fzf** in the search field or press **Ctrl+F** to find entries below the current folder, including inside collapsed directories.

Deep search respects ignore rules. Hidden entries and directories marked as caches also stay excluded while **View hidden** is off. Cargo's `target/` is both ignored and marked as a cache in this checkout; the prepared [v0.2.0 release notes](../../release/release-notes.md) live under `features/release/`, outside build output.

```sh
omablade search-deep on
omablade search getting
```

Demonstration: A nested getting-started document appears with its location.
