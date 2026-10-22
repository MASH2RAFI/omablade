import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons

QtObject {
  id: look

  property var service: null
  property var hyprLook: ({})
  property int generation: 0

  readonly property bool hyprLookKnown: hyprLook.ok === true
  readonly property int borderSize: hyprLook.borderSize !== undefined ? Math.max(0, Math.round(Number(hyprLook.borderSize))) : 2
  readonly property real activeOpacity: lookOpacity(hyprLook.activeOpacity)
  readonly property real inactiveOpacity: lookOpacity(hyprLook.inactiveOpacity)
  readonly property var lookGaps: hyprLook.gapsOut || ({ top: 0, right: 0, bottom: 0, left: 0 })
  readonly property int gapsTop: Math.max(0, Math.round(Number(lookGaps.top) || 0))
  readonly property int gapsRight: Math.max(0, Math.round(Number(lookGaps.right) || 0))
  readonly property int gapsBottom: Math.max(0, Math.round(Number(lookGaps.bottom) || 0))
  readonly property int gapsLeft: Math.max(0, Math.round(Number(lookGaps.left) || 0))
  readonly property var activeBorderSpec: hyprLook.activeBorder
    ? borderSpec(hyprLook.activeBorder)
    : Commons.Border.withWidth(Commons.Border.hyprlandActiveSpec(Commons.Color.accent, borderSize), borderSize)
  readonly property var inactiveBorderSpec: hyprLook.inactiveBorder ? borderSpec(hyprLook.inactiveBorder) : Commons.Border.none()

  function lookOpacity(value) {
    var n = Number(value)
    return isFinite(n) && value !== undefined ? Math.max(0.05, Math.min(1, n)) : 1
  }

  function hyprColors(raw) {
    return String(raw || "").split(/\s+/).map(function(token) {
      var m = token.match(/^(?:0x)?([0-9A-Fa-f]{2})([0-9A-Fa-f]{6})$/)
      return m ? "#" + m[2] + m[1] : token
    }).join(" ")
  }

  function borderSpec(raw) {
    var resolved = Commons.Border.borderValue(hyprColors(raw), Commons.Color.accent, 1.0, "")
    return Commons.Border.withWidth({ color: resolved.color, gradient: resolved.gradient }, borderSize)
  }

  function refresh() {
    if (!service || !service.backendReady) return
    var current = ++generation
    service.backendRequest("hypr-look", [], current, function(response) {
      if (current !== look.generation || !response || response.ok !== true) return
      look.hyprLook = response
    })
  }

  function scheduleRefresh() { refreshTimer.restart() }

  property Timer refreshTimer: Timer { interval: 120; onTriggered: look.refresh() }

  property Connections backendEvents: Connections {
    target: look.service
    function onBackendReadyChanged() { if (look.service.backendReady) look.refresh() }
  }

  property Connections hyprlandEvents: Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && event.name === "configreloaded") look.scheduleRefresh()
    }
  }

  onServiceChanged: refresh()
}
