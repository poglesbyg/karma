import XCTest
@testable import karma

// Slow email fetcher for testing isFetching guard
class SlowEmailFetcher: EmailFetcherProtocol {
    func fetch(accessToken: String, since: Double) async throws -> [EmailItem] {
        try await Task.sleep(nanoseconds: 500_000_000)
        return []
    }
}

final class StatusBarControllerTests: XCTestCase {

    // MARK: - Menu bar title computation

    @MainActor
    func testTitleIsKarmaWhenNoDigest() {
        let c = makeController()
        XCTAssertEqual(c.menuBarTitle, "karma")
    }

    @MainActor
    func testTitleShowsCountsWhenDigestHasItems() {
        let c = makeController()
        c.lastDigest = DigestResult(
            emails: [e(), e(), e()],
            messages: [m(), m()],
            emailError: nil,
            messageError: nil,
            fetchedAt: Date()
        )
        XCTAssertEqual(c.menuBarTitle, "3 email 2 msg")
    }

    @MainActor
    func testTitleEmailOnlyWhenNoMessages() {
        let c = makeController()
        c.lastDigest = DigestResult(
            emails: [e()],
            messages: [],
            emailError: nil,
            messageError: nil,
            fetchedAt: Date()
        )
        XCTAssertEqual(c.menuBarTitle, "1 email")
    }

    @MainActor
    func testTitleMsgOnlyWhenNoEmails() {
        let c = makeController()
        c.lastDigest = DigestResult(
            emails: [],
            messages: [m()],
            emailError: nil,
            messageError: nil,
            fetchedAt: Date()
        )
        XCTAssertEqual(c.menuBarTitle, "1 msg")
    }

    @MainActor
    func testTitleIsKarmaWhenDigestIsEmpty() {
        let c = makeController()
        c.lastDigest = DigestResult(
            emails: [], messages: [],
            emailError: nil, messageError: nil,
            fetchedAt: Date()
        )
        XCTAssertEqual(c.menuBarTitle, "karma")
    }

    @MainActor
    func testTitleIsKarmaLoadingOnFirstFetch() {
        let c = makeController()
        c.fetchState = .fetching
        // No lastDigest yet → "karma ..."
        XCTAssertEqual(c.menuBarTitle, "karma ...")
    }

    @MainActor
    func testTitleIsKarmaExclamOnError() {
        let c = makeController()
        c.fetchState = .error("something went wrong")
        XCTAssertEqual(c.menuBarTitle, "karma !")
    }

    @MainActor
    func testTitleShowsItemsDuringBackgroundRefetch() {
        // When we have a lastDigest AND fetchState is .fetching (background refresh),
        // show the stale counts, not "karma ..."
        let c = makeController()
        c.lastDigest = DigestResult(
            emails: [e()], messages: [],
            emailError: nil, messageError: nil,
            fetchedAt: Date()
        )
        c.fetchState = .fetching
        XCTAssertEqual(c.menuBarTitle, "1 email")
    }

    // MARK: - fetchState transitions

    @MainActor
    func testTriggerFetchNoopsWhenNotAuthenticated() {
        let emailMock = MockEmailFetcher()
        var fetchCalled = false
        emailMock.fetch = { _, _ in fetchCalled = true; return [] }
        let c = makeController(emailFetcher: emailMock)
        c.authState = nil
        c.triggerFetch()
        // No fetch should have started
        XCTAssertEqual(c.fetchState, .idle)
        XCTAssertFalse(fetchCalled)
    }

    // MARK: - lastChecked defaults

    @MainActor
    func testLastCheckedDefaultsToTwoHoursAgo() {
        // Clear any stored value
        UserDefaults.standard.removeObject(forKey: "karma.lastChecked")
        let c = makeController()
        let twoHoursAgo = Date().timeIntervalSince1970 - 7200
        XCTAssertEqual(c.lastChecked, twoHoursAgo, accuracy: 5.0)
    }

    @MainActor
    func testLastCheckedPersistsToUserDefaults() {
        let c = makeController()
        let ts = 1_700_000_000.0
        c.lastChecked = ts
        XCTAssertEqual(UserDefaults.standard.double(forKey: "karma.lastChecked"), ts)
        // Clean up
        UserDefaults.standard.removeObject(forKey: "karma.lastChecked")
    }

    // MARK: - Helpers

    @MainActor
    private func makeController(emailFetcher: EmailFetcherProtocol? = nil) -> StatusBarController {
        let email = emailFetcher ?? MockEmailFetcher()
        let msg = MockMessageFetcher()
        // Create without auto-starting scheduler or auto-fetch
        return StatusBarController(emailFetcher: email, messageFetcher: msg)
    }

    private func e() -> EmailItem { EmailItem(from: "x", subject: "s", date: Date()) }
    private func m() -> MessageItem { MessageItem(sender: "+1", text: "hi", date: Date()) }
}

// Upgraded mock with closure support for specific test cases
class MockEmailFetcher: EmailFetcherProtocol {
    var result: [EmailItem] = []
    var error: Error? = nil
    var fetch: ((String, Double) throws -> [EmailItem])?

    func fetch(accessToken: String, since: Double) async throws -> [EmailItem] {
        if let closure = fetch { return try closure(accessToken, since) }
        if let error { throw error }
        return result
    }
}
