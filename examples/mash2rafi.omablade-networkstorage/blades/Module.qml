import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

FocusScope {
  id: module

  property var context: null
  readonly property var files: context ? context.service("files") : null
  readonly property real fontScale: context && context.host ? context.host.fontScale : 1.0
  readonly property string scriptPath: (context && context.moduleDir ? context.moduleDir : "") + "/omablade-networkstorage"

  readonly property string folderClosedGlyph: ""
  readonly property string folderOpenGlyph: ""
  readonly property string expanderClosedGlyph: ""
  readonly property string expanderOpenGlyph: ""
  readonly property string fileGlyph: "󰈔"

  readonly property int maxRowsPerFolder: 150

  property var rows: []

  property var childCache: ({})

  property string confirmingPath: ""

  property var selectedPaths: ({})
  readonly property int selectedCount: Object.keys(module.selectedPaths).length
  property bool confirmingBulkUnsync: false
  property bool confirmingBulkSync: false

  function selectionHasRoot() {
    for (var i = 0; i < module.rows.length; i++) {
      if (module.rows[i].depth === 0 && module.selectedPaths[module.rows[i].path]) return true
    }
    return false
  }

  function deselectPaths(paths) {
    if (paths.length === 0) return
    var next = Object.assign({}, module.selectedPaths)
    var changed = false
    for (var i = 0; i < paths.length; i++) {
      if (next[paths[i]]) { delete next[paths[i]]; changed = true }
    }
    if (changed) module.selectedPaths = next
  }

  function toggleSelected(path) {
    var next = Object.assign({}, module.selectedPaths)
    if (next[path]) delete next[path]
    else next[path] = true
    module.selectedPaths = next
    module.confirmingBulkUnsync = false
    module.confirmingBulkSync = false
  }

  function syncSelected() {
    if (module.selectionHasRoot() && !module.confirmingBulkSync) {
      module.confirmingBulkSync = true
      confirmResetTimer.restart()
      return
    }
    module.confirmingBulkSync = false
    module.runBatch(Object.keys(module.selectedPaths), "sync")
  }

  function unsyncSelected() {
    if (!module.confirmingBulkUnsync) {
      module.confirmingBulkUnsync = true
      confirmResetTimer.restart()
      return
    }
    module.confirmingBulkUnsync = false
    module.runBatch(Object.keys(module.selectedPaths), "unsync")
  }

  Timer {
    id: confirmResetTimer
    interval: 4000
    onTriggered: { module.confirmingPath = ""; module.confirmingBulkUnsync = false; module.confirmingBulkSync = false }
  }

  property string status: "Idle"
  property bool busy: false
  property bool paused: false
  property int percent: 0
  property string transferBytes: ""
  property string transferRate: ""
  property string transferEta: ""
  property string currentFileName: ""
  property var activeSyncPaths: []

  property bool reattached: false

  readonly property var spinnerFrames: ["◐", "◓", "◑", "◒"]
  property int spinnerFrame: 0
  readonly property bool anyVerifying: module.rows.some(function(r) { return r.verifying })
  Timer {
    interval: 150
    repeat: true
    running: (module.busy && !module.paused) || module.anyVerifying
    onTriggered: module.spinnerFrame = (module.spinnerFrame + 1) % module.spinnerFrames.length
  }

  Component.onCompleted: {
    module.refreshShares()
    module.refreshSavedShares()
    module.checkActive()
  }

  function checkActive() {
    activeProc.command = [module.scriptPath, "active"]
    activeProc.running = true
  }

  Process {
    id: activeProc
    stdout: StdioCollector {
      id: activeOut
      waitForEnd: true
      onStreamFinished: {
        var text = String(activeOut.text || "").trim()
        if (text.indexOf("ACTIVE") === 0) {
          var parts = text.split("\t")
          var path = parts[1]
          var state = parts[2]
          module.busy = true
          module.paused = state === "paused"
          module.reattached = true
          module.activeSyncPaths = (path && path !== "?") ? [path] : []
          module.currentFileName = (path && path !== "?") ? module.baseName(path) : ""
          module.status = (module.paused ? "Paused" : "Syncing") + " (reattached after reload)…"
          if (parts.length >= 7) {
            var pct = parseInt(parts[3], 10)
            if (isFinite(pct)) module.percent = Math.max(0, Math.min(100, pct))
            module.transferBytes = (parts[4] && parts[4] !== "-") ? parts[4] : ""
            module.transferRate = (parts[5] && parts[5] !== "-") ? parts[5] : ""
            module.transferEta = (parts[6] && parts[6] !== "-") ? parts[6] : ""
          }
          reattachPoll.running = true
        } else if (module.reattached) {
          module.busy = false
          module.paused = false
          module.reattached = false
          module.activeSyncPaths = []
          module.currentFileName = ""
          module.transferBytes = ""
          module.transferRate = ""
          module.transferEta = ""
          module.status = "Idle"
          reattachPoll.running = false
          module.refreshRowStatus()
        }
      }
    }
  }

  Timer {
    id: reattachPoll
    interval: 3000
    repeat: true
    onTriggered: module.checkActive()
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: module.refreshShares()
  }

  function indexOfPath(path) {
    for (var i = 0; i < module.rows.length; i++) if (module.rows[i].path === path) return i
    return -1
  }

  function refreshShares() {
    sharesProc.command = [module.scriptPath, "shares"]
    sharesProc.running = true
  }

  property string newShareUri: ""
  property string shareActionStatus: ""
  property bool shareActionBusy: false
  property var savedShares: []

  function refreshSavedShares() {
    savedSharesProc.command = [module.scriptPath, "saved-shares"]
    savedSharesProc.running = true
  }

  Process {
    id: savedSharesProc
    property var _found: []
    stdout: SplitParser { onRead: function(line) { if (line) savedSharesProc._found.push(line) } }
    onRunningChanged: if (running) _found = []
    onExited: function(exitCode) {
      module.savedShares = savedSharesProc._found
      savedSharesProc._found = []
    }
  }

  function addShare(uri) {
    var trimmed = String(uri || "").trim()
    if (!trimmed || module.shareActionBusy) return
    module.shareActionBusy = true
    module.shareActionStatus = "Connecting…"
    shareActionProc._verb = "add"
    shareActionProc._arg = trimmed
    shareActionProc.command = [module.scriptPath, "add-share", trimmed]
    shareActionProc.running = true
  }

  function removeShare(uri) {
    if (module.shareActionBusy) return
    module.shareActionBusy = true
    module.shareActionStatus = "Forgetting…"
    shareActionProc._verb = "remove"
    shareActionProc._arg = uri
    shareActionProc.command = [module.scriptPath, "remove-share", uri]
    shareActionProc.running = true
  }

  function disconnectShare(path) {
    if (module.shareActionBusy) return
    module.shareActionBusy = true
    module.shareActionStatus = "Disconnecting…"
    shareActionProc._verb = "disconnect"
    shareActionProc._arg = path
    shareActionProc.command = [module.scriptPath, "disconnect", path]
    shareActionProc.running = true
  }

  Process {
    id: shareActionProc
    property string _verb: ""
    property string _arg: ""
    stdout: StdioCollector {
      id: shareActionOut
      waitForEnd: true
      onStreamFinished: {
        var text = String(shareActionOut.text || "").trim()
        module.shareActionBusy = false
        if (text.indexOf("ERROR") === 0) {
          module.shareActionStatus = text.replace(/^ERROR\s*/, "Failed: ")
        } else {
          module.shareActionStatus = ""
          if (shareActionProc._verb === "add") module.newShareUri = ""
        }
        module.refreshSavedShares()
        module.refreshShares()
      }
    }
  }

  Process {
    id: sharesProc
    property var _found: []
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).split("\t")
        if (parts.length < 2) return
        sharesProc._found.push({ path: parts[0], name: parts[1] })
      }
    }
    onRunningChanged: if (running) _found = []
    onExited: function(exitCode) {
      var found = sharesProc._found
      sharesProc._found = []
      var keep = {}
      for (var i = 0; i < found.length; i++) keep[found[i].path] = true

      var next = module.rows.filter(function(r) {
        if (r.depth !== 0) return true
        return !!keep[r.path]
      })
      var existingRoots = {}
      for (var j = 0; j < module.rows.length; j++) if (module.rows[j].depth === 0) existingRoots[module.rows[j].path] = true
      if (Object.keys(existingRoots).some(function(p) { return !keep[p] })) {
        next = module.pruneOrphans(next)
      }

      var have = {}
      for (var k = 0; k < next.length; k++) if (next[k].depth === 0) have[next[k].path] = true
      for (var m = 0; m < found.length; m++) {
        if (!have[found[m].path]) {
          next.push({ path: found[m].path, name: found[m].name, kind: "d", depth: 0, expanded: false, synced: false, loading: false, verifiedState: "", verifying: false })
        }
      }

      var stillThere = {}
      for (var n = 0; n < next.length; n++) stillThere[next[n].path] = true
      var dropped = module.rows.filter(function(r) { return !stillThere[r.path] }).map(function(r) { return r.path })

      module.rows = next
      module.deselectPaths(dropped)
      module.refreshRowStatus()
    }
  }

  function refreshRowStatus() {
    for (var i = 0; i < module.rows.length; i++) {
      if (module.rows[i].depth === 0) module.checkStatus(module.rows[i].path)
    }
  }

  function pruneOrphans(list) {
    var out = []
    var stack = []
    for (var i = 0; i < list.length; i++) {
      var r = list[i]
      stack.length = r.depth
      var parentAlive = r.depth === 0 || stack[r.depth - 1] !== false
      stack[r.depth] = parentAlive
      if (parentAlive) out.push(r)
    }
    return out
  }

  function rowsFromChildren(parentPath, parentDepth, children) {
    var capped = children.length > module.maxRowsPerFolder
    var shown = capped ? children.slice(0, module.maxRowsPerFolder) : children
    var out = shown.map(function(f) {
      return { path: parentPath + "/" + f.name, name: f.name, kind: f.kind, depth: parentDepth + 1, expanded: false, synced: f.synced, loading: false, verifiedState: "", verifying: false }
    })
    if (capped) {
      out.push({
        path: parentPath + "/…more",
        name: "+ " + (children.length - module.maxRowsPerFolder) + " more item(s) not shown",
        kind: "info", depth: parentDepth + 1, expanded: false, synced: false, loading: false, verifiedState: "", verifying: false
      })
    }
    return out
  }

  function toggleExpand(path) {
    var idx = module.indexOfPath(path)
    if (idx === -1) return
    var row = module.rows[idx]
    if (row.kind !== "d") return
    if (row.loading) return
    if (row.expanded) {
      var depth = row.depth
      var end = idx + 1
      while (end < module.rows.length && module.rows[end].depth > depth) end++
      var removed = module.rows.slice(idx + 1, end).map(function(r) { return r.path })
      var next = module.rows.slice()
      next.splice(idx + 1, end - (idx + 1))
      next[idx] = Object.assign({}, row, { expanded: false })
      module.rows = next
      module.deselectPaths(removed)
      return
    }

    var cached = module.childCache[path]
    if (cached) {
      var cnext = module.rows.slice()
      cnext[idx] = Object.assign({}, row, { expanded: true })
      cnext.splice.apply(cnext, [idx + 1, 0].concat(module.rowsFromChildren(path, row.depth, cached)))
      module.rows = cnext
      return
    }

    var loadingRows = module.rows.slice()
    loadingRows[idx] = Object.assign({}, row, { loading: true })
    module.rows = loadingRows
    module._expandQueue.push(path)
    module._pumpExpandQueue()
  }

  property var _expandQueue: []
  property bool _expandBusy: false

  function _pumpExpandQueue() {
    if (module._expandBusy || module._expandQueue.length === 0) return
    module._expandBusy = true
    var path = module._expandQueue.shift()
    expandProc._targetPath = path
    expandProc._found = []
    expandProc.command = [module.scriptPath, "list", path]
    expandProc.running = true
  }

  Process {
    id: expandProc
    property string _targetPath: ""
    property var _found: []
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).split("\t")
        if (parts.length < 3) return
        expandProc._found.push({ kind: parts[0], synced: parts[1] === "SYNCED", name: parts[2] })
      }
    }
    onExited: function(exitCode) {
      var path = expandProc._targetPath
      var found = expandProc._found
      expandProc._found = []
      module._expandBusy = false

      var cache = Object.assign({}, module.childCache)
      cache[path] = found
      module.childCache = cache

      var idx = module.indexOfPath(path)
      if (idx !== -1) {
        var row = module.rows[idx]
        var next = module.rows.slice()
        next[idx] = Object.assign({}, row, { expanded: true, loading: false })
        next.splice.apply(next, [idx + 1, 0].concat(module.rowsFromChildren(path, row.depth, found)))
        module.rows = next
      }
      module._pumpExpandQueue()
    }
  }

  function patchCache(path, synced) {
    var slash = path.lastIndexOf("/")
    if (slash < 0) return
    var parent = path.slice(0, slash)
    var name = path.slice(slash + 1)
    var entry = module.childCache[parent]
    if (!entry) return
    var patched = entry.map(function(f) { return f.name === name ? Object.assign({}, f, { synced: synced }) : f })
    var cache = Object.assign({}, module.childCache)
    cache[parent] = patched
    module.childCache = cache
  }

  function checkStatus(path) {
    statusQueue.push(path)
    _pumpStatusQueue()
  }

  function verifyPath(path) {
    var idx = module.indexOfPath(path)
    if (idx === -1) return
    var next = module.rows.slice()
    next[idx] = Object.assign({}, next[idx], { verifying: true })
    module.rows = next
    verifyQueue.push(path)
    _pumpVerifyQueue()
  }
  property var verifyQueue: []
  property bool _verifyBusy: false

  function _pumpVerifyQueue() {
    if (module._verifyBusy || module.verifyQueue.length === 0) return
    module._verifyBusy = true
    var path = module.verifyQueue.shift()
    verifyProc._targetPath = path
    verifyProc.command = [module.scriptPath, "check", path]
    verifyProc.running = true
  }

  Process {
    id: verifyProc
    property string _targetPath: ""
    stdout: StdioCollector {
      id: verifyOut
      waitForEnd: true
      onStreamFinished: {
        var path = verifyProc._targetPath
        var state = String(verifyOut.text || "").trim()
        var idx = module.indexOfPath(path)
        if (idx !== -1) {
          var next = module.rows.slice()
          next[idx] = Object.assign({}, next[idx], {
            verifying: false,
            verifiedState: state === "PARTIAL" ? "partial" : (state === "SYNCED" ? "synced" : "")
          })
          module.rows = next
        }
        module._verifyBusy = false
        module._pumpVerifyQueue()
      }
    }
  }
  property var statusQueue: []
  property bool _statusBusy: false

  function _pumpStatusQueue() {
    if (module._statusBusy || module.statusQueue.length === 0) return
    module._statusBusy = true
    var path = module.statusQueue.shift()
    statusProc._targetPath = path
    statusProc.command = [module.scriptPath, "status", path]
    statusProc.running = true
  }

  Process {
    id: statusProc
    property string _targetPath: ""
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
      onStreamFinished: {
        var path = statusProc._targetPath
        var synced = String(statusOut.text || "").trim() === "SYNCED"
        var idx = module.indexOfPath(path)
        if (idx !== -1) {
          var next = module.rows.slice()
          next[idx] = Object.assign({}, next[idx], { synced: synced, verifiedState: "" })
          module.rows = next
        }
        module.patchCache(path, synced)
        module._statusBusy = false
        module._pumpStatusQueue()
      }
    }
  }

  function requestToggle(row) {
    var effectivelySynced = row.synced && row.verifiedState !== "partial"
    if (row.depth !== 0) {
      module.togglePath(row.path, effectivelySynced)
      return
    }
    if (module.confirmingPath === row.path) {
      confirmResetTimer.stop()
      module.confirmingPath = ""
      module.togglePath(row.path, effectivelySynced)
      return
    }
    module.confirmingPath = row.path
    confirmResetTimer.restart()
  }

  function togglePath(path, synced) {
    module.runBatch([path], synced ? "unsync" : "sync")
  }

  function runBatch(paths, verb) {
    if (module.busy || paths.length === 0) return
    module.busy = true
    module.paused = false
    module.percent = 0
    module.transferBytes = ""
    module.transferRate = ""
    module.transferEta = ""
    module.activeSyncPaths = paths
    module.currentFileName = paths.length === 1 ? module.baseName(paths[0]) : ""
    module.status = (verb === "unsync" ? "Removing " : "Syncing ") + (paths.length > 1 ? paths.length + " items…" : "…")
    syncProc.command = [module.scriptPath, verb].concat(paths)
    syncProc._targetPaths = paths
    syncProc.running = true
  }

  function button(cmd) {
    ctrlProc.command = cmd
    ctrlProc.running = true
  }

  function pause() {
    if (!module.busy || module.paused) return
    module.paused = true
    module.status = "Paused at " + module.percent + "%"
    module.button([module.scriptPath, "pause"])
  }

  function resume() {
    if (!module.busy || !module.paused) return
    module.paused = false
    module.status = "Syncing…"
    module.button([module.scriptPath, "resume"])
  }

  function cancel() {
    if (!module.busy) return
    module.button([module.scriptPath, "cancel"])
    module.busy = false
    module.paused = false
    module.activeSyncPaths = []
    module.currentFileName = ""
    module.reattached = false
    reattachPoll.running = false
    module.status = "Cancelled"
  }

  function baseName(path) {
    if (!path) return ""
    var parts = String(path).replace(/\/+$/, "").split("/")
    return parts[parts.length - 1] || path
  }

  function handleLine(line) {
    var text = String(line).trim()
    if (text.indexOf("PROGRESS") === 0) {
      var parts = text.split("\t")
      var value = parseInt(parts[1], 10)
      if (isFinite(value)) module.percent = Math.max(0, Math.min(100, value))
      module.transferBytes = (parts[2] && parts[2] !== "-") ? parts[2] : ""
      module.transferRate = (parts[3] && parts[3] !== "-") ? parts[3] : ""
      module.transferEta = (parts[4] && parts[4] !== "-") ? parts[4] : ""
      if (parts[5]) module.currentFileName = module.baseName(parts[5])
    } else if (text === "DONE") {
      module.percent = 100
      module.status = "Done"
      module.transferBytes = ""
      module.transferRate = ""
      module.transferEta = ""
      module.currentFileName = ""
    } else if (text.indexOf("UNSYNCED") === 0) {
      module.status = "Removed local copy"
    } else if (text.indexOf("NOT-SYNCED") === 0) {
      module.status = "Nothing to remove"
    } else if (text.indexOf("ERROR") === 0) {
      module.status = text.replace(/^ERROR\s*/, "Failed: ")
    }
  }

  Process {
    id: syncProc
    property var _targetPaths: []
    stdout: SplitParser { onRead: function(line) { module.handleLine(line) } }
    stderr: StdioCollector { id: syncErr; waitForEnd: true }
    onExited: function(exitCode) {
      module.busy = false
      module.paused = false
      module.activeSyncPaths = []
      for (var i = 0; i < syncProc._targetPaths.length; i++) module.checkStatus(syncProc._targetPaths[i])
      module.selectedPaths = ({})
      if (exitCode !== 0 && module.status.indexOf("Cancelled") !== 0 && module.status.indexOf("Failed") !== 0) {
        var err = String(syncErr.text || "").trim()
        module.status = "Failed" + (err ? ": " + err : " (exit " + exitCode + ")")
      }
    }
  }

  Process {
    id: ctrlProc
    stdout: StdioCollector {
      id: ctrlOut
      waitForEnd: true
      onStreamFinished: {
        var text = String(ctrlOut.text || "").trim()
        if (text.indexOf("ERROR") === 0) module.status = text.replace(/^ERROR\s*/, "Failed: ")
      }
    }
  }

  function openFile(path) {
    if (module.files && typeof module.files.openDefault === "function")
      module.files.openDefault(path, undefined, false)
  }

  Rectangle { anchors.fill: parent; color: Commons.Color.background }

  Column {
    id: topBar
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(12)
    spacing: Style.space(10)

    Text {
      textFormat: Text.PlainText
      text: "Network Storage"
      color: Commons.Color.bar.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body * module.fontScale
      font.weight: Font.DemiBold
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Rectangle {
        width: parent.width - connectBtn.width - Style.space(6)
        height: Style.space(24)
        color: Util.alpha(Commons.Color.muted, 0.12)
        border.width: shareInput.activeFocus ? 1 : 0
        border.color: Commons.Color.accent

        TextInput {
          id: shareInput
          anchors.fill: parent
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          text: module.newShareUri
          onTextChanged: module.newShareUri = text
          color: Commons.Color.bar.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall * module.fontScale
          Keys.onReturnPressed: module.addShare(module.newShareUri)
          Keys.onEnterPressed: module.addShare(module.newShareUri)

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            visible: !shareInput.text && !shareInput.activeFocus
            text: "smb://server/share, sftp://…, nfs://…"
            color: Commons.Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall * module.fontScale
          }
        }
      }

      SyncButton {
        id: connectBtn
        label: "Connect"
        enabled: !module.shareActionBusy && module.newShareUri.trim() !== ""
        onActivated: module.addShare(module.newShareUri)
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: module.shareActionStatus !== ""
      text: module.shareActionStatus
      color: Commons.Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption * module.fontScale
    }

    Column {
      width: parent.width
      spacing: Style.space(2)
      visible: module.savedShares.length > 0

      Text {
        textFormat: Text.PlainText
        text: "Saved servers"
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption * module.fontScale
      }

      Repeater {
        model: module.savedShares

        delegate: Row {
          required property string modelData
          width: parent ? parent.width : 0
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            width: parent.width - connectSavedBtn.width - forgetBtn.width - Style.space(12)
            height: Style.space(22)
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
            text: parent.modelData
            color: Commons.Color.bar.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall * module.fontScale
          }
          SyncButton {
            id: connectSavedBtn
            label: "Connect"
            enabled: !module.shareActionBusy
            onActivated: module.addShare(parent.modelData)
          }
          SyncButton {
            id: forgetBtn
            label: "Forget"
            enabled: !module.shareActionBusy
            onActivated: module.removeShare(parent.modelData)
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: module.rows.length > 0
      text: "Ctrl/Shift+click a row to select multiple"
      color: Commons.Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption * module.fontScale
    }

    Text {
      textFormat: Text.PlainText
      visible: module.rows.length === 0
      text: "No network storage connected"
      color: Commons.Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall * module.fontScale
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        id: statusSpinner
        textFormat: Text.PlainText
        visible: module.busy && !module.paused
        text: module.spinnerFrames[module.spinnerFrame]
        color: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall * module.fontScale
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width - (statusSpinner.visible ? statusSpinner.width + Style.space(6) : 0)
        wrapMode: Text.WordWrap
        text: module.status
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall * module.fontScale
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      elide: Text.ElideMiddle
      visible: (module.busy || module.percent > 0) && module.currentFileName !== ""
      text: module.currentFileName
      color: Commons.Color.bar.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall * module.fontScale
      font.weight: Font.Medium
    }

    Rectangle {
      width: parent.width
      height: Style.space(8)
      color: Util.alpha(Commons.Color.muted, 0.25)
      visible: module.busy || module.percent > 0

      Rectangle {
        height: parent.height
        width: parent.width * (module.percent / 100)
        color: module.paused ? Commons.Color.muted : Commons.Color.accent
        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: module.busy || module.percent > 0
      text: {
        var parts = [module.percent + "%"]
        if (module.transferBytes) parts.push(module.transferBytes + " B")
        if (module.transferRate) parts.push(module.transferRate)
        if (module.transferEta) parts.push("ETA " + module.transferEta)
        return parts.join("  ·  ")
      }
      color: Commons.Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption * module.fontScale
    }

    Flow {
      width: parent.width
      spacing: Style.space(8)
      visible: module.busy

      SyncButton {
        label: "Pause"
        visible: module.busy && !module.paused
        onActivated: module.pause()
      }
      SyncButton {
        label: "Resume"
        visible: module.busy && module.paused
        onActivated: module.resume()
      }
      SyncButton {
        label: "Cancel"
        visible: module.busy
        onActivated: module.cancel()
      }
    }

    Flow {
      width: parent.width
      spacing: Style.space(8)
      visible: module.selectedCount > 0

      Text {
        textFormat: Text.PlainText
        height: Style.space(24)
        verticalAlignment: Text.AlignVCenter
        text: module.selectedCount + " selected"
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall * module.fontScale
      }
      SyncButton {
        label: module.confirmingBulkSync ? "Confirm sync of entire share?" : "Sync selected"
        enabled: !module.busy
        onActivated: module.syncSelected()
      }
      SyncButton {
        label: module.confirmingBulkUnsync ? "Confirm un-sync?" : "Un-sync selected"
        enabled: !module.busy
        onActivated: module.unsyncSelected()
      }
      SyncButton {
        label: "Clear selection"
        onActivated: { module.selectedPaths = ({}); module.confirmingBulkUnsync = false }
      }
    }
  }

  ListView {
    id: treeView
    anchors.top: topBar.bottom
    anchors.topMargin: Style.space(6)
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(12)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: module.rows

    delegate: Rectangle {
      id: treeRow
      required property var modelData
      width: treeView.width
      height: Style.space(26)
      readonly property bool selected: !!module.selectedPaths[treeRow.modelData.path]
      color: treeRow.selected ? Util.alpha(Commons.Color.accent, 0.18)
        : (rowPointer.containsMouse ? Util.alpha(Commons.Color.muted, 0.12) : "transparent")

      readonly property real indent: treeRow.modelData.depth * Style.space(13)
      readonly property bool isInfo: treeRow.modelData.kind === "info"
      readonly property bool confirming: !treeRow.isInfo && module.confirmingPath === treeRow.modelData.path
      readonly property bool syncing: !treeRow.isInfo && module.busy && !module.paused && module.activeSyncPaths.indexOf(treeRow.modelData.path) !== -1
      readonly property bool isPartial: treeRow.modelData.verifiedState === "partial"

      Text {
        id: syncGlyph
        textFormat: Text.PlainText
        x: Style.space(3) + treeRow.indent
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        horizontalAlignment: Text.AlignHCenter
        visible: !treeRow.isInfo
        text: treeRow.syncing ? module.spinnerFrames[module.spinnerFrame]
          : (treeRow.modelData.loading ? "…"
          : (treeRow.confirming ? "⚠"
          : (treeRow.isPartial ? "◐"
          : (treeRow.modelData.synced ? "✓" : "☁"))))
        color: treeRow.syncing ? Commons.Color.accent
          : (treeRow.confirming ? Commons.Color.urgent
          : (treeRow.isPartial ? Commons.Color.muted
          : (treeRow.modelData.synced ? Commons.Color.accent : Commons.Color.muted)))
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall * module.fontScale
      }

      Text {
        id: verifyGlyph
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.rightMargin: treeRow.modelData.depth === 0 ? Style.space(24) : Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        horizontalAlignment: Text.AlignHCenter
        visible: !treeRow.isInfo && treeRow.modelData.kind === "d" && treeRow.modelData.synced
          && treeRow.modelData.verifiedState === "" && !treeRow.modelData.verifying
        text: "?"
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption * module.fontScale
      }

      Text {
        id: disconnectGlyph
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        horizontalAlignment: Text.AlignHCenter
        visible: !treeRow.isInfo && treeRow.modelData.depth === 0 && !module.shareActionBusy
        text: "⏏"
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption * module.fontScale
      }

      Text {
        visible: treeRow.modelData.verifying
        anchors.right: parent.right
        anchors.rightMargin: treeRow.modelData.depth === 0 ? Style.space(24) : Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: module.spinnerFrames[module.spinnerFrame]
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption * module.fontScale
      }

      Text {
        id: disclosure
        textFormat: Text.PlainText
        x: syncGlyph.x + syncGlyph.width
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        horizontalAlignment: Text.AlignHCenter
        visible: treeRow.modelData.kind === "d"
        text: treeRow.modelData.expanded ? module.expanderOpenGlyph : module.expanderClosedGlyph
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall * module.fontScale
      }

      Text {
        id: icon
        textFormat: Text.PlainText
        x: disclosure.x + disclosure.width + Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        horizontalAlignment: Text.AlignHCenter
        visible: !treeRow.isInfo
        text: treeRow.modelData.kind === "d" ? (treeRow.modelData.expanded ? module.folderOpenGlyph : module.folderClosedGlyph) : module.fileGlyph
        color: treeRow.modelData.kind === "d" ? Commons.Color.accent : Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall * module.fontScale
      }

      Text {
        textFormat: Text.PlainText
        anchors.left: treeRow.isInfo ? parent.left : icon.right
        anchors.leftMargin: treeRow.isInfo ? Style.space(3) + treeRow.indent : Style.space(4)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: treeRow.confirming ? (treeRow.modelData.name + " — click again to confirm") : treeRow.modelData.name
        font.italic: treeRow.isInfo
        color: treeRow.isInfo ? Commons.Color.muted : (treeRow.confirming ? Commons.Color.urgent : Commons.Color.bar.text)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall * module.fontScale
      }

      MouseArea {
        id: rowPointer
        anchors.fill: parent
        hoverEnabled: true
        enabled: !treeRow.isInfo
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) {
            module.toggleSelected(treeRow.modelData.path)
            return
          }
          if (mouse.x >= syncGlyph.x && mouse.x <= syncGlyph.x + syncGlyph.width) {
            if (!treeRow.modelData.loading) module.requestToggle(treeRow.modelData)
            return
          }
          if (verifyGlyph.visible && mouse.x >= verifyGlyph.x - Style.space(2) && mouse.x <= verifyGlyph.x + verifyGlyph.width + Style.space(2)) {
            module.verifyPath(treeRow.modelData.path)
            return
          }
          if (disconnectGlyph.visible && mouse.x >= disconnectGlyph.x - Style.space(2) && mouse.x <= disconnectGlyph.x + disconnectGlyph.width + Style.space(2)) {
            module.disconnectShare(treeRow.modelData.path)
            return
          }
          if (treeRow.modelData.kind === "d") module.toggleExpand(treeRow.modelData.path)
          else module.openFile(treeRow.modelData.path)
        }
      }
    }
  }

  component SyncButton: Rectangle {
    id: btn
    property string label: ""
    property bool enabled: true
    signal activated()

    width: btnLabel.implicitWidth + Style.space(16)
    height: Style.space(24)
    visible: true
    color: !btn.enabled ? Util.alpha(Commons.Color.muted, 0.25) : (area.containsMouse ? Qt.lighter(Commons.Color.accent, 1.1) : Commons.Color.accent)

    Text {
      id: btnLabel
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: btn.label
      color: Commons.Color.background
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall * module.fontScale
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      enabled: btn.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.activated()
    }
  }
}
