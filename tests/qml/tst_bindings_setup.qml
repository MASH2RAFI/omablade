import QtQuick
import QtTest
import "../../controllers"

TestCase {
  name: "BindingsSetup"

  property var requests: []

  QtObject {
    id: fakeService
    property var bladeHost: ({ nativeApp: false })
    property bool backendReady: false
    property bool stateReady: false
    property string bindingsSetup: ""
    property string home: "/home/fixture"
    property string operationNotice: ""
    property string operationError: ""
    function setBindingsSetup(value) { bindingsSetup = value; return value }
    function backendRequest(command, args, generation, callback) {
      requests.push({ command: command, args: args, callback: callback })
      return "request-" + requests.length
    }
  }

  Component { id: controllerComponent; BindingsSetupController { service: fakeService } }

  function init() {
    requests = []
    fakeService.bladeHost = { nativeApp: false }
    fakeService.backendReady = false
    fakeService.stateReady = false
    fakeService.bindingsSetup = ""
    fakeService.operationNotice = ""
    fakeService.operationError = ""
  }

  function start() {
    var controller = createTemporaryObject(controllerComponent, this)
    fakeService.backendReady = true
    fakeService.stateReady = true
    tryVerify(function() { return requests.length === 1 })
    compare(requests[0].command, "read-text")
    compare(requests[0].args[1], "/home/fixture/.config/hypr/bindings.lua")
    return controller
  }

  function answer(index, response) {
    requests[index].callback(response)
    wait(0)
  }

  function test_a_plain_bindings_file_gets_the_omablade_role_once() {
    var controller = start()
    answer(0, { ok: true, text: "o.bind(\"SUPER + RETURN\", \"Terminal\", {})\n" })
    compare(requests.length, 2)
    compare(requests[1].command, "roles-set")
    compare(requests[1].args.join(" "), "--role bindings --on")
    answer(1, { roles: { bindings: { status: "enabled", error: "" } } })
    compare(fakeService.bindingsSetup, "added")
    verify(fakeService.operationNotice.indexOf("Super+B") >= 0)
    fakeService.backendReady = false
    fakeService.backendReady = true
    wait(20)
    compare(requests.length, 2, "it never runs again once decided")
  }

  function test_existing_omablade_or_fileblade_bindings_are_kept() {
    start()
    answer(0, { ok: true, text: "-- FileBlade sidebar bindings\nomarchy-shell mash2rafi.omablade.control toggleBladeFocus left\n" })
    compare(requests.length, 1)
    compare(fakeService.bindingsSetup, "kept")
    compare(fakeService.operationNotice, "")
  }

  function test_a_missing_bindings_file_is_skipped_quietly() {
    start()
    answer(0, { ok: false, missing: true, error: "No such file or directory (os error 2)" })
    compare(fakeService.bindingsSetup, "skipped")
    compare(fakeService.operationError, "")
  }

  function test_a_refused_role_is_reported_and_not_retried() {
    start()
    answer(0, { ok: true, text: "" })
    answer(1, { roles: { bindings: { status: "refused", error: "no stable launcher" } } })
    compare(fakeService.bindingsSetup, "failed")
    verify(fakeService.operationError.indexOf("no stable launcher") >= 0)
  }

  function test_native_installs_and_decided_homes_are_left_alone() {
    fakeService.bladeHost = { nativeApp: true }
    createTemporaryObject(controllerComponent, this)
    fakeService.backendReady = true
    fakeService.stateReady = true
    wait(20)
    compare(requests.length, 0)
    fakeService.bladeHost = { nativeApp: false }
    fakeService.bindingsSetup = "kept"
    wait(20)
    compare(requests.length, 0)
  }
}
