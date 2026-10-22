This file was written by an agent.

# Write your own module

Create a working panel in one command, edit its QML, and reload to see the
change. Your layout and open folder stay as they were.

```sh
omablade module new hello --add right
$EDITOR ~/.config/omarchy/omablade/modules/hello/Module.qml
omablade module reload
omablade extension check ~/.config/omarchy/omablade/modules/hello
```

Demonstration: A Hello panel appears on the right blade, then shows an edit
after `omablade module reload`.

To share a module, turn it into an extension with `omablade extension template
ID --install --add right`; see [Add an extension pane](extensions.md).
