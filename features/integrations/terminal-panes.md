This file was written by an agent.

# Target terminal panes

A supported terminal multiplexer can receive files in a chosen placement. Omablade resolves the live target pane before dispatching.

```sh
omablade drop-run mux-open /path/to/notes.txt --placement right --at 1200,220
```

Demonstration: A real tmux target gains a right-hand pane containing the sample file.

This recording covers tmux; it does not qualify every supported terminal or multiplexer.
