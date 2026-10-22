import QtQuick
import QtTest
import "../../blades" as Blades

TestCase {
  name: "BladeRegistryHostileDefinitions"

  Blades.BladeRegistry {
    id: registry
    socketId: "mash2rafi.omablade/blade"
    contractVersion: 3
  }

  function row(definition, dir, source) {
    return { definition: definition, source_dir: dir, source: source }
  }

  function test_user_definitions_cannot_escape_shadow_or_corrupt_the_registry() {
    registry.parseScanOutput({ modules: [
      row({ id: "files", name: "Files", entry: "Module.qml" }, "/plugin/modules/files", "builtin"),
      row({ id: "escape", name: "Escape", entry: "../../outside/Evil.qml" }, "/user/escape", "user"),
      row({ id: "absolute", name: "Absolute", entry: "/tmp/Evil.qml" }, "/user/absolute", "user"),
      row({ id: "control", name: "Control", entry: "Mod\u0000ule.qml" }, "/user/control", "user"),
      row({ id: "files", name: "Fake Files", entry: "Module.qml" }, "/user/idclash", "user"),
      row({ id: "../../x", name: "Bad id", entry: "Module.qml" }, "/user/badid", "user"),
      row({ id: 7, name: [], entry: {}, singleton: "yes" }, "/user/types", "user"),
      row({ id: "huge", name: "Huge", entry: "Module.qml", minHeight: 1e308, hostContract: -5 }, "/user/huge", "user"),
      row({ id: "future", name: "Future", entry: "Module.qml", hostContract: 99 }, "/user/future", "user"),
      row({ id: "objprovider", name: "Object provider", entry: "Module.qml", provider: { path: "x" } }, "/user/objprovider", "user"),
      row(null, "/user/null", "user"),
      row([], "/user/array", "user")
    ] })
    var ids = Object.keys(registry.fileModules).sort()
    compare(ids.join(","), "7,control,files,future,huge,objprovider")
    compare(registry.fileModules.objprovider.providerEntry, "")
    compare(registry.fileModules.objprovider.providerState, "invalid")
    compare(String(registry.fileModules.control.entryUrl), "file:///user/control/Module.qml")
    compare(registry.fileModules["7"].name, "7")
    compare(String(registry.fileModules["7"].entryUrl), "file:///user/types/Module.qml")
    compare(registry.fileModules.files.source, "builtin")
    compare(registry.fileModules.files.sourceDir, "/plugin/modules/files")
    compare(registry.fileModules.huge.minHeight, 4096)
    compare(registry.fileModules.huge.hostContract, 1)
    verify(registry.fileModules.huge.compatible)
    verify(!registry.fileModules.future.compatible)
    for (var id of ids) {
      var url = String(registry.fileModules[id].entryUrl)
      verify(url.indexOf("file://" + registry.fileModules[id].sourceDir + "/") === 0, url)
    }
  }
}
