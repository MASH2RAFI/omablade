This file was written by an agent.

# Add an extension pane

Install a trusted extension with one command: it is checked, copied into
`~/.config/omablade/extensions/ID/`, rescanned and placed. See EXTENSIONS.md for
the complete host contract.

```sh
omablade extension check ./demo-extension
omablade extension install ./demo-extension --add left
omablade extension install ./demo-extension --replace
```

Demonstration: The generated sample extension loads as a real Omablade pane.

Extensions execute local code and should come from a source you trust.
