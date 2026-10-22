import QtQuick
import QtTest
import "../../modules/welcome/WelcomePlan.js" as WelcomePlan

TestCase {
  name: "WelcomePlan"

  function test_core_and_offline_help_need_no_installer_or_network() {
    compare(WelcomePlan.CORE.map(function(entry) { return entry.id }), ["files", "notes", "skills", "memory", "hooks", "mcp"])
    for (var topic of WelcomePlan.HELP) verify(topic.name.length > 0 && topic.text.length > 40)
    verify(WelcomePlan.installCommand === undefined)
    verify(WelcomePlan.EXTENSIONS === undefined)
  }

  function test_state_pending_while_unset_or_after_a_version_change() {
    verify(WelcomePlan.pending("", "", "0.1.2"))
    verify(WelcomePlan.pending(undefined, undefined, "0.1.2"))
    verify(WelcomePlan.firstRun(""))
    verify(!WelcomePlan.firstRun("dismissed"))
    verify(!WelcomePlan.pending("dismissed", "0.1.2", "0.1.2"))
    verify(!WelcomePlan.pending("installed", "0.1.2", "0.1.2"))
    verify(WelcomePlan.pending("dismissed", "0.1.2", "0.2.0"))
    verify(WelcomePlan.updated("dismissed", "0.1.2", "0.2.0"))
    verify(WelcomePlan.updated("installed", "0.1.2", "0.2.0"))
    verify(!WelcomePlan.updated("", "", "0.2.0"))
    verify(!WelcomePlan.updated("dismissed", "0.2.0", ""))
    verify(!WelcomePlan.updated("dismissed", "0.2.0", "0.2.0"))
    verify(!WelcomePlan.updated("dismissed", "", "0.2.0"))
    verify(!WelcomePlan.pending("dismissed", "", "0.2.0"))
    verify(WelcomePlan.needsVersionAdoption("dismissed", "", "0.2.0"))
    verify(WelcomePlan.needsVersionAdoption("installed", "", "0.2.0"))
    verify(!WelcomePlan.needsVersionAdoption("", "", "0.2.0"))
    verify(!WelcomePlan.needsVersionAdoption("dismissed", "0.1.2", "0.2.0"))
    verify(!WelcomePlan.needsVersionAdoption("dismissed", "", ""))
    compare(WelcomePlan.welcomeSlot().modules[0].module, "welcome")
    compare(WelcomePlan.welcomeSlot().modules[1].module, "notes")
  }

  function test_repository_links_are_derived_from_the_manifest() {
    var manifest = { repository: "https://github.com/mash2rafi/omablade" }
    compare(WelcomePlan.issuesUrl(manifest), "https://github.com/mash2rafi/omablade/issues/new")
    compare(WelcomePlan.releaseUrl(manifest, "0.2.0"), "https://github.com/mash2rafi/omablade/releases/tag/v0.2.0")
    compare(WelcomePlan.releaseNotesUrl(manifest), "https://github.com/mash2rafi/omablade/blob/main/features/release/release-notes.md")
    compare(WelcomePlan.releaseUrl(manifest, ""), "")
    compare(WelcomePlan.issuesUrl(null), "")
    compare(WelcomePlan.issuesUrl({ repository: "http://github.com/mash2rafi/omablade" }), "")
    compare(WelcomePlan.issuesUrl({ repository: "https://example.org/evil" }), "")
    compare(WelcomePlan.issuesUrl({ repository: "https://github.com/a/b/../../c" }), "")
    compare(WelcomePlan.issuesUrl({ repository: "https://github.com/../.." }), "")
  }

}
