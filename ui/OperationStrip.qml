import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../theme"

Item {
  id: strip

  required property var controller

  readonly property bool trashWork: !!controller && controller.trashOperationBusy && !controller.trashMode
  readonly property bool fileWork: !!controller && controller.operationBusy
  readonly property bool busy: fileWork || trashWork
  readonly property string failure: controller ? String(controller.operationError || "") : ""
  readonly property string doneText: !busy && controller ? String(controller.operationNotice || "") : ""
  readonly property var progressValue: fileWork ? controller.activeOperationProgress : (trashWork ? controller.trashProgress : null)
  readonly property int total: progressValue && Number(progressValue.total) > 0 ? Number(progressValue.total) : 0
  readonly property int completed: progressValue ? Math.max(0, Math.min(total, Number(progressValue.completed) || 0)) : 0
  readonly property int queued: fileWork ? Math.max(0, Number(controller.operationPendingCount) - 1) : 0
  readonly property bool cancellable: fileWork ? !!controller.operationCancellable : trashWork
  readonly property string message: {
    if (fileWork) return String(controller.operationNotice || ((controller.operationLabel || "Working") + "…"))
    if (trashWork) {
      const name = progressValue && progressValue.name ? " — " + String(progressValue.name) : ""
      const position = total > 0 ? " " + Math.min(total, completed + 1) + " of " + total : ""
      return String(controller.trashOperationLabel || "Trash") + position + name
    }
    return doneText
  }

  readonly property var spinnerFrames: ["◐", "◓", "◑", "◒"]
  property int spinnerFrame: 0

  implicitHeight: visible ? column.implicitHeight + Style.space(10) : 0
  height: implicitHeight
  visible: busy || doneText !== "" || failure !== ""

  Timer {
    interval: 150
    repeat: true
    running: strip.busy && strip.visible
    onTriggered: strip.spinnerFrame = (strip.spinnerFrame + 1) % strip.spinnerFrames.length
  }

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.bar.background
  }

  Rectangle {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 1
    color: Util.alpha(Commons.Color.muted, 0.25)
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(9)
    anchors.rightMargin: Style.space(9)
    spacing: Style.space(4)

    Row {
      width: parent.width
      spacing: Style.space(6)
      visible: strip.message !== ""

      Text {
        id: glyph
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: strip.busy ? strip.spinnerFrames[strip.spinnerFrame] : "✓"
        color: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Typography.caption
      }

      Text {
        objectName: "operationStripMessage"
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - glyph.width - (queuedText.visible ? queuedText.width + parent.spacing : 0)
          - (cancelText.visible ? cancelText.width + parent.spacing : 0) - parent.spacing
        elide: Text.ElideMiddle
        text: strip.message
        color: strip.busy ? Commons.Color.bar.text : Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Typography.caption
      }

      Text {
        id: queuedText
        objectName: "operationStripQueued"
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: strip.queued > 0
        text: "+" + strip.queued + " queued"
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Typography.caption
      }

      Text {
        id: cancelText
        objectName: "operationStripCancel"
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: strip.busy && strip.cancellable
        text: "Cancel"
        color: cancelArea.containsMouse ? Commons.Color.urgent : Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Typography.caption
        font.underline: cancelArea.containsMouse

        MouseArea {
          id: cancelArea
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: strip.cancel()
        }
      }
    }

    Rectangle {
      objectName: "operationStripBar"
      width: parent.width
      height: Style.space(3)
      visible: strip.busy
      color: Util.alpha(Commons.Color.muted, 0.25)

      Rectangle {
        height: parent.height
        width: strip.total > 0 ? parent.width * strip.completed / strip.total : parent.width * 0.3
        x: strip.total > 0 ? 0 : (parent.width - width) * (0.5 + 0.5 * Math.sin(strip.spinnerFrame * Math.PI / 2))
        color: Commons.Color.accent
        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(6)
      visible: strip.failure !== ""

      Text {
        objectName: "operationStripError"
        textFormat: Text.PlainText
        width: parent.width - dismissText.width - parent.spacing
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        text: strip.failure
        color: Commons.Color.urgent
        font.family: Style.font.family
        font.pixelSize: Typography.caption
      }

      Text {
        id: dismissText
        textFormat: Text.PlainText
        text: "✕"
        color: dismissArea.containsMouse ? Commons.Color.bar.text : Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Typography.caption

        MouseArea {
          id: dismissArea
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: strip.controller.operationError = ""
        }
      }
    }
  }

  function cancel() {
    if (fileWork) controller.cancelOperation(controller.activeOperationId)
    else if (trashWork) controller.cancelTrashOperation()
  }
}
