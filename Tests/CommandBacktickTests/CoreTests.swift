import XCTest
@testable import CommandBacktick

final class CoreTests: XCTestCase {
    func testLocalFirstAndReverseNavigation() {
        var state = CycleState(ids: ["A", "C", "B", "D"], focused: "A", local: ["A", "B"])
        XCTAssertEqual(state.ids, ["A", "B", "C", "D"])
        state.step(1); XCTAssertEqual(state.selected, "B")
        state.step(1); XCTAssertEqual(state.selected, "C")
        state.step(-1); XCTAssertEqual(state.selected, "B")
        state.step(-1); state.step(-1); XCTAssertEqual(state.selected, "D")
        let nextHold = CycleState(ids: ["A", "C", "B", "D"], focused: "B", local: ["A", "B"])
        XCTAssertEqual(nextHold.ids, ["B", "A", "C", "D"])
    }
    func testMenuRebuildResolution() {
        XCTAssertEqual(resolvedMenuIndex(original: ["A", "B"], current: ["B", "A"], selected: 1), 0)
        XCTAssertEqual(resolvedMenuIndex(original: ["Same", "Same"], current: ["Same", "Same"], selected: 1), 1)
        XCTAssertNil(resolvedMenuIndex(original: ["Same", "Same"], current: ["Other", "Same", "Same"], selected: 1))
        XCTAssertNil(resolvedMenuIndex(original: ["A"], current: [], selected: 0))
        XCTAssertNil(resolvedMenuIndex(original: [], current: [], selected: 0))
    }
    func testStagePeersBeforeOriginatingAppsOtherWindows() {
        var state = CycleState(ids: ["editor-here", "editor-away", "editor-here-2", "terminal-here"],
                               focused: "editor-here", local: ["editor-here", "editor-here-2", "terminal-here"],
                               stagePeers: ["terminal-here"])
        XCTAssertEqual(state.ids, ["editor-here", "terminal-here", "editor-here-2", "editor-away"])
        state.step(1); XCTAssertEqual(state.selected, "terminal-here")
        state.step(1); XCTAssertEqual(state.selected, "editor-here-2")
        state.step(1); XCTAssertEqual(state.selected, "editor-away")
        state.step(1); XCTAssertEqual(state.selected, "editor-here")
        state.step(-1); XCTAssertEqual(state.selected, "editor-away")

        // Selecting the peer changes the originating app only on the next hold.
        var nextHold = CycleState(ids: ["terminal-here", "terminal-away", "terminal-here-2", "editor-here"],
                                  focused: "terminal-here", local: ["terminal-here", "terminal-here-2", "editor-here"],
                                  stagePeers: ["editor-here"])
        nextHold.step(1); XCTAssertEqual(nextHold.selected, "editor-here")
        nextHold.step(1); XCTAssertEqual(nextHold.selected, "terminal-here-2")
        nextHold.step(1); XCTAssertEqual(nextHold.selected, "terminal-away")
    }
    func testMultipleStagePeersKeepTheirFrontToBackOrder() {
        let state = CycleState(ids: ["away", "peer-front", "focused", "local", "peer-back"],
                               focused: "focused", local: ["focused", "local", "peer-front", "peer-back"],
                               stagePeers: ["peer-front", "peer-back", "focused"])
        XCTAssertEqual(state.ids, ["focused", "peer-front", "peer-back", "local", "away"])
    }
    func testEmptyAndSingleWindow() {
        var empty = CycleState(ids: [], focused: nil, local: [])
        empty.step(1); XCTAssertNil(empty.selected)
        var single = CycleState(ids: ["one"], focused: "gone", local: [])
        single.step(-1); XCTAssertEqual(single.selected, "one")
    }
    func testReleaseRequiresConfirmedHold() {
        var state = ReleaseState()
        XCTAssertFalse(state.update(held: false))
        XCTAssertFalse(state.update(held: true))
        XCTAssertFalse(state.update(held: true))
        XCTAssertTrue(state.update(held: false))
    }
    func testProfileDiscoveryAndPathValidation() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = Data("""
        {"Default":{"name":"Sam","gaia_given_name":"Sam","is_using_default_name":true,"is_using_default_avatar":true,"gaia_picture_file_name":"avatar.png"},
        "Profile 1":{"name":"Work","gaia_given_name":"Sam","is_using_default_name":false,"is_using_default_avatar":true,"gaia_picture_file_name":"avatar.png"},
        "Profile 2":{"name":"Person 2","gaia_given_name":"Sam","is_using_default_name":true,"gaia_picture_file_name":"../secret.png"}}
        """.utf8)
        let profiles = try decoder.decode([String: BrowserProfile].self, from: data)
        let rules = ProfileCatalog.rules(from: profiles, root: URL(fileURLWithPath: "/example"))
        XCTAssertEqual(Set(rules.map(\.name)), ["Sam", "Sam (Work)", "Sam (Person 2)"])
        XCTAssertEqual(ProfileCatalog.match(title: "Sam (Work)", fullTitle: "", rules: rules)?.imageURL?.path,
                       "/example/Profile 1/avatar.png")
        XCTAssertNil(rules.first { $0.name == "Sam (Person 2)" }?.imageURL)
        XCTAssertNil(ProfileCatalog.match(title: "Sam", fullTitle: "Page - Google Chrome - Sam (Work)", rules: rules))
        XCTAssertNil(ProfileCatalog.match(title: "Page - Sam", fullTitle: "", rules: rules))
        XCTAssertNil(ProfileCatalog.match(title: "Sam", fullTitle: "", rules: rules + rules))
        for path in ["", ".", "..", "../outside", "/absolute", "a\\b", "a\0b"] {
            XCTAssertFalse(ProfileCatalog.isLeaf(path))
        }
    }
    func testEnterpriseProfileLabel() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let profile = try decoder.decode(BrowserProfile.self,
            from: Data(#"{"name":"Old","enterprise_label":"Team","gaia_name":"Lee","is_using_default_name":true}"#.utf8))
        XCTAssertEqual(profile.displayName(among: ["one": profile], directory: "one"), "Lee (Team)")
    }
}
