This file was written by an agent.

# Change file permissions

Use the permissions action for an eligible local file. Integrations can invoke the same backend operation with an octal mode.

```sh
omablade native backend -- permissions-set --path /path/to/file.txt --mode 644
```

Demonstration: The sample file changes to mode 644, confirmed by filesystem metadata.

The clip proves the backend mutation, not interaction with the permissions form.
