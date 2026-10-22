This file was written by an agent.

# Forget stored agent usage

Forget stored usage events before a chosen local date, or clear the usage history. This changes Omablade's usage database, not the original agent transcripts.

```sh
omablade usage forget --before 2026-09-22
```

Demonstration: Events before the chosen cutoff disappear while later sample events remain.

The recording uses disposable synthetic activity; forgetting real usage is a deliberate data-removal action.
