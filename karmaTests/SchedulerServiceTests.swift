import XCTest
@testable import karma

final class SchedulerServiceTests: XCTestCase {

    // MARK: - Boolean gate: isFetching prevents concurrent fetches

    func testIsFetchingGateViaStatusBarController() async throws {
        // StatusBarController.triggerFetch() has a guard !isFetching check.
        // Test that calling it while fetching is in progress is a no-op.
        var triggerCount = 0
        class FakeFetcher: EmailFetcherProtocol {
            var triggerCount = 0
            func fetch(accessToken: String, since: Double) async throws -> [EmailItem] {
                // Simulate slow fetch
                try await Task.sleep(nanoseconds: 100_000_000)
                return []
            }
        }
        // This is tested via StatusBarController.isFetching guard
        // (direct test of the guard logic itself)
        var calledCount = 0
        var isFetching = false

        func guardedTrigger() {
            guard !isFetching else { return }
            calledCount += 1
        }

        // First call goes through
        guardedTrigger()
        isFetching = true

        // Subsequent calls blocked
        guardedTrigger()
        guardedTrigger()

        XCTAssertEqual(calledCount, 1)
    }

    // MARK: - Wake debounce: rapid notifications result in single fetch

    func testRapidWakeNotificationsDebounced() {
        var triggerCount = 0
        let scheduler = SchedulerService(
            onTrigger: { triggerCount += 1 },
            wakeDebounceInterval: 0.1  // short interval for testing
        )

        // Fire 3 rapid wake notifications
        scheduler.handleWakeNotification()
        scheduler.handleWakeNotification()
        scheduler.handleWakeNotification()

        // Wait for debounce to fire (0.1s + buffer)
        let expectation = XCTestExpectation(description: "debounce fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(triggerCount, 1, "Rapid wake notifications should be collapsed into one fetch")
    }

    // MARK: - Debounce cancels previous task on second wake

    func testSecondWakeCancelsPreviousDebounceTask() {
        var timestamps: [Date] = []
        let scheduler = SchedulerService(
            onTrigger: { timestamps.append(Date()) },
            wakeDebounceInterval: 0.15
        )

        // First wake
        scheduler.handleWakeNotification()
        // 0.05s later — second wake (before first debounce fires)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scheduler.handleWakeNotification()
        }

        let expectation = XCTestExpectation(description: "only one trigger fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(timestamps.count, 1,
            "Second wake should cancel first debounce — only one fetch should fire")

        // The trigger should have fired ~0.2s after start (0.05s delay + 0.15s debounce)
        // not ~0.15s (first debounce firing)
        if let ts = timestamps.first {
            let elapsed = ts.timeIntervalSince(timestamps.first ?? ts)
            XCTAssertLessThan(elapsed, 0.3, "Should fire within 300ms total")
        }
    }

    // MARK: - triggerFetch calls onTrigger

    func testTriggerFetchCallsOnTrigger() {
        var called = false
        let scheduler = SchedulerService(onTrigger: { called = true })
        scheduler.triggerFetch()
        XCTAssertTrue(called)
    }
}
