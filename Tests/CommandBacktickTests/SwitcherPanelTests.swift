import AppKit
import XCTest
@testable import CommandBacktick

final class SwitcherPanelTests: XCTestCase {
    func testOverlayRecreatesItsWindowWithoutChangingSelection() throws {
        _ = NSApplication.shared
        let owner = NSRunningApplication.current
        let snapshot = WindowSnapshot(app: owner, windows: [
            WindowChoice(id: "one", owner: owner, title: "Example one", fullTitle: "", local: true,
                         focused: true, target: .menu(0)),
            WindowChoice(id: "two", owner: owner, title: "Example two", fullTitle: "", local: false,
                         focused: false, target: .menu(1))
        ])
        var state = CycleState(ids: ["one", "two"], focused: "one", local: ["one"])
        state.step(1)
        let overlay = SwitcherPanel()
        defer { overlay.hide() }
        func window() throws -> NSWindow {
            try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "CommandBacktickSwitcher" })
        }

        overlay.show(snapshot: snapshot, state: state)
        let first = try window()
        XCTAssertTrue(first.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(first.collectionBehavior.contains(.canJoinAllApplications))
        overlay.show(snapshot: snapshot, state: state)
        XCTAssertTrue(try window() === first)

        overlay.redisplay(snapshot: snapshot, state: state)
        XCTAssertFalse(try window() === first)
        XCTAssertFalse(first.isVisible)
        XCTAssertEqual(state.selected, "two")
        XCTAssertEqual(NSApp.windows.filter { $0.isVisible && $0.identifier?.rawValue == "CommandBacktickSwitcher" }.count, 1)

        overlay.hide()
        XCTAssertFalse(NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue == "CommandBacktickSwitcher" })
        overlay.show(snapshot: snapshot, state: state)
        XCTAssertFalse(try window() === first)
    }
}
