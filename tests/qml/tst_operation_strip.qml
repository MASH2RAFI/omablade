import QtQuick
import QtTest
import "../../ui" as PluginUi

TestCase {
  id: test
  name: "OperationStrip"
  width: 400
  height: 200
  visible: true
  when: windowShown

  QtObject {
    id: controller
    property bool operationBusy: false
    property string operationLabel: ""
    property string operationNotice: ""
    property string operationError: ""
    property var activeOperationProgress: null
    property int operationPendingCount: 0
    property bool operationCancellable: false
    property string activeOperationId: ""
    property bool trashOperationBusy: false
    property string trashOperationLabel: ""
    property var trashProgress: null
    property bool trashMode: false
    property var cancelled: []
    function cancelOperation(id) { cancelled.push("file:" + id); return "cancelling" }
    function cancelTrashOperation() { cancelled.push("trash"); return true }
  }

  PluginUi.OperationStrip {
    id: strip
    width: 380
    controller: controller
  }

  function child(name) { return findChild(strip, name) }

  function init() {
    controller.operationBusy = false
    controller.operationLabel = ""
    controller.operationNotice = ""
    controller.operationError = ""
    controller.activeOperationProgress = null
    controller.operationPendingCount = 0
    controller.operationCancellable = false
    controller.trashOperationBusy = false
    controller.trashProgress = null
    controller.trashMode = false
    controller.cancelled = []
  }

  function test_idle_takes_no_space() {
    verify(!strip.visible)
    compare(strip.height, 0)
  }

  function test_a_copy_shows_what_is_happening_with_progress_queue_and_cancel() {
    controller.operationBusy = true
    controller.operationLabel = "Copy"
    controller.operationNotice = "Copying 3 of 10 — holiday.mov"
    controller.activeOperationProgress = { completed: 2, total: 10 }
    controller.operationPendingCount = 3
    controller.operationCancellable = true
    controller.activeOperationId = "op-7"
    verify(strip.visible)
    verify(strip.height > 0)
    compare(child("operationStripMessage").text, "Copying 3 of 10 — holiday.mov")
    compare(child("operationStripQueued").text, "+2 queued")
    verify(child("operationStripBar").visible)
    compare(strip.completed, 2)
    compare(strip.total, 10)
    verify(child("operationStripCancel").visible)
    waitForRendering(strip)
    mouseClick(child("operationStripCancel"))
    compare(controller.cancelled.join(","), "file:op-7")
  }

  function test_work_that_cannot_be_cancelled_offers_no_cancel() {
    controller.operationBusy = true
    controller.operationLabel = "Rename"
    verify(!child("operationStripCancel").visible)
    compare(child("operationStripMessage").text, "Rename…")
  }

  function test_completion_and_errors_stay_visible_until_cleared() {
    controller.operationNotice = "Move complete"
    verify(strip.visible)
    verify(!child("operationStripBar").visible)
    compare(child("operationStripMessage").text, "Move complete")
    controller.operationNotice = ""
    controller.operationError = "Permission denied: /srv/locked"
    verify(strip.visible)
    compare(child("operationStripError").text, "Permission denied: /srv/locked")
    waitForRendering(strip)
    mouseClick(findChild(strip, "operationStripError").parent.children[1])
    compare(controller.operationError, "")
    verify(!strip.visible)
  }

  function test_emptying_the_trash_is_shown_and_cancellable_outside_the_trash_view() {
    controller.trashOperationBusy = true
    controller.trashOperationLabel = "Empty Trash"
    controller.trashProgress = { completed: 4, total: 9, name: "old.log" }
    compare(child("operationStripMessage").text, "Empty Trash 5 of 9 — old.log")
    waitForRendering(strip)
    mouseClick(child("operationStripCancel"))
    compare(controller.cancelled.join(","), "trash")
    controller.trashMode = true
    verify(!strip.visible, "the Trash view shows its own progress")
  }
}
