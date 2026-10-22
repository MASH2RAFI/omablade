import QtQuick
import Quickshell

QtObject {
  id: setup

  required property var service
  property bool running: false
  readonly property bool pluginMode: !!service && !!service.bladeHost && service.bladeHost.nativeApp !== true
  readonly property bool due: pluginMode && service.backendReady && service.stateReady
    && service.bindingsSetup === "" && !running
  readonly property string bindingsPath: {
    var config = String(Quickshell.env("XDG_CONFIG_HOME") || "")
    return (config.charAt(0) === "/" ? config : service.home + "/.config") + "/hypr/bindings.lua"
  }
  readonly property string addedNotice: "Added Omablade keys to Hyprland: Super+B and Super+Shift+B open the blades"

  onDueChanged: if (due) Qt.callLater(setup.run)
  Component.onCompleted: if (due) Qt.callLater(setup.run)

  function run() {
    if (!due) return
    running = true
    service.backendRequest("read-text", ["--path", bindingsPath, "--limit", "1048576"], 0, function(response) {
      if (!response || response.ok !== true) {
        setup.finish(response && response.missing ? "skipped" : "failed",
          response && response.missing ? "" : "Could not read " + setup.bindingsPath + ": " + String(response && response.error || "no answer"))
        return
      }
      if (/omablade|fileblade/i.test(String(response.text || ""))) {
        setup.finish("kept", "")
        return
      }
      service.backendRequest("roles-set", ["--role", "bindings", "--on"], 0, function(answer) {
        var entry = answer && answer.roles ? answer.roles.bindings : null
        var status = entry ? String(entry.status || "") : ""
        if (status === "enabled" || status === "already_on") setup.finish("added", setup.addedNotice)
        else setup.finish("failed", "Could not add Omablade keys to Hyprland: "
          + String((entry && entry.error) || (answer && answer.error) || "no answer from the backend"))
      })
    })
  }

  function finish(state, message) {
    running = false
    service.setBindingsSetup(state)
    if (!message) return
    if (state === "failed") service.operationError = message
    else service.operationNotice = message
  }
}
