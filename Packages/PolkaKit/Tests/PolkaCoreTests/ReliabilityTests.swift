import Foundation
import Testing

@testable import PolkaCore

@Suite struct ClipboardBudgetTests {
    private func picture(bytes: Int, seed: UInt8 = 1) -> ClipboardImage {
        var data = Data(count: bytes)
        data[0] = seed
        return ClipboardImage(png: data, pixelWidth: 10, pixelHeight: 10)
    }

    @Test func picturePreparedLaterStaysBelowNewerCopies() {
        var history = ClipboardHistory()
        let copiedAt = Date(timeIntervalSince1970: 1_000)
        history.record("copied after the picture", at: copiedAt.addingTimeInterval(1))
        history.record(picture(bytes: 10), at: copiedAt)
        #expect(history.entries.map(\.kind) == [.text, .image])
    }

    @Test func keepsAllPicturesUnderTheMemoryBudget() {
        var history = ClipboardHistory()
        let big = ClipboardHistory.maximumImageBytes
        for seed in 1...4 {
            history.record(picture(bytes: big, seed: UInt8(seed)), at: Date(timeIntervalSince1970: Double(seed)))
        }
        #expect(history.imageBytes <= ClipboardHistory.maximumTotalImageBytes)
        #expect(history.entries.count == ClipboardHistory.maximumTotalImageBytes / big)
        // The newest pictures are the ones kept.
        #expect(history.entries.first?.image?.png.first == 4)
    }

    @Test func limitsPinnedPicturesButAlwaysAllowsUnpinning() throws {
        var history = ClipboardHistory()
        let big = ClipboardHistory.maximumImageBytes
        history.record(picture(bytes: big, seed: 1), at: Date(timeIntervalSince1970: 1))
        history.record(picture(bytes: big, seed: 2), at: Date(timeIntervalSince1970: 2))
        let newest = try #require(history.entries.first)
        let older = try #require(history.entries.last)
        let pinnedNewest = history.togglePin(newest.id)
        #expect(pinnedNewest)
        // A second 15 MB picture would take pins past their share.
        #expect(!history.canPin(older.id))
        let pinnedOlder = history.togglePin(older.id)
        #expect(!pinnedOlder)
        #expect(history.canPin(newest.id))
        let unpinned = history.togglePin(newest.id)
        #expect(unpinned)
        #expect(history.entries.allSatisfy { !$0.isPinned })
    }

    @Test func samePictureWithAnotherPreviewIsNotDuplicated() {
        var history = ClipboardHistory()
        let png = Data([1, 2, 3])
        history.record(ClipboardImage(png: png, pixelWidth: 2, pixelHeight: 2, preview: Data([9])))
        history.record(ClipboardImage(png: png, pixelWidth: 2, pixelHeight: 2))
        #expect(history.entries.count == 1)
    }

    @Test func textStillRecordedWhilePicturesFillTheBudget() {
        var history = ClipboardHistory()
        for seed in 1...6 {
            history.record(picture(bytes: ClipboardHistory.maximumImageBytes, seed: UInt8(seed)))
        }
        let recorded = history.record("note")
        #expect(recorded)
        #expect(history.entries.first?.text == "note")
    }
}

@Suite struct SectionLayoutTests {
    private let all = ["overview", "tabs", "vpn", "translator", "shelf"]
    private let original = ["overview", "tabs", "vpn", "shelf"]

    @Test func freshInstallShowsEverything() {
        #expect(SectionLayout.restore(saved: nil, known: nil, all: all, original: original) == all)
    }

    @Test func keepsUserOrderAndHiddenSections() {
        let saved = ["vpn", "overview"]
        let known = all
        #expect(SectionLayout.restore(saved: saved, known: known, all: all, original: original) == ["vpn", "overview"])
    }

    @Test func addsNewSectionsOnce() {
        let saved = ["overview", "tabs"]
        #expect(
            SectionLayout.restore(saved: saved, known: original, all: all, original: original)
                == ["overview", "tabs", "translator"])
        // An old layout saved before "known" was recorded counts as the original set.
        #expect(
            SectionLayout.restore(saved: saved, known: nil, all: all, original: original)
                == ["overview", "tabs", "translator"])
    }

    @Test func ignoresSectionsFromANewerVersion() {
        let saved = ["overview", "weather", "tabs", "tabs"]
        #expect(SectionLayout.restore(saved: saved, known: all, all: all, original: original) == ["overview", "tabs"])
    }

    @Test func neverLeavesThePanelEmpty() {
        #expect(SectionLayout.restore(saved: ["weather"], known: all, all: all, original: original) == all)
        #expect(SectionLayout.restore(saved: [], known: all, all: all, original: original) == all)
    }

    @Test func rememberedSectionsSurviveAnOlderVersion() {
        let newer = ["overview", "tabs", "vpn", "translator", "shelf", "weather"]
        let knownAfterOlder = SectionLayout.known(before: newer, all: all, original: original)
        #expect(knownAfterOlder.contains("weather"))
        #expect(Set(SectionLayout.known(before: nil, all: all, original: original)) == Set(all))
    }
}

@Suite struct GroupNameSearchTests {
    private let groups = ["Работа", "Read later", "Café"]

    @Test func emptyQueryListsAllWithoutNewGroup() {
        let found = GroupNameSearch.results(in: groups, name: { $0 }, query: "   ")
        #expect(found.matches == groups)
        #expect(found.newGroupName == nil)
    }

    @Test func findsByPartAndOffersNewName() {
        let found = GroupNameSearch.results(in: groups, name: { $0 }, query: " rea ")
        #expect(found.matches == ["Read later"])
        #expect(found.newGroupName == "rea")
    }

    @Test func exactNameIgnoringCaseAndAccentsIsNotOfferedAgain() {
        #expect(GroupNameSearch.results(in: groups, name: { $0 }, query: "работа").newGroupName == nil)
        #expect(GroupNameSearch.results(in: groups, name: { $0 }, query: "cafe").newGroupName == nil)
    }

    @Test func newNameIsShortened() {
        let long = String(repeating: "a", count: 200)
        let found = GroupNameSearch.results(in: [String](), name: { $0 }, query: long)
        #expect(found.newGroupName?.count == GroupNameSearch.maximumNameLength)
    }
}

@Suite struct UpdatePolicyTests {
    private let system = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)

    private func manifest(build: Int, minimum: String = "14.0") throws -> UpdateManifest {
        let url = try #require(URL(string: "https://github.com/romabmstu/polka/releases/download/nightly/Polka.zip"))
        return UpdateManifest(
            version: "0.1.0", build: build, channel: .beta, url: url,
            size: 1, sha256: "", signature: "", minimumSystemVersion: minimum, notes: "",
            publishedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func offersOnlyNewerBuildsThatRun() throws {
        let newer = try manifest(build: 60)
        let same = try manifest(build: 55)
        let tooNew = try manifest(build: 60, minimum: "26.0")
        #expect(UpdatePolicy.shouldOffer(newer, currentBuild: 55, skippedBuild: nil, automatic: true, system: system))
        #expect(!UpdatePolicy.shouldOffer(same, currentBuild: 55, skippedBuild: nil, automatic: true, system: system))
        #expect(!UpdatePolicy.shouldOffer(tooNew, currentBuild: 55, skippedBuild: nil, automatic: false, system: system))
    }

    @Test func automaticChecksSkipARolledBackBuild() throws {
        let crashed = try manifest(build: 60)
        let later = try manifest(build: 61)
        #expect(!UpdatePolicy.shouldOffer(crashed, currentBuild: 55, skippedBuild: 60, automatic: true, system: system))
        // Checking by hand still shows it, and a later build is offered again.
        #expect(UpdatePolicy.shouldOffer(crashed, currentBuild: 55, skippedBuild: 60, automatic: false, system: system))
        #expect(UpdatePolicy.shouldOffer(later, currentBuild: 55, skippedBuild: 60, automatic: true, system: system))
    }
}

@Suite struct DisplayGeometryTests {
    /// A 14-inch MacBook Pro at its default resolution: 1512×982 points with
    /// a 32-point camera housing about 185 points wide.
    private func macBook(id: UInt32 = 1, origin: CGPoint = .zero, safeAreaTop: CGFloat = 32, sideAreas: Bool = true) -> DisplayInfo {
        let frame = CGRect(origin: origin, size: CGSize(width: 1512, height: 982))
        let left = CGRect(x: frame.minX, y: frame.maxY - 32, width: 663.5, height: 32)
        let right = CGRect(x: frame.maxX - 663.5, y: frame.maxY - 32, width: 663.5, height: 32)
        return DisplayInfo(
            id: id, frame: frame, isBuiltIn: true, safeAreaTop: safeAreaTop,
            topLeftArea: sideAreas ? left : nil, topRightArea: sideAreas ? right : nil)
    }

    private func monitor(id: UInt32 = 2, origin: CGPoint) -> DisplayInfo {
        DisplayInfo(
            id: id, frame: CGRect(origin: origin, size: CGSize(width: 2560, height: 1440)), isBuiltIn: false,
            safeAreaTop: 0, topLeftArea: nil, topRightArea: nil)
    }

    @Test func findsTheNotch() {
        #expect(macBook().notch == CGSize(width: 185, height: 32))
        #expect(monitor(origin: .zero).notch == nil)
    }

    @Test func notchSurvivesAMomentaryZeroSafeArea() {
        // Right after a monitor is plugged in the safe area can read as zero
        // while the areas beside the camera are already there.
        #expect(macBook(safeAreaTop: 0).notch == CGSize(width: 185, height: 32))
    }

    @Test func resolutionBelowTheCameraHasNoNotch() {
        #expect(macBook(safeAreaTop: 0, sideAreas: false).notch == nil)
    }

    @Test func builtInChoicePrefersTheNotchWhateverIsMain() {
        let laptop = macBook()
        let external = monitor(origin: CGPoint(x: 1512, y: 0))
        #expect(DisplayGeometry.builtIn(in: [laptop, external])?.id == laptop.id)
        #expect(DisplayGeometry.builtIn(in: [external, laptop])?.id == laptop.id)
        // Notch hidden by the resolution: still the built-in display.
        let hidden = macBook(safeAreaTop: 0, sideAreas: false)
        #expect(DisplayGeometry.builtIn(in: [external, hidden])?.id == hidden.id)
        #expect(DisplayGeometry.builtIn(in: [external])?.id == external.id)
    }

    @Test func pointerAtTheTopEdgeBelongsToTheLowerDisplay() {
        // A monitor arranged above the MacBook: their edges meet at y = 982.
        let laptop = macBook()
        let above = monitor(origin: CGPoint(x: -524, y: 982))
        let displays = [laptop, above]
        #expect(DisplayGeometry.display(at: CGPoint(x: 756, y: 982), in: displays)?.id == laptop.id)
        #expect(DisplayGeometry.display(at: CGPoint(x: 756, y: 983), in: displays)?.id == above.id)
        #expect(DisplayGeometry.display(at: CGPoint(x: 756, y: 500), in: displays)?.id == laptop.id)
        #expect(DisplayGeometry.display(at: CGPoint(x: 5000, y: 500), in: displays) == nil)
    }
}
