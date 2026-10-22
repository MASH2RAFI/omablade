import QtQuick
import QtTest
import "../../controllers"
import "../../panes"

TestCase {
  id: test
  name: "DrivesView"
  width: 420
  height: 600
  visible: true
  when: windowShown

  QtObject {
    id: fakeService
    property bool backendReady: false
    function backendRequest() { return "" }
    function backendSubscribeTopic() { return "" }
    function cancelBackendRequest() { return true }
    function navigateToLocation() {}
  }

  DrivesController {
    id: drives
    service: fakeService
  }

  QtObject {
    id: treeController
    property var drivesController: drives
    function focusTree() {}
    function goBack() {}
  }

  Item {
    id: pane
    property var hostWindow: null
    function targetScreen() { return null }
  }

  DrivesView {
    id: view
    width: 400
    height: 560
    controller: treeController
    pane: pane
  }

  function volume(name, tier, overrides) {
    var row = { name: name, device: name, source: "/dev/" + name, mountpoint: "/run/media/" + name, mounted: true,
      filesystem: "ext4", label: name, bus: "usb", size: 1000, size_label: "1 kB", used: 100, available: 900,
      removable: true, external: tier === "external", read_only: false, image: null, tier: tier, needs_authorization: false }
    for (var key in overrides || {}) row[key] = overrides[key]
    return row
  }

  function headings() {
    var out = []
    for (var i = 0; i < view.list.count; i++) {
      var entry = view.list.itemAtIndex(i)
      if (entry && entry.firstOfTier) out.push(i + ":" + drives.tierLabel(entry.tier))
    }
    return out
  }

  function test_each_tier_is_headed_once_above_its_first_drive() {
    failOnWarning(/.*/)
    drives.apply({ actions: true, volumes: [
      volume("usbA", "external"), volume("usbB", "external"),
      volume("root", "system", { mountpoint: "/" }), volume("data", "system", { mountpoint: "/data" })
    ] })
    tryVerify(function() { return view.list.count === 4 })
    wait(50)
    compare(headings().join("|"), "0:" + drives.tierLabel("external") + "|2:" + drives.tierLabel("system"))
    drives.apply({ actions: true, volumes: [] })
    tryVerify(function() { return view.list.count === 0 })
    compare(headings().length, 0)
    drives.apply({ actions: true, volumes: [volume("root", "system", { mountpoint: "/" })] })
    tryVerify(function() { return view.list.count === 1 })
    wait(100)
    compare(headings().join("|"), "0:" + drives.tierLabel("system"))
  }

  function test_the_list_view_uses_no_section_delegates() {
    compare(view.list.section.delegate, null)
  }
}
