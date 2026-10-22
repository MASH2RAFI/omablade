This file was written by an agent.

# Recover interrupted operations

Omablade checks recorded in-flight operations so interrupted staged items can be recovered without silently overwriting another file.

```sh
omablade native backend -- recover
```

Demonstration: The real recovery command restores a sample staged file and reports its path.

The interruption is represented by a documented fixture; the recording does not claim a process crashed.
