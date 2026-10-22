import QtQuick
import qs.Commons
import qs.Commons as Commons

FocusScope {
  id: module

  property var context: null

  readonly property string title: "{{NAME}}"
  readonly property var files: context ? context.service("files") : null
  readonly property string selectedPath: files && files.selectedPath ? String(files.selectedPath) : ""
  readonly property string selectedName: context && selectedPath !== "" ? String(context.paths.name(selectedPath)) : ""
  readonly property color paneBackground: Qt.lighter(Commons.Color.bar.background, 1.035)
  readonly property var shortcuts: [
    {
      title: "{{NAME}}",
      items: [
        { shortcut: "Enter", text: "Open the selected file" },
        { shortcut: "e", text: "Open the selected file in the editor" },
        { shortcut: "Tab / Shift+Tab", text: "Next / previous slot" },
        { shortcut: "Esc", text: "Close the blade" }
      ]
    }
  ]

  function takeFocus(part) {
    module.forceActiveFocus()
  }

  function openSelection(inEditor) {
    if (!files || selectedPath === "") return false
    if (inEditor) files.openInEditor(selectedPath)
    else files.openDefault(selectedPath, context.screen)
    return true
  }

  Keys.onPressed: function(event) {
    if (!context) return
    if (event.key === Qt.Key_Tab) context.focusNext()
    else if (event.key === Qt.Key_Backtab) context.focusPrevious()
    else if (event.key === Qt.Key_Escape) context.closeBlade()
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) openSelection(false)
    else if (event.key === Qt.Key_E && event.modifiers === Qt.NoModifier) openSelection(true)
    else return
    event.accepted = true
  }

  Rectangle {
    anchors.fill: parent
    color: module.paneBackground
  }

  MouseArea {
    anchors.fill: parent
    onClicked: module.forceActiveFocus()
  }

  Text {
    id: heading
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: Style.space(10)
    text: module.title.toUpperCase()
    color: module.activeFocus || handle.containsMouse ? Commons.Color.accent : Commons.Color.bar.text
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.weight: Font.DemiBold
    font.letterSpacing: 0.6
  }

  MouseArea {
    id: handle
    anchors.fill: heading
    anchors.margins: -Style.space(5)
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    onPressed: function(mouse) { if (module.context) module.context.handlePressed(handle, mouse.x, mouse.y) }
    onPositionChanged: function(mouse) { if (module.context && (mouse.buttons & Qt.LeftButton)) module.context.handleMoved(handle, mouse.x, mouse.y) }
    onReleased: function(mouse) { if (module.context) module.context.handleReleased(handle, mouse.x, mouse.y) }
    onCanceled: if (module.context) module.context.handleCanceled()
  }

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: heading.bottom
    anchors.margins: Style.space(10)
    spacing: Style.space(6)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      text: module.selectedName !== "" ? module.selectedName : "Nothing selected"
      color: module.selectedName !== "" ? Commons.Color.bar.text : Commons.Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "Select a file in Files. Enter opens it, e edits it. Edit {{FILE}}, then run omablade module reload to see your changes."
      color: Commons.Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
