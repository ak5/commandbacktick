import XCTest
@testable import CommandBacktick

final class ActivationTests: XCTestCase {
    @MainActor func testSelectionRequestsOwnerFocusEvenWhenAlreadyActive() async throws {
        var requests = 0
        var checks = 0
        try await confirmAppActivation(targetPID: 2, frontmostPID: { 2 },
            request: { requests += 1 }, pause: { checks += 1 })
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(checks, 2)
    }

    @MainActor func testFocusHandoffWaitsForDesktopTransition() async throws {
        var front: Int32 = 1
        var requests = 0
        try await confirmAppActivation(targetPID: 2, frontmostPID: { front },
            request: { requests += 1 }, pause: { if requests == 3 { front = 2 } })
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(front, 2)
    }

    @MainActor func testForegroundAppWithoutFocusedWindowDoesNotConfirm() async throws {
        var requests = 0
        try await confirmAppActivation(targetPID: 2, frontmostPID: { 2 },
            focusReady: { requests >= 3 }, request: { requests += 1 }, pause: {})
        XCTAssertEqual(requests, 3)
    }

    @MainActor func testTransientFocusMustSettle() async throws {
        var requests = 0
        var checks = 0
        try await confirmAppActivation(targetPID: 2, frontmostPID: { 2 },
            focusReady: { checks != 2 }, request: { requests += 1 }, pause: { checks += 1 })
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(checks, 4)
    }

    @MainActor func testActiveAppWithWrongWindowCannotConfirm() async {
        var requests = 0
        do {
            try await confirmAppActivation(targetPID: 2, frontmostPID: { 2 },
                focusReady: { false }, request: { requests += 1 }, pause: {})
            XCTFail("App activation alone must not confirm selected-window focus")
        } catch is EngineError { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(requests, 8)
    }

    func testDesktopManagerIsTransientButUserAppsAreNot() {
        XCTAssertNil(focusHandoffPID(pid: 3, bundleID: "com.apple.WindowManager"))
        XCTAssertEqual(focusHandoffPID(pid: 3, bundleID: "example.editor"), 3)
        XCTAssertEqual(focusHandoffPID(pid: 3, bundleID: nil), 3)
    }

    @MainActor func testDesktopManagerTransitionDoesNotCancelFocusRestoration() async throws {
        var checks = 0
        var requests = 0
        try await confirmAppActivation(targetPID: 2,
            frontmostPID: {
                focusHandoffPID(pid: checks == 1 || checks == 2 ? 3 : 2,
                    bundleID: checks == 1 || checks == 2 ? "com.apple.WindowManager" : "example.browser")
            }, request: { requests += 1 }, pause: { checks += 1 })
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(checks, 4)
    }

    @MainActor func testAnotherAppTakingFocusCancelsFurtherRequests() async {
        var front: Int32 = 1
        var requests = 0
        do {
            try await confirmAppActivation(targetPID: 2, frontmostPID: { front },
                request: { requests += 1 }, pause: { front = 3 })
            XCTFail("A new app taking focus should cancel the old handoff")
        } catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(front, 3)
    }

    @MainActor func testCancellationDoesNotContinueActivating() async {
        var requests = 0
        do {
            try await confirmAppActivation(targetPID: 2, frontmostPID: { 1 },
                request: { requests += 1 }, pause: { throw CancellationError() })
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(requests, 1)
    }

    @MainActor func testAlreadyCancelledTaskNeverRequestsFocus() async {
        var requests = 0
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await confirmAppActivation(targetPID: 2, frontmostPID: { 1 },
                    request: { requests += 1 }, pause: {})
                XCTFail("Expected cancellation before requesting focus")
            } catch is CancellationError { }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        await task.value
        XCTAssertEqual(requests, 0)
    }

    @MainActor func testFocusFailureIsBoundedAndReported() async {
        var requests = 0
        do {
            try await confirmAppActivation(targetPID: 2, frontmostPID: { 1 },
                request: { requests += 1 }, pause: {})
            XCTFail("Expected an activation error")
        } catch is EngineError { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(requests, 8)
    }
}
