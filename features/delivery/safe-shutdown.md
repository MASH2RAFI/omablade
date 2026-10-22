This file was written by an agent.

# Drain before maintenance

Drain the native runtime before maintenance. The result reports whether accepted work and state reached a safe stopping point.

```sh
omablade native drain --timeout-ms 5000 --json
```

Demonstration: The disposable runtime reports that it drained and stopped.

The capture helper reopens that disposable runtime after recording.
