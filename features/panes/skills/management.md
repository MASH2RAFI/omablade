This file was written by an agent.

# Share and unshare skills

Enable agent management in preferences to manage which supported agents receive a skill. Unsharing an owned link leaves the original skill source intact.

```sh
omablade preferences --agent-management true
```

Demonstration: The backend removes and restores the sample skill's Codex link while retaining the Claude source.

This clip proves provider-level sharing changes; it does not disable the original source skill.
