import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../ui" as PluginUi
import "../theme"
import qs.Commons as Commons

Column {
  id: section

  required property var host
  property bool active: true
  property var roles: ({})
  property var results: ({})
  readonly property bool nativeApp: !!host && host.nativeApp === true
  readonly property var rows: [
    { role: "folder", glyph: "󰉋", label: "Open folders with Omablade", detail: "Makes Omablade the inode/directory handler in mimeapps.list" },
    { role: "reveal", glyph: "󰈞", label: "Reveal in Omablade", detail: "Serves org.freedesktop.FileManager1 for other applications' Reveal actions" },
    { role: "chooser", glyph: "󰈔", label: "File chooser", detail: "Routes the FileChooser portal to Omablade in portals.conf" },
    { role: "bindings", glyph: "󰌌", label: "Hyprland bindings", detail: "Adds omablade-bindings.lua to your Hyprland bindings" },
    { role: "autostart", glyph: "󰐥", label: "Start at login", detail: "Adds an autostart entry for Omablade" }
  ]
  readonly property var shownRows: nativeApp ? rows : rows.filter(function(row) { return row.role === "bindings" })
  readonly property int enabledCount: shownRows.filter(function(row) { return roleOn(row.role) }).length
  readonly property string keywords: (nativeApp ? "desktop integration folder reveal chooser bindings autostart login " : "desktop integration bindings keys shortcuts hyprland ")
    + shownRows.map(function(row) { return row.label }).join(" ")

  visible: !!host
  spacing: Style.space(5)

  onActiveChanged: if (active) refresh()
  Component.onCompleted: if (active) refresh()

  function refresh() {
    if (!host) return
    host.rolesStatus(function(response) {
      section.roles = response && response.roles ? response.roles : {}
      if (response && response.error) section.results = { "*": String(response.error) }
    })
  }

  function roleOn(role) {
    var entry = roles[role]
    return !!entry && entry.enabled === true
  }

  function toggle(role) {
    if (!host) return
    var on = !roleOn(role)
    host.setRole(role, on, function(response) {
      var next = {}
      next[role] = section.resultText(response, role)
      section.results = next
      section.refresh()
    })
  }

  function resultText(response, role) {
    if (!response) return "no answer from the backend"
    var entry = response.roles && response.roles[role] ? response.roles[role] : response
    if (entry.error) return String(entry.error)
    if (response.error) return String(response.error)
    if (entry.conflict) return String(entry.conflict)
    var texts = { restored: "restored the previous handler", preserved_newer: "kept your newer choice", already_off: "already off", already_on: "already on" }
    return texts[String(entry.status || "")] || ""
  }

  function rowText(role, detail) {
    if (results["*"]) return results["*"]
    if (results[role]) return results[role]
    var entry = roles[role]
    if (entry && entry.conflict) return String(entry.conflict)
    return detail
  }

  Repeater {
    model: section.shownRows

    delegate: Column {
      id: rowColumn
      required property var modelData
      width: parent.width
      spacing: Style.space(2)

      PluginUi.ToggleRow {
        objectName: "role-" + rowColumn.modelData.role
        width: parent.width
        glyph: rowColumn.modelData.glyph
        label: rowColumn.modelData.label
        checked: section.roleOn(rowColumn.modelData.role)
        onToggled: section.toggle(rowColumn.modelData.role)
      }

      Text {
        objectName: "detail-" + rowColumn.modelData.role
        textFormat: Text.PlainText
        width: parent.width
        text: section.rowText(rowColumn.modelData.role, rowColumn.modelData.detail)
        color: Commons.Color.muted
        wrapMode: Text.WordWrap
        font.family: Style.font.family
        font.pixelSize: Typography.caption
      }
    }
  }
}
