import QtQuick
import QtTest
import "../../lib/KeyBindings.js" as KeyBindings

TestCase {
  name: "KeyBindingsHostileDocuments"

  function test_any_document_compiles_to_a_working_plan_or_a_clean_refusal() {
    var long = []
    for (var i = 0; i < 1000; i++) long.push("Ctrl+A")
    var documents = [
      null, undefined, 7, "text", [], true,
      { bindings: null }, { bindings: 7 }, { bindings: [] }, { bindings: "j" },
      { bindings: { next: "j" } }, { bindings: { next: [7, null, {}, []] } },
      { bindings: { next: long } }, { bindings: { next: ["Hyper+Ctrl+Ctrl+X", "Ctrl+", "+", "", "F99", "\u0000", "x".repeat(100)] } },
      { bindings: { "__proto__": ["j"], constructor: ["k"], next: ["j"], previous: ["j"] } },
      { bindings: { next: ["g g g g g g g g g g g g g g g g g g g g"] } }
    ]
    var refused = 0
    for (var doc of documents) {
      var plan
      try {
        plan = KeyBindings.compile(doc)
      } catch (error) {
        verify(error instanceof Error && String(error.message).length > 0)
        refused++
        continue
      }
      verify(plan && Array.isArray(plan.entries), JSON.stringify(doc))
      verify(plan.entries.length > 0)
      verify(KeyBindings.label(plan, "next").length > 0)
      verify(Object.prototype.toString.call({}) === "[object Object]")
    }
    verify(refused > 0 && refused < documents.length)
  }
}
