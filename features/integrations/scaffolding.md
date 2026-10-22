This file was written by an agent.

# Scaffold an extension

Generate an extension from the bundled template, then run the generated project's checks before customizing it. With `--install` it is written straight into Omablade's extension folder and placed on a blade.

```sh
omablade extension template demo.omablade-sample demo-extension
cd demo-extension
tests/run
omablade extension template demo.omablade-other --install --add right
```

Demonstration: The template generates a sample extension with its manifest and validation files.

The video shows generation; the full local code gate exercises the generated extension checks.
