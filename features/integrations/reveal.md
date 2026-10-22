This file was written by an agent.

# Reveal a file through the desktop

Enable the reveal role to serve desktop FileManager1 reveal requests. A request opens the containing folder and selects the requested file.

```sh
omablade native roles enable --role reveal
```

Demonstration: A real org.freedesktop.FileManager1.ShowItems call reveals and selects the requested document in Omablade.

The D-Bus service is started explicitly on the disposable session bus; automatic activation is covered separately by the native-role regressions.
