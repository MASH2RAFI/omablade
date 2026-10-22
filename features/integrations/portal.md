This file was written by an agent.

# Choose files for applications

Enable the chooser role to register Omablade as a FileChooser portal backend. Applications request files through the desktop portal frontend.

```sh
omablade native roles enable --role chooser
```

Demonstration: A client requests a file through the public desktop portal, selects notes.txt in Omablade, and receives that exact file URI.

The real portal frontend and Omablade backend run on a disposable session bus. They are started explicitly for this recording; automatic service activation is covered separately by native-role checks.
