import QtQuick
import QtTest

TestCase {
  id: test
  name: "NetworkStorageModule"
  width: 420
  height: 700
  visible: true
  when: windowShown

  property var module: null
  property var requests: []
  property var opened: []
  property int closes: 0
  property int focusMoves: 0

  readonly property string share: "/run/user/1000/gvfs/smb-share:server=100.85.55.98,share=torrents"

  QtObject {
    id: files
    property bool backendReady: true
    property bool showHidden: false
    function backendRequest(command, args, generation, callback, progress, deadline, options) {
      requests.push({ command: command, verb: args[0], args: args.slice(1), callback: callback, progress: progress, options: options || {} })
      return "request-" + requests.length
    }
    function openDefault(path) { opened.push(path) }
  }

  QtObject {
    id: hostWindow
    property bool shortcutsOpen: false
  }

  QtObject {
    id: context
    property bool bladeOpen: true
    property bool collapsed: false
    property var hostWindow: hostWindow
    function service(id) { return id === "files" ? files : null }
    function focusNext() { focusMoves++ }
    function focusPrevious() { focusMoves-- }
    function closeBlade() { closes++ }
  }

  function init() {
    requests = []; opened = []; closes = 0; focusMoves = 0
    files.showHidden = false
    hostWindow.shortcutsOpen = false
    var component = Qt.createComponent("../../modules/networkstorage/Module.qml")
    compare(component.status, Component.Ready, component.errorString())
    module = component.createObject(test, { context: context, width: 400, height: 680 })
    component.destroy()
    verify(module !== null)
    tryVerify(function() { return pending("shares") && pending("discover") && pending("saved") && pending("active") })
  }

  function cleanup() {
    if (module) module.destroy()
    module = null
    wait(0)
  }

  function pending(verb) {
    for (var i = requests.length - 1; i >= 0; i--) if (requests[i].verb === verb && !requests[i].answered) return requests[i]
    return null
  }

  function answer(verb, response) {
    var request = pending(verb)
    verify(request !== null, "no pending " + verb + " request")
    request.answered = true
    request.callback(response)
    wait(0)
    return request
  }

  function loadNetwork() {
    answer("shares", { ok: true, shares: [{ path: share, name: "smb-share:server=100.85.55.98,share=torrents", uri: "smb://100.85.55.98/torrents" }] })
    answer("discover", { ok: true, servers: [
      { name: "minipi", uri: "smb://100.85.55.98/", source: "tailnet", shares: [
        { name: "torrents", uri: "smb://100.85.55.98/torrents" },
        { name: "thesis", uri: "smb://100.85.55.98/thesis" }
      ] },
      { name: "backup", uri: "smb://10.0.0.9/", source: "network", shares: [{ name: "torrents", uri: "smb://10.0.0.9/torrents" }] }
    ] })
    answer("saved", { ok: true, servers: ["smb://100.85.55.98/torrents", "sftp://box.local/home"] })
    answer("active", { ok: true, active: false })
    while (pending("status")) answer("status", { ok: true, path: share, synced: false })
  }

  function rowsOf(type) {
    return module.displayRows.filter(function(row) { return !type || row.type === type })
  }

  function labels() {
    return module.displayRows.map(function(row) { return row.type === "header" || row.type === "note" ? "[" + row.text + "]" : row.name })
  }

  function focusList() {
    var list = findChild(module, "networkStorageList")
    list.forceActiveFocus()
    wait(0)
    verify(list.activeFocus)
    return list
  }

  function test_every_row_glyph_is_drawn() {
    for (var name of ["folderClosedGlyph", "folderOpenGlyph", "expanderClosedGlyph", "expanderOpenGlyph", "fileGlyph", "shareGlyph", "serverGlyph", "previousGlyph", "ejectGlyph", "forgetGlyph"])
      verify(module[name].length > 0, name + " is empty")
  }

  function test_groups_follow_the_files_network_page_with_tailnet_names() {
    loadNetwork()
    compare(labels().join("|"),
      "[Connected]|torrents on minipi|[Available on Current Network]|minipi|thesis|backup|torrents|[Previous Servers]|home on box.local")
  }

  function test_a_server_whose_shares_are_all_connected_says_so() {
    answer("shares", { ok: true, shares: [{ path: share, name: "x", uri: "smb://100.85.55.98/torrents" }] })
    answer("discover", { ok: true, servers: [{ name: "minipi", uri: "smb://100.85.55.98/", shares: [{ name: "torrents", uri: "smb://100.85.55.98/torrents/" }] }] })
    verify(labels().indexOf("[All shares connected]") > 0, labels().join("|"))
  }

  function test_an_identical_refresh_does_not_rebuild_the_list() {
    loadNetwork()
    var before = module.displayRows
    module.refreshShares()
    answer("shares", { ok: true, shares: module.shares.slice() })
    module.discover()
    answer("discover", { ok: true, servers: JSON.parse(JSON.stringify(module.discovered)) })
    verify(module.displayRows === before, "the model was rebuilt by an unchanged refresh")
  }

  function test_hidden_entries_follow_the_files_setting() {
    loadNetwork()
    module.toggleExpand(share)
    answer("list", { ok: true, entries: [
      { name: "movies", kind: "d", synced: false },
      { name: ".ncdata", kind: "f", synced: false },
      { name: "notes.txt", kind: "f", synced: true }
    ] })
    var names = rowsOf("tree").map(function(row) { return row.name })
    compare(names.join(","), "torrents on minipi,movies,notes.txt")
    files.showHidden = true
    wait(0)
    names = rowsOf("tree").map(function(row) { return row.name })
    compare(names.join(","), "torrents on minipi,movies,.ncdata,notes.txt")
    compare(rowsOf("tree")[3].synced, true)
  }

  function test_keyboard_moves_expands_and_acts_like_the_other_panes() {
    loadNetwork()
    focusList()
    compare(module.currentRow.name, "torrents on minipi")
    keyClick(Qt.Key_L)
    var listing = answer("list", { ok: true, entries: [{ name: "movies", kind: "d", synced: false }, { name: "a.txt", kind: "f", synced: false }] })
    compare(listing.args.join(" "), "-- " + share)
    keyClick(Qt.Key_J)
    compare(module.currentRow.name, "movies")
    keyClick(Qt.Key_J)
    compare(module.currentRow.name, "a.txt")
    keyClick(Qt.Key_Return)
    compare(opened.join(","), share + "/a.txt")
    keyClick(Qt.Key_H)
    compare(module.currentRow.name, "torrents on minipi")
    keyClick(Qt.Key_H)
    verify(!module.expanded[share])
    compare(rowsOf("tree").length, 1)

    keyClick(Qt.Key_J)
    compare(module.currentRow.name, "minipi")
    keyClick(Qt.Key_Left)
    compare(labels().indexOf("thesis"), -1)
    keyClick(Qt.Key_Right)
    keyClick(Qt.Key_Down)
    compare(module.currentRow.name, "thesis")
    keyClick(Qt.Key_Return)
    var connect = answer("connect", { ok: true, uri: "smb://100.85.55.98/thesis", servers: ["smb://100.85.55.98/thesis", "smb://100.85.55.98/torrents", "sftp://box.local/home"] })
    compare(connect.args.join(" "), "-- smb://100.85.55.98/thesis")
    verify(connect.options.untimed)
    answer("shares", { ok: true, shares: module.shares.concat([{ path: share.replace("torrents", "thesis"), name: "x", uri: "smb://100.85.55.98/thesis" }]) })
    compare(labels().indexOf("thesis"), -1)
    verify(labels().indexOf("thesis on minipi") > 0)

    keyClick(Qt.Key_End)
    compare(module.currentRow.name, "home on box.local")
    keyClick(Qt.Key_Delete)
    compare(answer("forget", { ok: true, servers: [] }).args.join(" "), "-- sftp://box.local/home")

    keyClick(Qt.Key_Home)
    compare(module.currentRow.name, "torrents on minipi")
    keyClick(Qt.Key_Tab)
    compare(focusMoves, 1)
    keyClick(Qt.Key_Question, Qt.ShiftModifier)
    verify(hostWindow.shortcutsOpen)
    keyClick(Qt.Key_Escape)
    compare(closes, 1)
  }

  function test_space_asks_before_syncing_a_whole_share_and_reports_progress() {
    loadNetwork()
    focusList()
    keyClick(Qt.Key_Space)
    compare(module.confirmingPath, share)
    verify(pending("sync") === null)
    keyClick(Qt.Key_Space)
    var sync = pending("sync")
    compare(sync.args.join(" "), "-- " + share)
    verify(sync.options.untimed)
    sync.progress({ percent: 42, bytes: "1,024", rate: "2.00MB/s", eta: "0:00:09", path: share })
    compare(module.percent, 42)
    compare(module.transferRate, "2.00MB/s")
    verify(module.busy)
    answer("sync", { ok: true, synced: [share] })
    compare(module.status, "Done")
    verify(!module.busy)
    var status = answer("status", { ok: true, path: share, synced: true })
    compare(status.args.join(" "), "-- " + share)
    compare(rowsOf("tree")[0].synced, true)
  }

  function test_cancel_and_a_failed_pause_leave_a_consistent_state() {
    loadNetwork()
    module.toggleExpand(share)
    answer("list", { ok: true, entries: [{ name: "movies", kind: "d", synced: false }] })
    module.requestToggle(rowsOf("tree")[1])
    verify(module.busy)
    module.pause()
    verify(module.paused)
    answer("pause", { ok: false, error: "nothing is syncing" })
    verify(!module.paused)
    compare(module.status, "Failed: nothing is syncing")
    module.cancel()
    compare(module.status, "Cancelling…")
    answer("cancel", { ok: true, state: "cancelled" })
    answer("sync", { ok: false, cancelled: true, error: "cancelled" })
    compare(module.status, "Cancelled")
    verify(!module.busy)
    verify(!module.cancelling)
  }

  function test_unsync_needs_confirmation_for_a_selection_and_refreshes_rows() {
    loadNetwork()
    module.toggleExpand(share)
    answer("list", { ok: true, entries: [{ name: "a", kind: "d", synced: true }, { name: "b", kind: "f", synced: true }] })
    module.toggleSelected(share + "/a")
    module.toggleSelected(share + "/b")
    compare(module.selectedCount, 2)
    module.unsyncSelected()
    verify(pending("unsync") === null)
    module.unsyncSelected()
    var unsync = answer("unsync", { ok: true, results: [{ path: share + "/a", state: "unsynced" }, { path: share + "/b", state: "unsynced" }] })
    compare(unsync.args.length, 3)
    compare(module.status, "Removed 2 local copies")
    compare(module.selectedCount, 0)
    verify(pending("status") !== null)
  }

  function test_typing_a_server_without_a_share_lists_its_shares_under_previous_servers() {
    loadNetwork()
    var input = findChild(module, "networkStorageAddress")
    module.focusAddress()
    verify(input.activeFocus)
    input.text = "smb://nas.local"
    keyClick(Qt.Key_Return)
    var remember = answer("remember", { ok: true, servers: ["smb://nas.local", "sftp://box.local/home"] })
    compare(remember.args.join(" "), "-- smb://nas.local")
    compare(module.newShareUri, "")
    compare(input.text, "")
    answer("browse", { ok: true, uri: "smb://nas.local", shares: [{ name: "media", uri: "smb://nas.local/media" }] })
    var at = labels().indexOf("nas.local")
    verify(at > 0, labels().join("|"))
    compare(labels()[at + 1], "media")
    compare(module.currentRow.name, "nas.local")
    keyClick(Qt.Key_Escape)
  }

  function test_a_bad_address_is_explained_and_kept() {
    loadNetwork()
    module.newShareUri = "nas.local/media"
    module.addShare(module.newShareUri)
    compare(module.shareActionStatus, "Failed: type an address such as smb://server/share")
    compare(module.newShareUri, "nas.local/media")
    module.newShareUri = "smb://nas.local/media"
    module.addShare(module.newShareUri)
    answer("connect", { ok: false, error: "Failed to mount Windows share: Connection refused" })
    compare(module.shareActionStatus, "Failed: Failed to mount Windows share: Connection refused")
    compare(module.newShareUri, "smb://nas.local/media")
  }

  function test_ejecting_a_share_forgets_its_expanded_folders() {
    loadNetwork()
    module.toggleExpand(share)
    answer("list", { ok: true, entries: [{ name: "movies", kind: "d", synced: false }] })
    module.toggleExpand(share + "/movies")
    answer("list", { ok: true, entries: [] })
    module.disconnectShare(share)
    answer("disconnect", { ok: true, path: share })
    answer("shares", { ok: true, shares: [] })
    compare(Object.keys(module.expanded).length, 0)
    compare(Object.keys(module.listings).length, 0)
    verify(labels().indexOf("[No servers connected]") > 0)
    compare(labels().filter(function(label) { return label === "torrents" }).length, 2, "the ejected share is offered again under its server")
  }

  function test_a_reopened_pane_reattaches_to_a_running_sync_and_reports_how_it_ended() {
    answer("shares", { ok: true, shares: [{ path: share, name: "x", uri: "smb://100.85.55.98/torrents" }] })
    var movie = share + "/Movies/film.mkv"
    answer("active", { ok: true, active: true, path: movie, paths: [movie, share + "/Movies/other.mkv"], paused: true,
      progress: { percent: 61, bytes: "7,000", rate: "", eta: "", path: movie } })
    verify(module.busy)
    verify(module.paused)
    verify(module.reattached)
    compare(module.percent, 61)
    compare(module.activeSyncPaths.length, 2)
    compare(module.status, "Paused (reattached after reload)…")
    module.checkActive()
    answer("active", { ok: true, active: false, last: { ok: true, synced: [movie] } })
    verify(!module.busy)
    compare(module.status, "Done")

    module.reattached = true
    module.busy = true
    module.checkActive()
    answer("active", { ok: true, active: false, last: { ok: false, error: "rsync failed on film.mkv: No space left on device" } })
    compare(module.status, "Failed: rsync failed on film.mkv: No space left on device")
  }

  function test_malformed_backend_answers_leave_the_pane_working() {
    failOnWarning(/.*/)
    answer("shares", { ok: true, shares: "not a list" })
    answer("discover", { ok: true, servers: [null, 7, { uri: 5, shares: "x" }, { name: "ok", uri: "smb://ok/", shares: [null, { name: 3 }] }] })
    answer("saved", { ok: true, servers: [null, 7, "smb://fine/share", {}] })
    answer("active", { ok: true, active: true, path: 9, paths: "x", progress: { percent: "lots", bytes: {}, path: [] } })
    answer("active", null)
    module.refreshShares()
    answer("shares", { ok: true, shares: [{ path: share, uri: "smb://100.85.55.98/torrents" }, null, { path: 3 }] })
    module.toggleExpand(share)
    answer("list", { ok: true, entries: [null, { name: "" }, { name: "a/b", kind: "d" }, { name: 4, kind: "f" }, { name: "fine.txt", kind: "f", synced: "yes" }] })
    module.checkStatus(share)
    answer("status", { ok: true, synced: "maybe" })
    verify(module.displayRows.length > 0)
    var names = module.displayRows.filter(function(row) { return row.type === "tree" }).map(function(row) { return row.name })
    verify(names.indexOf("fine.txt") >= 0, names.join("|"))
    verify(names.indexOf("a/b") < 0, "a name with a slash would make a bogus path")
    focusList()
    keyClick(Qt.Key_J)
    keyClick(Qt.Key_End)
    keyClick(Qt.Key_Return)
  }

  function test_answers_after_the_pane_closes_are_ignored() {
    loadNetwork()
    module.toggleExpand(share)
    var listing = pending("list")
    module.destroy()
    module = null
    wait(0)
    listing.callback({ ok: true, entries: [{ name: "late", kind: "f", synced: false }] })
    wait(0)
    verify(true)
  }
}
