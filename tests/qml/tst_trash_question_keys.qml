import QtQuick
import QtTest
import "../../controllers"

TestCase {
  name: "TrashQuestionKeys"

  property var calls: []

  QtObject {
    id: fakeService
    property var preferences: ({ questionPending: true })
  }

  QtObject {
    id: fakeHost
    property bool layoutSettled: true
    property string focusedEdge: ""
    property bool leftOpen: true
    function normalizeEdge(edge) { return edge === "right" ? "right" : "left" }
    function isOpen(edge) { return edge === "left" ? leftOpen : true }
    function preferredScreen(edge) { return "screen-" + edge }
    function focusBlade(edge, screen, slot, part, openIfClosed) {
      calls.push("focus " + edge)
      focusedEdge = edge
      return true
    }
    function toggleBladeFocus(edge, screen) {
      calls.push("toggle " + edge)
      if (edge === "left") leftOpen = !leftOpen
      return "toggled"
    }
  }

  FileTreeIpc { id: ipc; service: fakeService; bladeHost: fakeHost; watchController: null }

  function init() {
    calls = []
    fakeService.preferences = { questionPending: true }
    fakeHost.focusedEdge = ""
    fakeHost.leftOpen = true
  }

  function test_super_b_brings_the_keyboard_to_the_pending_question() {
    compare(ipc.handler.toggleBladeFocus("left"), "focused")
    compare(calls.join(","), "focus left")
    verify(fakeHost.leftOpen)
    compare(ipc.handler.toggleBladeFocus("left"), "consent-pending", "a second press still cannot hide it")
    compare(calls.length, 1)
    verify(fakeHost.leftOpen)
  }

  function test_focus_left_behaves_like_super_b() {
    compare(ipc.handler.focusLeft(), "focused")
    compare(ipc.handler.focusLeft(), "consent-pending")
  }

  function test_from_the_right_blade_super_b_moves_to_the_question() {
    fakeHost.focusedEdge = "right"
    compare(ipc.handler.toggleBladeFocus("left"), "focused")
    compare(fakeHost.focusedEdge, "left")
  }

  function test_the_right_blade_and_answered_homes_toggle_as_usual() {
    compare(ipc.handler.toggleBladeFocus("right"), "toggled")
    fakeService.preferences = { questionPending: false }
    compare(ipc.handler.toggleBladeFocus("left"), "toggled")
    compare(calls.join(","), "toggle right,toggle left")
    verify(!fakeHost.leftOpen)
  }
}
