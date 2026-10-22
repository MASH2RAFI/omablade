This file was written by an agent.

# Register native autostart

Opt into the native autostart role to install the login desktop entry. Its stable launcher starts Omablade and restores the saved blade layout. Disable the role to reverse its owned registration.

```sh
omablade native roles enable --role autostart
omablade native roles status --json
```

Demonstration: After the runtime is drained, GIO launches the installed autostart desktop entry and the real native Files blade returns.

Proves registration and a cold desktop-entry launch. A full logout/login transition was not performed; the user's active desktop remains untouched.
