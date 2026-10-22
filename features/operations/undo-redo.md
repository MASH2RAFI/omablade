This file was written by an agent.

# Undo and redo file operations

Undo reverses an eligible completed operation; redo reapplies it. Inspect operation history when you need the recorded result.

```sh
omablade undo --wait
omablade redo --wait
```

Demonstration: A sample rename is undone and then reapplied without losing the file contents.
