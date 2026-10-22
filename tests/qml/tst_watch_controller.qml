import QtQuick
import QtTest
import "../../controllers"

TestCase {
  name: "WatchControllerRegression"

  property var requests: []
  property var callbacks: []
  property int searchRestartCount: 0

  ListModel { id: rows }

  Item {
    id: fakeService
    property bool stateReady: false
    property bool open: false
    property string rootPath: "/tmp"
    property bool showHidden: false
    property string searchQuery: ""
    property int directoryBatchLimit: 8
    property var treeModel: rows
    property var gitRepoDirectories: ({})
    property bool trashMode: false
    property bool recentMode: false
    property bool drivesMode: false
    property var backendLimits: ({ watch_paths: 512 })
    property int treeRefreshCount: 0

    function parentDirectory(path) { return "/tmp" }
    function indexOfTreePath(path) { return -1 }
    function scheduleGitMetadataRefresh(reason, repoRoot) {}
    function refreshTree() { treeRefreshCount++ }
    function restartSearch() { searchRestartCount++ }
    function flushFilesystemEvents() { controller.flushFilesystemEvents() }
    property var subscriptions: []
    function backendSubscribe(paths, generation, eventCallback, readyCallback, closedCallback) {
      subscriptions.push({ paths: paths, ready: readyCallback, closed: closedCallback })
      return "watch-" + subscriptions.length
    }
    function cancelBackendRequest() {}
    function backendRequest(name, arguments, generation, callback) {
      requests.push({ name: name, arguments: arguments, generation: generation })
      callbacks.push(callback)
      return name + "-request"
    }
  }

  WatchController {
    id: controller
    service: fakeService
  }

  function init() {
    requests = []
    callbacks = []
    searchRestartCount = 0
    fakeService.searchQuery = ""
    fakeService.treeRefreshCount = 0
    controller.pendingWatchDirectories = []
    controller.watchRefreshQueue = []
    controller.activeWatchRefreshPaths = []
    controller.indexDirty = false
    fakeService.subscriptions = []
  }

  function startWatching() {
    fakeService.stateReady = true
    fakeService.open = true
    controller.startWatcher()
    compare(fakeService.subscriptions.length, 1)
    return fakeService.subscriptions[0]
  }

  function stopWatching() {
    fakeService.open = false
    fakeService.stateReady = false
    controller.watcherGeneration++
  }

  function test_a_root_that_vanished_before_its_watch_relists_the_tree() {
    var watch = startWatching()
    watch.ready({ ok: true, skipped: [{ path: "/tmp", error: "No such file or directory" }] })
    tryCompare(fakeService, "treeRefreshCount", 1)
    stopWatching()
  }

  function test_an_unwatchable_subfolder_does_not_relist_the_tree() {
    var watch = startWatching()
    watch.ready({ ok: true, skipped: [{ path: "/tmp/sub", error: "Permission denied" }] })
    wait(20)
    compare(fakeService.treeRefreshCount, 0)
    stopWatching()
  }

  function test_a_failed_watcher_relists_the_tree() {
    var watch = startWatching()
    watch.closed({ ok: false, error: "could not watch any of the 1 requested paths" })
    tryCompare(fakeService, "treeRefreshCount", 1)
    stopWatching()
  }

  function completeInvalidation() {
    compare(callbacks.length, 1)
    callbacks.shift()({ ok: true })
  }

  function test_dirty_index_is_invalidated_without_an_active_search() {
    controller.indexDirty = true
    controller.flushFilesystemEvents()

    compare(requests.length, 1)
    compare(requests[0].name, "index-invalidate")
    verify(!controller.indexDirty)
    completeInvalidation()
    compare(searchRestartCount, 0)
  }

  function test_active_search_restarts_after_invalidation() {
    fakeService.searchQuery = "needle"
    controller.indexDirty = true
    controller.flushFilesystemEvents()

    completeInvalidation()
    compare(searchRestartCount, 1)
  }

  function test_cleared_search_does_not_restart_after_invalidation() {
    fakeService.searchQuery = "needle"
    controller.indexDirty = true
    controller.flushFilesystemEvents()
    fakeService.searchQuery = ""

    completeInvalidation()
    compare(searchRestartCount, 0)
  }

  function test_overflow_schedules_index_invalidation() {
    controller.receiveFilesystemEvent({ overflow: true })

    compare(fakeService.treeRefreshCount, 1)
    verify(controller.indexDirty)
    tryCompare(requests, "length", 1, 500)
    compare(requests[0].name, "index-invalidate")
    verify(!controller.indexDirty)
  }
}
