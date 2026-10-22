import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../../lib/KeyRouter.js" as KeyRouter
import "../../theme"

FocusScope {
  id: module

  property var context: null
  readonly property var files: context ? context.service("files") : null
  readonly property bool backendReady: !!files && files.backendReady !== false
  readonly property bool active: !!context && context.bladeOpen !== false && context.collapsed !== true
  readonly property bool showHidden: !!files && files.showHidden === true
  readonly property color paneBackground: Qt.lighter(Commons.Color.background, 1.035)

  readonly property string title: "Network Storage"
  readonly property var shortcuts: [
    {
      title: "Network Storage",
      items: [
        { shortcut: "j / k, ↑ / ↓", text: "Move between rows" },
        { shortcut: "l / →", text: "Expand a folder or server, connect a share" },
        { shortcut: "h / ←", text: "Collapse, or go to the enclosing row" },
        { shortcut: "Enter", text: "Open a file, fold a folder or server, connect a share" },
        { shortcut: "Space", text: "Sync or un-sync the row" },
        { shortcut: "Ctrl+Space", text: "Add the row to the selection" },
        { shortcut: "c", text: "Check whether a synced folder is complete" },
        { shortcut: "d / Delete", text: "Eject a share, forget a previous server, or un-sync" },
        { shortcut: "/ or Ctrl+L", text: "Type a server address" },
        { shortcut: "Shift+R", text: "Look for servers again" }
      ]
    }
  ]

  readonly property string folderClosedGlyph: ""
  readonly property string folderOpenGlyph: ""
  readonly property string expanderClosedGlyph: ""
  readonly property string expanderOpenGlyph: ""
  readonly property string fileGlyph: "󰈔"
  readonly property string shareGlyph: "󰛳"
  readonly property string serverGlyph: "󰒋"
  readonly property string previousGlyph: "󰋚"
  readonly property string ejectGlyph: "󰇪"
  readonly property string forgetGlyph: "󰅖"

  readonly property int maxRowsPerFolder: 150

  property var lifetime: ({ alive: true })

  property var shares: []
  property var listings: ({})
  property var expanded: ({})
  property var loadingPaths: ({})
  property var syncedPaths: ({})
  property var verifiedPaths: ({})
  property var verifyingPaths: ({})

  property var savedServers: []
  property var discovered: []
  property bool discovering: false
  property var browsed: ({})
  property var browseOpen: ({})
  property var browseClosed: ({})
  property var browseLoading: ({})

  property string currentKey: ""
  property string confirmingPath: ""
  property var selectedPaths: ({})
  readonly property int selectedCount: Object.keys(module.selectedPaths).length
  property bool confirmingBulkUnsync: false
  property bool confirmingBulkSync: false

  property string newShareUri: ""
  property string shareActionStatus: ""
  property bool shareActionBusy: false

  property string status: "Idle"
  property bool busy: false
  property bool paused: false
  property bool cancelling: false
  property int percent: 0
  property string transferBytes: ""
  property string transferRate: ""
  property string transferEta: ""
  property string currentFileName: ""
  property var activeSyncPaths: []
  property string syncRequestId: ""
  property bool reattached: false

  readonly property var spinnerFrames: ["◐", "◓", "◑", "◒"]
  property int spinnerFrame: 0
  readonly property bool anyVerifying: Object.keys(module.verifyingPaths).length > 0

  function request(verb, args, callback, progress, options) {
    var life = module.lifetime
    var done = function(response) { if (life.alive && callback) callback(response) }
    var step = progress ? function(update) { if (life.alive) progress(update) } : null
    if (!module.files || typeof module.files.backendRequest !== "function") {
      done({ ok: false, error: "Omablade backend is unavailable" })
      return ""
    }
    return module.files.backendRequest("network-storage", [verb].concat(args || []), 0, done, step, 30000, options)
  }

  function text(value) {
    return typeof value === "string" ? value : ""
  }

  function cleanShares(list) {
    if (!Array.isArray(list)) return []
    return list.filter(function(share) { return share && typeof share.path === "string" && share.path.charAt(0) === "/" })
      .map(function(share) { return { path: share.path.replace(/\/+$/, ""), name: module.text(share.name), uri: module.text(share.uri) } })
  }

  function cleanEntries(list) {
    if (!Array.isArray(list)) return []
    return list.filter(function(entry) {
      var name = entry ? entry.name : null
      return typeof name === "string" && name !== "" && name !== "." && name !== ".." && name.indexOf("/") < 0
    }).map(function(entry) { return { name: entry.name, kind: entry.kind === "d" ? "d" : "f", synced: entry.synced === true } })
  }

  function cleanShareList(list) {
    if (!Array.isArray(list)) return []
    return list.filter(function(share) { return share && typeof share.uri === "string" && share.uri !== "" })
      .map(function(share) { return { name: module.text(share.name) || module.uriLabel(share.uri), uri: share.uri } })
  }

  function cleanServers(list) {
    if (!Array.isArray(list)) return []
    return list.filter(function(server) { return server && typeof server.uri === "string" && server.uri !== "" })
      .map(function(server) { return { name: module.text(server.name), uri: server.uri, source: module.text(server.source), shares: module.cleanShareList(server.shares) } })
  }

  function cleanSaved(list) {
    if (!Array.isArray(list)) return []
    return list.filter(function(uri) { return typeof uri === "string" && uri.indexOf("://") > 0 })
  }

  function failure(response, fallback) {
    return response && response.error ? String(response.error) : fallback
  }

  function same(left, right) {
    return JSON.stringify(left) === JSON.stringify(right)
  }

  function withKey(map, key, value) {
    var next = Object.assign({}, map)
    if (value === undefined) delete next[key]
    else next[key] = value
    return next
  }

  function normalUri(uri) {
    return String(uri || "").trim().replace(/\/+$/, "")
  }

  function uriParts(uri) {
    var match = module.normalUri(uri).match(/^([A-Za-z0-9+.-]+):\/\/(?:[^@\/]*@)?([^\/]+)(\/.*)?$/)
    if (!match) return null
    return { scheme: match[1], host: match[2], path: (match[3] || "").replace(/^\/+/, "") }
  }

  function uriHasShare(uri) {
    var parts = module.uriParts(uri)
    return !!parts && parts.path !== ""
  }

  readonly property var serverNames: {
    var names = {}
    for (var i = 0; i < module.discovered.length; i++) {
      var parts = module.uriParts(module.discovered[i].uri)
      if (parts && module.discovered[i].name) names[parts.host] = String(module.discovered[i].name)
    }
    return names
  }

  function uriLabel(uri) {
    var parts = module.uriParts(uri)
    if (!parts) return module.normalUri(uri)
    var host = module.serverNames[parts.host] || parts.host
    if (!parts.path) return host
    var segments = parts.path.split("/")
    return segments[segments.length - 1] + " on " + host
  }

  function shareLabel(share) {
    return share.uri ? module.uriLabel(share.uri) : String(share.name || share.path)
  }

  function baseName(path) {
    if (!path) return ""
    var parts = String(path).replace(/\/+$/, "").split("/")
    return parts[parts.length - 1] || path
  }

  function under(path, root) {
    return path === root || path.indexOf(root + "/") === 0
  }

  function pruneUnder(map, roots) {
    var next = {}
    var changed = false
    for (var key in map) {
      var gone = roots.some(function(root) { return module.under(key, root) })
      if (gone) changed = true
      else next[key] = map[key]
    }
    return changed ? next : map
  }

  function dropDescendants(map, path) {
    var next = {}
    var changed = false
    for (var key in map) {
      if (key.indexOf(path + "/") === 0) changed = true
      else next[key] = map[key]
    }
    return changed ? next : map
  }

  readonly property var rows: {
    var out = []
    var hidden = module.showHidden
    var visit = function(path, depth) {
      var entries = module.listings[path] || []
      var shown = entries.filter(function(entry) { return hidden || String(entry.name).charAt(0) !== "." })
      var capped = shown.length > module.maxRowsPerFolder
      var limit = capped ? module.maxRowsPerFolder : shown.length
      for (var i = 0; i < limit; i++) {
        var entry = shown[i]
        var child = path + "/" + entry.name
        out.push(module.treeRow(child, String(entry.name), entry.kind === "d" ? "d" : "f", depth, entry.synced))
        if (entry.kind === "d" && module.expanded[child]) visit(child, depth + 1)
      }
      if (capped) out.push({ type: "note", key: "n:" + path, text: "+ " + (shown.length - module.maxRowsPerFolder) + " more item(s) not shown", depth: depth })
    }
    for (var s = 0; s < module.shares.length; s++) {
      var share = module.shares[s]
      out.push(module.treeRow(share.path, module.shareLabel(share), "d", 0, false))
      if (module.expanded[share.path]) visit(share.path, 1)
    }
    return out
  }

  function treeRow(path, name, kind, depth, listedSynced) {
    var synced = module.syncedPaths[path] !== undefined ? module.syncedPaths[path] : !!listedSynced
    return {
      type: "tree", key: "t:" + path, path: path, name: name, kind: kind, depth: depth,
      isShare: depth === 0, expanded: !!module.expanded[path], loading: !!module.loadingPaths[path],
      synced: synced, verifiedState: synced ? (module.verifiedPaths[path] || "") : "", verifying: !!module.verifyingPaths[path]
    }
  }

  readonly property var connectedUris: {
    var out = {}
    for (var i = 0; i < module.shares.length; i++) if (module.shares[i].uri) out[module.normalUri(module.shares[i].uri)] = true
    return out
  }

  function serverRows(list, kind) {
    var out = []
    for (var i = 0; i < list.length; i++) {
      var uri = kind === "saved" ? String(list[i]) : String(list[i].uri || "")
      var key = module.normalUri(uri)
      if (!key || module.connectedUris[key]) continue
      var name = kind === "saved" ? module.uriLabel(uri) : String(list[i].name || module.uriLabel(uri))
      var expandable = !module.uriHasShare(uri)
      var open = expandable && !!module.browseOpen[key]
      out.push({ type: "server", key: "s:" + kind + ":" + key, kind: kind, uri: uri, name: name, expandable: expandable, expanded: open, loading: !!module.browseLoading[key], depth: 0 })
      if (!open) continue
      var found = module.browsed[key]
      if (!found) continue
      if (found.error) {
        out.push({ type: "note", key: "n:" + kind + ":" + key, text: found.error, depth: 1 })
        continue
      }
      var shown = 0
      for (var j = 0; j < found.shares.length; j++) {
        var share = found.shares[j]
        if (module.connectedUris[module.normalUri(share.uri)]) continue
        shown++
        out.push({ type: "server", key: "s:" + kind + ":" + module.normalUri(share.uri), kind: "share", uri: String(share.uri), name: String(share.name), parentKey: "s:" + kind + ":" + key, expandable: false, expanded: false, loading: false, depth: 1 })
      }
      if (shown === 0) out.push({ type: "note", key: "n:" + kind + ":" + key, text: found.shares.length > 0 ? "All shares connected" : "No shares", depth: 1 })
    }
    return out
  }

  readonly property var displayRows: {
    var out = [{ type: "header", key: "h:connected", text: "Connected" }]
    if (module.rows.length === 0) out.push({ type: "note", key: "n:connected", text: "No servers connected", depth: 0 })
    out = out.concat(module.rows)
    out.push({ type: "header", key: "h:available", text: "Available on Current Network" })
    var available = module.serverRows(module.discovered, "discovered")
    if (available.length === 0) out.push({ type: "note", key: "n:available", text: module.discovering ? "Searching…" : "No servers found", depth: 0 })
    out = out.concat(available)
    var previous = module.serverRows(module.savedServers, "saved")
    if (previous.length > 0) out = out.concat([{ type: "header", key: "h:previous", text: "Previous Servers" }], previous)
    return out
  }

  function actionable(row) {
    return !!row && (row.type === "tree" || row.type === "server")
  }

  function indexOfKey(key) {
    for (var i = 0; i < module.displayRows.length; i++) if (module.displayRows[i].key === key) return i
    return -1
  }

  readonly property int currentIndex: module.indexOfKey(module.currentKey)
  readonly property var currentRow: module.currentIndex >= 0 ? module.displayRows[module.currentIndex] : null

  function moveTo(index) {
    if (index < 0 || index >= module.displayRows.length) return
    module.currentKey = module.displayRows[index].key
    treeView.positionViewAtIndex(index, ListView.Contain)
  }

  function step(delta) {
    var rows = module.displayRows
    var start = module.currentIndex
    if (start < 0) start = delta > 0 ? -1 : rows.length
    for (var i = start + delta; i >= 0 && i < rows.length; i += delta) {
      if (module.actionable(rows[i])) { module.moveTo(i); return true }
    }
    return false
  }

  function edge(last) {
    var rows = module.displayRows
    for (var n = 0; n < rows.length; n++) {
      var i = last ? rows.length - 1 - n : n
      if (module.actionable(rows[i])) { module.moveTo(i); return }
    }
  }

  function page(delta) {
    var count = Math.max(1, Math.floor(treeView.height / Style.space(26)) - 1)
    for (var i = 0; i < count; i++) if (!module.step(delta)) break
  }

  function parentKey(row) {
    if (row.type === "server") return row.parentKey || ""
    if (row.type !== "tree" || row.depth === 0) return ""
    return "t:" + row.path.slice(0, row.path.lastIndexOf("/"))
  }

  function goUp() {
    var row = module.currentRow
    if (!row) return
    if (row.type === "tree" && row.kind === "d" && row.expanded) { module.toggleExpand(row.path); return }
    if (row.type === "server" && row.expanded) { module.toggleBrowse(row.uri); return }
    var parent = module.parentKey(row)
    if (parent) module.moveTo(module.indexOfKey(parent))
  }

  function goIn() {
    var row = module.currentRow
    if (!row) return
    if (row.type === "tree") {
      if (row.kind !== "d") module.openFile(row.path)
      else if (!row.expanded) module.toggleExpand(row.path)
      else module.step(1)
      return
    }
    if (row.type === "server") {
      if (row.expandable && !row.expanded) module.toggleBrowse(row.uri)
      else if (row.expandable) module.step(1)
      else module.addShare(row.uri)
    }
  }

  function activateRow(row) {
    if (!row) return
    if (row.type === "tree") {
      if (row.kind === "d") module.toggleExpand(row.path)
      else module.openFile(row.path)
    } else if (row.type === "server") {
      module.openServer(row.uri)
    }
  }

  function removeRow(row) {
    if (!row) return
    if (row.type === "server" && row.kind === "saved") module.removeShare(row.uri)
    else if (row.type === "tree" && row.isShare && !row.synced) module.disconnectShare(row.path)
    else if (row.type === "tree" && row.synced) module.requestToggle(row)
  }

  function focusAddress() {
    shareInput.forceActiveFocus()
    shareInput.selectAll()
  }

  function handleKey(event) {
    var row = module.currentRow
    if (event.key === Qt.Key_Space && (event.modifiers & Qt.ControlModifier)) {
      if (row && row.type === "tree") module.toggleSelected(row.path)
      return true
    }
    if (event.key === Qt.Key_Space && KeyRouter.noModifiers(event.modifiers)) {
      if (row && row.type === "tree" && !row.loading) module.requestToggle(row)
      else if (row && row.type === "server") module.openServer(row.uri)
      return true
    }
    if (event.key === Qt.Key_L && KeyRouter.exactControl(event.modifiers)) { module.focusAddress(); return true }
    if (event.key === Qt.Key_R && event.modifiers === Qt.ShiftModifier) { module.loadAll(); return true }
    if (event.key === Qt.Key_C && KeyRouter.noModifiers(event.modifiers)) {
      if (row && row.type === "tree" && row.kind === "d" && row.synced) module.verifyPath(row.path)
      return true
    }
    var action = KeyRouter.artifactAction(event)
    if (!action) return false
    if (event.isAutoRepeat && KeyRouter.ignoresAutoRepeat(action, event.key)) return true
    switch (action) {
      case "next": module.step(1); break
      case "previous": module.step(-1); break
      case "first": module.edge(false); break
      case "last": module.edge(true); break
      case "page-next": module.page(1); break
      case "page-previous": module.page(-1); break
      case "up": module.goUp(); break
      case "open": module.goIn(); break
      case "activate": module.activateRow(row); break
      case "action": module.removeRow(row); break
      case "search": module.focusAddress(); break
      case "focus-next": if (module.context && module.context.focusNext) module.context.focusNext(); break
      case "focus-previous": if (module.context && module.context.focusPrevious) module.context.focusPrevious(); break
      case "help": if (module.context && module.context.hostWindow) module.context.hostWindow.shortcutsOpen = true; break
      case "dismiss":
        if (module.confirmingPath || module.confirmingBulkSync || module.confirmingBulkUnsync) module.clearConfirmations()
        else if (module.selectedCount > 0) module.selectedPaths = ({})
        else if (module.context && module.context.closeBlade) module.context.closeBlade()
        break
      default: return false
    }
    return true
  }

  function clearConfirmations() {
    module.confirmingPath = ""
    module.confirmingBulkUnsync = false
    module.confirmingBulkSync = false
  }

  function selectionHasRoot() {
    for (var i = 0; i < module.shares.length; i++) if (module.selectedPaths[module.shares[i].path]) return true
    return false
  }

  function toggleSelected(path) {
    module.selectedPaths = module.withKey(module.selectedPaths, path, module.selectedPaths[path] ? undefined : true)
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
    onTriggered: module.clearConfirmations()
  }

  Timer {
    id: statusClear
    interval: 6000
    onTriggered: if (!module.busy) module.status = "Idle"
  }

  Timer {
    interval: 150
    repeat: true
    running: module.active && ((module.busy && !module.paused) || module.anyVerifying || module.discovering || Object.keys(module.browseLoading).length > 0)
    onTriggered: module.spinnerFrame = (module.spinnerFrame + 1) % module.spinnerFrames.length
  }

  Timer {
    interval: 5000
    running: module.backendReady && module.active
    repeat: true
    onTriggered: module.refreshShares()
  }

  Timer {
    interval: 30000
    running: module.backendReady && module.active
    repeat: true
    onTriggered: module.discover()
  }

  Timer {
    id: reattachPoll
    interval: 3000
    repeat: true
    onTriggered: module.checkActive()
  }

  onBackendReadyChanged: if (backendReady) module.loadAll()
  onNewShareUriChanged: if (shareInput.text !== newShareUri) shareInput.text = newShareUri
  onActiveChanged: if (active && backendReady) { module.refreshShares(); module.discover() }
  Component.onCompleted: if (backendReady) module.loadAll()
  Component.onDestruction: module.lifetime.alive = false

  function loadAll() {
    module.refreshShares()
    module.refreshSaved()
    module.discover()
    module.checkActive()
  }

  function checkActive() {
    module.request("active", [], function(response) {
      if (response && response.ok && response.active) {
        if (module.syncRequestId) return
        module.busy = true
        module.paused = !!response.paused
        module.reattached = true
        var path = module.text(response.path)
        var queued = Array.isArray(response.paths) ? response.paths.filter(function(item) { return typeof item === "string" }) : []
        module.activeSyncPaths = queued.length > 0 ? queued : (path ? [path] : [])
        module.currentFileName = path ? module.baseName(path) : ""
        if (!module.cancelling) module.status = (module.paused ? "Paused" : "Syncing") + " (reattached after reload)…"
        if (response.progress && typeof response.progress === "object") module.applyProgress(response.progress)
        reattachPoll.running = true
      } else if (module.reattached) {
        var last = response && response.last && typeof response.last === "object" ? response.last : null
        var finished = module.activeSyncPaths.slice()
        module.finishTransfer()
        module.reattached = false
        reattachPoll.running = false
        if (module.cancelling || (last && last.cancelled)) {
          module.status = "Cancelled"
        } else if (last && last.ok) {
          module.percent = 100
          module.status = "Done"
        } else if (last && last.error) {
          module.status = "Failed: " + module.text(last.error)
        } else {
          module.status = "Idle"
        }
        if (module.status.indexOf("Failed") !== 0) statusClear.restart()
        module.cancelling = false
        module.refreshStatusUnder(finished.length > 0 ? finished : module.shares.map(function(share) { return share.path }))
      }
    })
  }

  function refreshSaved() {
    module.request("saved", [], function(response) {
      if (response && response.ok && !module.same(module.savedServers, module.cleanSaved(response.servers))) module.savedServers = module.cleanSaved(response.servers)
    })
  }

  function discover() {
    if (module.discovering) return
    module.discovering = true
    module.request("discover", [], function(response) {
      module.discovering = false
      if (!response || !response.ok) return
      var servers = module.cleanServers(response.servers)
      var found = Object.assign({}, module.browsed)
      var open = Object.assign({}, module.browseOpen)
      for (var i = 0; i < servers.length; i++) {
        var key = module.normalUri(servers[i].uri)
        found[key] = { shares: servers[i].shares, error: "" }
        if (!module.browseClosed[key]) open[key] = true
      }
      if (!module.same(found, module.browsed)) module.browsed = found
      if (!module.same(open, module.browseOpen)) module.browseOpen = open
      if (!module.same(servers, module.discovered)) module.discovered = servers
    }, null, { untimed: true })
  }

  function toggleBrowse(uri, forceOpen) {
    var key = module.normalUri(uri)
    if (module.browseOpen[key] && !forceOpen) {
      module.browseOpen = module.withKey(module.browseOpen, key, undefined)
      module.browseClosed = module.withKey(module.browseClosed, key, true)
      return
    }
    module.browseClosed = module.withKey(module.browseClosed, key, undefined)
    module.browseOpen = module.withKey(module.browseOpen, key, true)
    if (module.browsed[key] && !module.browsed[key].error) return
    module.browseLoading = module.withKey(module.browseLoading, key, true)
    module.request("browse", ["--", uri], function(response) {
      module.browseLoading = module.withKey(module.browseLoading, key, undefined)
      module.browsed = module.withKey(module.browsed, key, response && response.ok
        ? { shares: module.cleanShareList(response.shares), error: "" }
        : { shares: [], error: module.failure(response, "could not browse " + uri) })
    }, null, { untimed: true })
  }

  function openServer(uri) {
    if (module.uriHasShare(uri)) module.addShare(uri)
    else module.toggleBrowse(uri)
  }

  function addShare(uri) {
    var trimmed = String(uri || "").trim()
    if (!trimmed || module.shareActionBusy) return
    if (trimmed.indexOf("://") < 0) {
      module.shareActionStatus = "Failed: type an address such as smb://server/share"
      return
    }
    var typed = module.normalUri(module.newShareUri) === module.normalUri(trimmed)
    if (!module.uriHasShare(trimmed)) {
      module.request("remember", ["--", trimmed], function(response) {
        if (!response || !response.ok) {
          module.shareActionStatus = "Failed: " + module.failure(response, "not a server address")
          return
        }
        module.shareActionStatus = ""
        if (typed) module.newShareUri = ""
        if (!module.same(module.savedServers, module.cleanSaved(response.servers))) module.savedServers = module.cleanSaved(response.servers)
        module.toggleBrowse(trimmed, true)
        module.currentKey = "s:saved:" + module.normalUri(trimmed)
      })
      return
    }
    module.shareActionBusy = true
    module.shareActionStatus = "Connecting to " + module.uriLabel(trimmed) + "…"
    module.request("connect", ["--", trimmed], function(response) {
      module.shareActionBusy = false
      if (response && response.ok) {
        module.shareActionStatus = ""
        if (typed) module.newShareUri = ""
        if (!module.same(module.savedServers, module.cleanSaved(response.servers))) module.savedServers = module.cleanSaved(response.servers)
      } else {
        module.shareActionStatus = "Failed: " + module.failure(response, "could not connect")
      }
      module.refreshShares()
    }, null, { untimed: true })
  }

  function removeShare(uri) {
    if (module.shareActionBusy) return
    module.request("forget", ["--", uri], function(response) {
      if (response && response.ok) module.savedServers = module.cleanSaved(response.servers)
      else module.shareActionStatus = "Failed: " + module.failure(response, "could not forget")
    })
  }

  function disconnectShare(path) {
    if (module.shareActionBusy) return
    if (module.busy && module.activeSyncPaths.some(function(active) { return module.under(active, path) })) {
      module.shareActionStatus = "Failed: cancel the sync before ejecting this share"
      return
    }
    module.shareActionBusy = true
    module.shareActionStatus = "Disconnecting…"
    module.request("disconnect", ["--", path], function(response) {
      module.shareActionBusy = false
      module.shareActionStatus = response && response.ok ? "" : "Failed: " + module.failure(response, "could not disconnect")
      module.refreshShares()
    }, null, { untimed: true })
  }

  function refreshShares() {
    module.request("shares", [], function(response) {
      if (!response || !response.ok) return
      var found = module.cleanShares(response.shares)
      if (module.same(found, module.shares)) return
      var keep = {}
      for (var i = 0; i < found.length; i++) keep[found[i].path] = true
      var gone = module.shares.filter(function(share) { return !keep[share.path] }).map(function(share) { return share.path })
      var added = found.filter(function(share) { return !module.shares.some(function(old) { return old.path === share.path }) })
      module.shares = found
      if (gone.length > 0) {
        module.listings = module.pruneUnder(module.listings, gone)
        module.expanded = module.pruneUnder(module.expanded, gone)
        module.loadingPaths = module.pruneUnder(module.loadingPaths, gone)
        module.syncedPaths = module.pruneUnder(module.syncedPaths, gone)
        module.verifiedPaths = module.pruneUnder(module.verifiedPaths, gone)
        module.verifyingPaths = module.pruneUnder(module.verifyingPaths, gone)
        module.selectedPaths = module.pruneUnder(module.selectedPaths, gone)
      }
      for (var j = 0; j < added.length; j++) module.checkStatus(added[j].path)
    })
  }

  function refreshStatusUnder(paths) {
    var rows = module.rows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].type !== "tree") continue
      var path = rows[i].path
      if (paths.some(function(root) { return module.under(path, root) || module.under(root, path) })) module.checkStatus(path)
    }
  }

  function toggleExpand(path) {
    if (module.loadingPaths[path]) return
    if (module.expanded[path]) {
      module.expanded = module.withKey(module.expanded, path, undefined)
      module.selectedPaths = module.dropDescendants(module.selectedPaths, path)
      if (module.currentKey.indexOf("t:" + path + "/") === 0) module.currentKey = "t:" + path
      return
    }
    module.expanded = module.withKey(module.expanded, path, true)
    module.loadingPaths = module.withKey(module.loadingPaths, path, true)
    module.request("list", ["--", path], function(response) {
      module.loadingPaths = module.withKey(module.loadingPaths, path, undefined)
      if (!response || !response.ok) {
        module.expanded = module.withKey(module.expanded, path, undefined)
        module.status = "Failed: " + module.failure(response, "could not list " + path)
        statusClear.stop()
        return
      }
      var entries = module.cleanEntries(response.entries)
      if (!module.same(entries, module.listings[path])) module.listings = module.withKey(module.listings, path, entries)
      var kept = {}
      var changed = false
      for (var key in module.syncedPaths) {
        if (key.indexOf(path + "/") === 0 && key.slice(path.length + 1).indexOf("/") < 0) changed = true
        else kept[key] = module.syncedPaths[key]
      }
      if (changed) module.syncedPaths = kept
    })
  }

  function checkStatus(path) {
    module.request("status", ["--", path], function(response) {
      if (!response || !response.ok) return
      var synced = response.synced === true
      if (module.syncedPaths[path] !== synced) module.syncedPaths = module.withKey(module.syncedPaths, path, synced)
      if (module.verifiedPaths[path] !== undefined) module.verifiedPaths = module.withKey(module.verifiedPaths, path, undefined)
    })
  }

  function verifyPath(path) {
    if (module.verifyingPaths[path]) return
    module.verifyingPaths = module.withKey(module.verifyingPaths, path, true)
    module.request("check", ["--", path], function(response) {
      module.verifyingPaths = module.withKey(module.verifyingPaths, path, undefined)
      if (!response || !response.ok) {
        module.status = "Failed: " + module.failure(response, "could not check " + path)
        return
      }
      var state = String(response.state)
      module.syncedPaths = module.withKey(module.syncedPaths, path, state !== "not-synced")
      module.verifiedPaths = module.withKey(module.verifiedPaths, path, state === "partial" ? "partial" : (state === "synced" ? "synced" : undefined))
    }, null, { untimed: true })
  }

  function requestToggle(row) {
    if (module.busy) return
    var effectivelySynced = row.synced && row.verifiedState !== "partial"
    if (!row.isShare) {
      module.runBatch([row.path], effectivelySynced ? "unsync" : "sync")
      return
    }
    if (module.confirmingPath === row.path) {
      confirmResetTimer.stop()
      module.confirmingPath = ""
      module.runBatch([row.path], effectivelySynced ? "unsync" : "sync")
      return
    }
    module.confirmingPath = row.path
    confirmResetTimer.restart()
  }

  function applyProgress(update) {
    if (!update || typeof update !== "object") return
    var value = parseInt(update.percent, 10)
    if (isFinite(value)) module.percent = Math.max(0, Math.min(100, value))
    module.transferBytes = module.text(update.bytes)
    module.transferRate = module.text(update.rate)
    module.transferEta = module.text(update.eta)
    if (module.text(update.path)) module.currentFileName = module.baseName(update.path)
  }

  function finishTransfer() {
    module.busy = false
    module.paused = false
    module.activeSyncPaths = []
    module.syncRequestId = ""
    module.transferBytes = ""
    module.transferRate = ""
    module.transferEta = ""
    module.currentFileName = ""
  }

  function runBatch(paths, verb) {
    if (module.busy || paths.length === 0) return
    module.clearConfirmations()
    statusClear.stop()
    module.busy = true
    module.paused = false
    module.cancelling = false
    module.percent = 0
    module.transferBytes = ""
    module.transferRate = ""
    module.transferEta = ""
    module.activeSyncPaths = paths
    module.currentFileName = paths.length === 1 ? module.baseName(paths[0]) : ""
    module.status = (verb === "unsync" ? "Removing " : "Syncing ") + (paths.length > 1 ? paths.length + " items…" : "…")
    var finished = function(response) {
      var cancelled = module.cancelling
      module.finishTransfer()
      module.cancelling = false
      if (cancelled) {
        module.status = "Cancelled"
        statusClear.restart()
      } else if (!response || response.ok !== true) {
        var problems = response && Array.isArray(response.results) ? response.results.filter(function(r) { return r.error }).map(function(r) { return r.error }) : []
        module.status = "Failed: " + (problems.length ? problems.join("; ") : module.failure(response, verb + " failed"))
      } else if (verb === "unsync") {
        var removed = (response.results || []).filter(function(r) { return r.state === "unsynced" }).length
        module.status = removed > 0 ? (removed > 1 ? "Removed " + removed + " local copies" : "Removed local copy") : "Nothing to remove"
        statusClear.restart()
      } else {
        module.percent = 100
        module.status = "Done"
        statusClear.restart()
      }
      module.refreshStatusUnder(paths)
      module.selectedPaths = ({})
    }
    module.syncRequestId = module.request(verb, ["--"].concat(paths), finished, verb === "sync" ? module.applyProgress : null, { untimed: true })
  }

  function control(verb, onFailure) {
    module.request(verb, [], function(response) {
      if (response && response.ok) return
      module.status = "Failed: " + module.failure(response, verb + " failed")
      if (onFailure) onFailure()
    })
  }

  function pause() {
    if (!module.busy || module.paused || module.cancelling) return
    module.paused = true
    module.status = "Paused at " + module.percent + "%"
    module.control("pause", function() { module.paused = false })
  }

  function resume() {
    if (!module.busy || !module.paused || module.cancelling) return
    module.paused = false
    module.status = "Syncing…"
    module.control("resume", function() { module.paused = true })
  }

  function cancel() {
    if (!module.busy || module.cancelling) return
    module.cancelling = true
    module.status = "Cancelling…"
    module.control("cancel", function() { module.cancelling = false })
  }

  function openFile(path) {
    if (module.files && typeof module.files.openDefault === "function")
      module.files.openDefault(path, undefined, false)
  }

  Rectangle { anchors.fill: parent; color: module.paneBackground }

  ListView {
    id: treeView
    objectName: "networkStorageList"
    anchors.top: parent.top
    anchors.topMargin: Style.space(6)
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.bottom: bottomBar.top
    anchors.bottomMargin: Style.space(6)
    clip: true
    focus: true
    activeFocusOnTab: true
    boundsBehavior: Flickable.StopAtBounds
    model: module.displayRows
    property real keptY: 0
    onContentYChanged: if (count > 0) keptY = contentY
    onModelChanged: {
      var y = keptY
      Qt.callLater(function() { treeView.contentY = Math.max(0, Math.min(y, Math.max(0, treeView.contentHeight - treeView.height))) })
    }
    onActiveFocusChanged: if (activeFocus && module.currentIndex < 0) module.step(1)
    Keys.onPressed: function(event) { if (module.handleKey(event)) event.accepted = true }

    delegate: Loader {
      id: rowLoader
      required property var modelData
      width: treeView.width
      height: item ? item.height : 0
      sourceComponent: rowLoader.modelData.type === "header" ? headerRow
        : (rowLoader.modelData.type === "tree" ? treeRowComponent
        : (rowLoader.modelData.type === "server" ? serverRowComponent : noteRow))
      onLoaded: item.modelData = rowLoader.modelData
    }
  }

  component RowBackground: Rectangle {
    property bool current: false
    property bool hovered: false
    property bool selected: false
    color: selected ? Util.alpha(Commons.Color.accent, 0.18)
      : (current && treeView.activeFocus ? Util.alpha(Commons.Color.accent, 0.12)
      : (hovered || current ? Util.alpha(Commons.Color.muted, 0.12) : "transparent"))
  }

  Component {
    id: headerRow
    Item {
      property var modelData
      width: treeView.width
      height: Style.space(28)
      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(3)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(4)
        text: parent.modelData ? parent.modelData.text : ""
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Typography.caption
        font.weight: Font.DemiBold
      }
    }
  }

  Component {
    id: noteRow
    Item {
      property var modelData
      width: treeView.width
      height: Style.space(22)
      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6) + (parent.modelData ? parent.modelData.depth || 0 : 0) * Style.space(13)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: parent.modelData ? parent.modelData.text : ""
        color: Commons.Color.muted
        font.italic: true
        font.family: Style.font.family
        font.pixelSize: Typography.bodySmall
      }
    }
  }

  Component {
    id: serverRowComponent
    RowBackground {
      id: serverRow
      property var modelData: ({})
      readonly property real indent: (serverRow.modelData.depth || 0) * Style.space(13)
      width: treeView.width
      height: Style.space(26)
      current: serverRow.modelData.key === module.currentKey
      hovered: serverPointer.containsMouse

      Text {
        id: serverDisclosure
        textFormat: Text.PlainText
        x: Style.space(17) + serverRow.indent
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        horizontalAlignment: Text.AlignHCenter
        visible: !!serverRow.modelData.expandable
        text: serverRow.modelData.loading ? module.spinnerFrames[module.spinnerFrame]
          : (serverRow.modelData.expanded ? module.expanderOpenGlyph : module.expanderClosedGlyph)
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Typography.bodySmall
      }

      Text {
        id: serverIcon
        textFormat: Text.PlainText
        x: serverDisclosure.x + serverDisclosure.width + Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        horizontalAlignment: Text.AlignHCenter
        text: serverRow.modelData.kind === "share" ? module.shareGlyph
          : (serverRow.modelData.kind === "saved" ? module.previousGlyph : module.serverGlyph)
        color: serverRow.modelData.kind === "share" ? Commons.Color.accent : Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Typography.bodySmall
      }

      Text {
        textFormat: Text.PlainText
        anchors.left: serverIcon.right
        anchors.leftMargin: Style.space(4)
        anchors.right: forgetGlyphText.visible ? forgetGlyphText.left : parent.right
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideMiddle
        text: serverRow.modelData.name || ""
        color: Commons.Color.bar.text
        font.family: Style.font.family
        font.pixelSize: Typography.bodySmall
      }

      Text {
        id: forgetGlyphText
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        horizontalAlignment: Text.AlignHCenter
        visible: serverRow.modelData.kind === "saved" && (serverPointer.containsMouse || serverRow.current)
        text: module.forgetGlyph
        color: Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Typography.caption
      }

      MouseArea {
        id: serverPointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          module.currentKey = serverRow.modelData.key
          treeView.forceActiveFocus()
          if (forgetGlyphText.visible && mouse.x >= forgetGlyphText.x - Style.space(2)) {
            module.removeShare(serverRow.modelData.uri)
            return
          }
          module.openServer(serverRow.modelData.uri)
        }
      }
    }
  }

  Component {
    id: treeRowComponent
    RowBackground {
      id: treeRow
      property var modelData: ({ path: "", name: "", kind: "", depth: 0 })
      width: treeView.width
      height: Style.space(26)
      current: treeRow.modelData.key === module.currentKey
      hovered: rowPointer.containsMouse
      selected: !!module.selectedPaths[treeRow.modelData.path]

      readonly property real indent: treeRow.modelData.depth * Style.space(13)
      readonly property bool isShare: !!treeRow.modelData.isShare
      readonly property bool confirming: module.confirmingPath === treeRow.modelData.path
      readonly property bool syncing: module.busy && !module.paused && module.activeSyncPaths.indexOf(treeRow.modelData.path) !== -1
      readonly property bool isPartial: treeRow.modelData.verifiedState === "partial"

      Text {
        id: syncGlyph
        textFormat: Text.PlainText
        x: Style.space(3) + treeRow.indent
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        horizontalAlignment: Text.AlignHCenter
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
        font.pixelSize: Typography.bodySmall
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
        font.pixelSize: Typography.bodySmall
      }

      Text {
        id: icon
        textFormat: Text.PlainText
        x: disclosure.x + disclosure.width + Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        horizontalAlignment: Text.AlignHCenter
        text: treeRow.isShare ? module.shareGlyph
          : (treeRow.modelData.kind === "d" ? (treeRow.modelData.expanded ? module.folderOpenGlyph : module.folderClosedGlyph) : module.fileGlyph)
        color: treeRow.modelData.kind === "d" ? Commons.Color.accent : Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Typography.bodySmall
      }

      Text {
        textFormat: Text.PlainText
        anchors.left: icon.right
        anchors.leftMargin: Style.space(4)
        anchors.right: trailing.left
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: treeRow.confirming
          ? (treeRow.modelData.name + " — " + (treeRow.modelData.synced && !treeRow.isPartial ? "un-sync" : "sync") + " the whole share? Again to confirm")
          : treeRow.modelData.name
        color: treeRow.confirming ? Commons.Color.urgent : Commons.Color.bar.text
        font.family: Style.font.family
        font.pixelSize: Typography.bodySmall
      }

      Row {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          id: verifyGlyph
          textFormat: Text.PlainText
          width: Style.space(14)
          horizontalAlignment: Text.AlignHCenter
          visible: treeRow.modelData.kind === "d" && !!treeRow.modelData.synced
          text: treeRow.modelData.verifying ? module.spinnerFrames[module.spinnerFrame] : "?"
          color: Commons.Color.muted
          font.family: Style.font.family
          font.pixelSize: Typography.caption
        }

        Text {
          id: disconnectGlyph
          textFormat: Text.PlainText
          width: Style.space(14)
          horizontalAlignment: Text.AlignHCenter
          visible: treeRow.isShare
          opacity: module.shareActionBusy ? 0.4 : 1
          text: module.ejectGlyph
          color: Commons.Color.muted
          font.family: Style.font.family
          font.pixelSize: Typography.caption
        }
      }

      MouseArea {
        id: rowPointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          module.currentKey = treeRow.modelData.key
          treeView.forceActiveFocus()
          if (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) {
            module.toggleSelected(treeRow.modelData.path)
            return
          }
          if (mouse.x >= syncGlyph.x && mouse.x <= syncGlyph.x + syncGlyph.width) {
            if (!treeRow.modelData.loading) module.requestToggle(treeRow.modelData)
            return
          }
          var local = mapToItem(trailing, mouse.x, mouse.y)
          if (verifyGlyph.visible && local.x >= verifyGlyph.x - Style.space(2) && local.x <= verifyGlyph.x + verifyGlyph.width + Style.space(2)) {
            module.verifyPath(treeRow.modelData.path)
            return
          }
          if (disconnectGlyph.visible && local.x >= disconnectGlyph.x - Style.space(2) && local.x <= disconnectGlyph.x + disconnectGlyph.width + Style.space(2)) {
            module.disconnectShare(treeRow.modelData.path)
            return
          }
          module.activateRow(treeRow.modelData)
        }
      }
    }
  }

  Column {
    id: bottomBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    Row {
      width: parent.width
      spacing: Style.space(6)
      visible: module.busy || module.status !== "Idle"

      Text {
        id: statusSpinner
        textFormat: Text.PlainText
        visible: module.busy && !module.paused
        text: module.spinnerFrames[module.spinnerFrame]
        color: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Typography.bodySmall
      }

      Text {
        objectName: "networkStorageStatus"
        textFormat: Text.PlainText
        width: parent.width - (statusSpinner.visible ? statusSpinner.width + Style.space(6) : 0)
        wrapMode: Text.WordWrap
        text: module.status
        color: module.status.indexOf("Failed") === 0 ? Commons.Color.urgent : Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Typography.bodySmall
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      elide: Text.ElideMiddle
      visible: module.busy && module.currentFileName !== ""
      text: module.currentFileName
      color: Commons.Color.bar.text
      font.family: Style.font.family
      font.pixelSize: Typography.bodySmall
      font.weight: Font.Medium
    }

    Rectangle {
      width: parent.width
      height: Style.space(6)
      color: Util.alpha(Commons.Color.muted, 0.25)
      visible: module.busy && module.status.indexOf("Removing") !== 0

      Rectangle {
        height: parent.height
        width: parent.width * (module.percent / 100)
        color: module.paused ? Commons.Color.muted : Commons.Color.accent
        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: module.busy && module.status.indexOf("Removing") !== 0
      text: {
        var parts = [module.percent + "%"]
        if (module.transferBytes) parts.push(module.transferBytes)
        if (module.transferRate) parts.push(module.transferRate)
        if (module.transferEta) parts.push("ETA " + module.transferEta)
        return parts.join("  ·  ")
      }
      color: Commons.Color.muted
      font.family: Style.font.family
      font.pixelSize: Typography.caption
    }

    Flow {
      width: parent.width
      spacing: Style.space(8)
      visible: module.busy && module.status.indexOf("Removing") !== 0

      SyncButton { label: "Pause"; visible: !module.paused; available: !module.cancelling; onActivated: module.pause() }
      SyncButton { label: "Resume"; visible: module.paused; available: !module.cancelling; onActivated: module.resume() }
      SyncButton { label: "Cancel"; available: !module.cancelling; onActivated: module.cancel() }
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
        font.pixelSize: Typography.bodySmall
      }
      SyncButton {
        label: module.confirmingBulkSync ? "Confirm sync of entire share?" : "Sync selected"
        available: !module.busy
        onActivated: module.syncSelected()
      }
      SyncButton {
        label: module.confirmingBulkUnsync ? "Confirm un-sync?" : "Un-sync selected"
        available: !module.busy
        onActivated: module.unsyncSelected()
      }
      SyncButton {
        label: "Clear selection"
        onActivated: { module.selectedPaths = ({}); module.clearConfirmations() }
      }
    }

    Text {
      objectName: "networkStorageShareStatus"
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      visible: module.shareActionStatus !== ""
      text: module.shareActionStatus
      color: module.shareActionBusy ? Commons.Color.muted : Commons.Color.urgent
      font.family: Style.font.family
      font.pixelSize: Typography.caption
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(Commons.Color.muted, 0.25)
    }

    Text {
      textFormat: Text.PlainText
      text: "Connect to Server"
      color: Commons.Color.muted
      font.family: Style.font.family
      font.pixelSize: Typography.caption
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
          objectName: "networkStorageAddress"
          anchors.fill: parent
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          activeFocusOnTab: true
          text: module.newShareUri
          onTextChanged: { module.newShareUri = text; if (module.shareActionStatus.indexOf("Failed") === 0) module.shareActionStatus = "" }
          color: Commons.Color.bar.text
          font.family: Style.font.family
          font.pixelSize: Typography.bodySmall
          Keys.onReturnPressed: module.addShare(module.newShareUri)
          Keys.onEnterPressed: module.addShare(module.newShareUri)
          Keys.onEscapePressed: treeView.forceActiveFocus()

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            visible: !shareInput.text && !shareInput.activeFocus
            text: "Enter server address…"
            color: Commons.Color.muted
            font.family: Style.font.family
            font.pixelSize: Typography.bodySmall
          }
        }
      }

      SyncButton {
        id: connectBtn
        label: "Connect"
        available: !module.shareActionBusy && module.newShareUri.trim() !== ""
        onActivated: module.addShare(module.newShareUri)
      }
    }
  }

  component SyncButton: Rectangle {
    id: btn
    property string label: ""
    property bool available: true
    signal activated()

    width: btnLabel.implicitWidth + Style.space(16)
    height: Style.space(24)
    color: !btn.available ? Util.alpha(Commons.Color.muted, 0.25) : (area.containsMouse ? Qt.lighter(Commons.Color.accent, 1.1) : Commons.Color.accent)

    Text {
      id: btnLabel
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: btn.label
      color: Commons.Color.background
      font.family: Style.font.family
      font.pixelSize: Typography.bodySmall
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      enabled: btn.available
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.activated()
    }
  }
}
