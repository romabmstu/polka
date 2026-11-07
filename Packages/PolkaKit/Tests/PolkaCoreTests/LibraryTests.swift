import Foundation
import Testing

@testable import PolkaCore

@Suite struct LibraryTests {
    @Test func nestedGroupsSurviveParentDeletion() {
        var library = Library()
        let parent = library.createGroup(named: "Parent")
        let child = library.createGroup(named: "Child", parentID: parent.id)
        let grandchild = library.createGroup(named: "Grandchild", parentID: child.id)
        library.add([PageReference(url: URL(string: "https://example.com")!)], to: child.id)
        #expect(library.orderedGroups.firstIndex(where: { $0.id == parent.id })! < library.orderedGroups.firstIndex(where: { $0.id == child.id })!)
        library.deleteGroup(parent.id)
        #expect(library.group(child.id)?.parentID == nil)
        #expect(library.group(child.id)?.tabs.count == 1)
        #expect(library.group(grandchild.id)?.parentID == child.id)
    }

    @Test func preventsMovingParentIntoDescendant() {
        var library = Library()
        let parent = library.createGroup(named: "Parent")
        let child = library.createGroup(named: "Child", parentID: parent.id)
        library.moveGroup(parent.id, relativeTo: child.id, after: true)
        #expect(library.group(parent.id)?.parentID == nil)
        #expect(library.group(child.id)?.parentID == parent.id)
    }
    private func page(_ string: String, _ title: String = "") -> PageReference {
        PageReference(url: URL(string: string)!, title: title)
    }

    @Test func newLibraryHasInbox() {
        let library = Library()
        #expect(library.groups.count == 1)
        #expect(library.defaultGroupID == library.groups[0].id)
    }

    @Test func addSkipsDuplicatesAndUnsafeSchemes() {
        var library = Library()
        let inbox = library.groups[0].id
        let result = library.add(
            [
                page("https://example.com/a", "A"),
                page("https://EXAMPLE.com/a/"),
                page("javascript:alert(1)"),
                page("https://example.com/b", "B"),
            ], to: inbox)

        #expect(result.added.map(\.title) == ["A", "B"])
        #expect(result.duplicates.count == 1)
        #expect(library.group(inbox)?.tabs.count == 2)
    }

    @Test func addInsertsAtPosition() {
        var library = Library()
        let inbox = library.groups[0].id
        library.add([page("https://a.com"), page("https://c.com")], to: inbox)
        library.add([page("https://b.com")], to: inbox, at: 1)
        #expect(library.group(inbox)?.tabs.map(\.site) == ["a.com", "b.com", "c.com"])
    }

    @Test func pinnedGroupsComeFirst() {
        var library = Library(groupOrder: .name)
        let zeta = library.createGroup(named: "Zeta")
        library.createGroup(named: "Alpha")
        library.updateGroup(zeta.id) { $0.isPinned = true }
        #expect(library.orderedGroups.first?.name == "Zeta")
    }

    @Test func movingTabWithinSortedGroupSwitchesToManual() {
        var library = Library()
        let inbox = library.groups[0].id
        library.add([page("https://b.com", "B"), page("https://a.com", "A"), page("https://c.com", "C")], to: inbox)
        library.updateGroup(inbox) { $0.sortOrder = .title }
        let c = library.group(inbox)!.tabs.first { $0.title == "C" }!
        let a = library.group(inbox)!.tabs.first { $0.title == "A" }!

        library.moveTab(c.id, to: inbox, before: a.id)

        #expect(library.group(inbox)?.sortOrder == .manual)
        #expect(library.group(inbox)?.tabs.map(\.title) == ["C", "A", "B"])
    }

    @Test func movingTabIntoGroupWithSamePageKeepsOriginal() {
        var library = Library()
        let inbox = library.groups[0].id
        let work = library.createGroup(named: "Work").id
        library.add([page("https://same.com")], to: inbox)
        library.add([page("https://same.com")], to: work)
        let tab = library.group(inbox)!.tabs[0]

        library.moveTab(tab.id, to: work)

        #expect(library.group(inbox)?.tabs.count == 1)
        #expect(library.group(work)?.tabs.count == 1)
    }

    @Test func deletingLastGroupRecreatesInbox() {
        var library = Library()
        library.deleteGroup(library.groups[0].id)
        #expect(library.groups.count == 1)
    }

    @Test func searchMatchesAllTerms() {
        var library = Library()
        let inbox = library.groups[0].id
        library.add([page("https://swift.org/blog", "Swift blog"), page("https://swift.org/docs", "Docs")], to: inbox)
        let hits = library.search("swift blog")
        #expect(hits.count == 1)
        #expect(hits.first?.tabs.map(\.title) == ["Swift blog"])
    }

    @Test func repairPreservesDuplicateEntriesFromEditedFiles() {
        var library = Library()
        let tab = SavedTab(title: "x", url: URL(string: "https://x.com")!)
        library.groups[0].tabs = [tab, SavedTab(title: "x again", url: URL(string: "https://X.com/")!)]
        library.repair()
        #expect(library.groups[0].tabs.count == 2)
    }
}
