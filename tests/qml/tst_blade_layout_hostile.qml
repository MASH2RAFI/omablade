import QtQuick
import QtTest
import "../../blades" as Blades

TestCase {
  name: "BladeLayoutHostileDocuments"

  QtObject {
    id: registry
    property var coreModules: ["skills", "memory", "hooks", "mcp"]
    function canonicalModule(name) { return name }
    function module(name) { return ["files", "notes", "properties"].indexOf(name) >= 0 ? { id: name, singleton: true } : null }
    function disabledModule() { return null }
  }

  QtObject {
    id: host
    property var config: ({})
    property var legacyDefaults: ({})
    property int minimumWidth: 240
    property int slotHandleSize: 6
    property var layout: ({})
    property var edges: ["left", "right"]
    property var registry: registry
    property var activeSlots: ({})
    property var windowAddresses: ({})
    property string monitorMode: "active"
    property bool animateBlades: true
    property real fontScale: 1
    property string barPlacement: "below"
    property var defaultPlacements: []
  }

  Blades.BladeLayout {
    id: layout
    host: host
  }

  function valid(result) {
    for (var edge of ["left", "right"]) {
      var blade = result[edge]
      verify(blade && typeof blade === "object", edge)
      verify(typeof blade.open === "boolean")
      verify(isFinite(blade.width) && blade.width >= 240 && blade.width <= 1600, String(blade.width))
      verify(blade.mode === "docked" || blade.mode === "window")
      verify(Array.isArray(blade.slots) && blade.slots.length <= 64)
      var ids = {}
      for (var slot of blade.slots) {
        verify(/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(slot.id), slot.id)
        verify(!ids[slot.id], "duplicate slot id " + slot.id)
        ids[slot.id] = true
        verify(slot.modules.length > 0 && slot.modules.length <= 32)
        verify(slot.active >= 0 && slot.active < slot.modules.length)
        verify(slot.fraction === -1 || (slot.fraction > 0 && slot.fraction < 1))
        for (var tab of slot.modules) {
          verify(typeof tab.module === "string" && tab.module.length > 0 && tab.module.length <= 128)
          verify(!/[\u0000-\u001f]/.test(tab.module))
          verify(tab.state && typeof tab.state === "object" && !Array.isArray(tab.state))
        }
      }
    }
  }

  function test_any_document_normalizes_to_a_usable_layout() {
    var many = []
    for (var i = 0; i < 500; i++) many.push({ id: "same", modules: [{ module: "files" }], active: 9, fraction: 7 })
    var deep = {}
    var cursor = deep
    for (var d = 0; d < 2000; d++) { cursor.next = {}; cursor = cursor.next }
    var documents = [
      null, undefined, 0, 7, "text", [], [1, 2], true,
      { version: "x", blades: 7 },
      { blades: { left: "files", right: [null, 3] } },
      { blades: { left: { open: "yes", width: "wide", mode: "fullscreen", slots: "files" } } },
      { blades: { left: { width: -1e308, slots: [null, {}, { modules: [] }, { modules: [null, 5, { module: "" }] }] } } },
      { blades: { left: { width: 1e308, slots: many } } },
      { blades: { right: { slots: [{ id: "../../x", modules: [{ module: "../../etc" }, { module: "a\u0000b" }, { module: "x".repeat(500) }], active: -3 }] } } },
      { blades: { left: { slots: [{ modules: [{ module: "notes", state: [1, 2] }, { module: "files", state: deep }] }] } } },
      { blades: { left: { slots: [{ modules: [{ module: "notes", state: { text: "x".repeat(200000) } }] }] } } },
      { left: { open: true, slots: ["files", "notes", "files"] } }
    ]
    for (var doc of documents) valid(layout.normalizeLayout(doc))
    var noted = layout.normalizeLayout({ blades: { left: { slots: [{ modules: [{ module: "notes", state: { text: "x".repeat(200000) } }] }] } } })
    compare(JSON.stringify(noted.left.slots[0].modules[0].state), "{}")
  }
}
