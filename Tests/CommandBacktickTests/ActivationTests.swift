import XCTest
@testable import CommandBacktick

final class ActivationTests: XCTestCase {
    @MainActor func testSelectionRequestsOwnerFocusEvenWhenAlreadyActive() async throws {
        var requests = 0
        var checks = 0
        try await confirmAppActivation(targetPID: 2, frontmostPID: { 2 },
            request: { requests += 1 }, pause: { checks += 1 })
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(checks, 1)
    }

    @MainActor func testFocusHandoffWaitsForDesktopTransition() async throws {
        var front: Int32 = 1
        var requests = 0
        try await confirmAppActivation(targetPID: 2, frontmostPID: { front },
            request: { requests += 1 }, pause: { if requests == 3 { front = 2 } })
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(front, 2)
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
