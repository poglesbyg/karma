import XCTest
@testable import karma

// MARK: - Tests

final class DigestBuilderTests: XCTestCase {
    var emailFetcher: MockEmailFetcher!
    var messageFetcher: MockMessageFetcher!
    var builder: DigestBuilder!

    override func setUp() {
        emailFetcher = MockEmailFetcher()
        messageFetcher = MockMessageFetcher()
        builder = DigestBuilder(emailFetcher: emailFetcher, messageFetcher: messageFetcher)
    }

    // MARK: Scenario 1: both succeed

    func testBothSucceed() async {
        emailFetcher.result = [EmailItem(from: "alice", subject: "Hey", date: Date())]
        messageFetcher.result = [MessageItem(sender: "+1234", text: "hi", date: Date())]

        let result = await builder.build(accessToken: "tok", since: 0)

        XCTAssertEqual(result.emails.count, 1)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertNil(result.emailError)
        XCTAssertNil(result.messageError)
    }

    // MARK: Scenario 2: email fails, messages succeed

    func testEmailFailsMessageSucceeds() async {
        emailFetcher.error = TestError(msg: "gmail 500")
        messageFetcher.result = [MessageItem(sender: "bob", text: "yo", date: Date())]

        let result = await builder.build(accessToken: "tok", since: 0)

        XCTAssertTrue(result.emails.isEmpty)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertNotNil(result.emailError)
        XCTAssertNil(result.messageError)
    }

    // MARK: Scenario 3: messages fail, email succeeds

    func testMessagesFailEmailSucceeds() async {
        emailFetcher.result = [EmailItem(from: "Carol", subject: "Sub", date: Date())]
        messageFetcher.error = MessageFetcherError.permissionDenied

        let result = await builder.build(accessToken: "tok", since: 0)

        XCTAssertEqual(result.emails.count, 1)
        XCTAssertTrue(result.messages.isEmpty)
        XCTAssertNil(result.emailError)
        XCTAssertNotNil(result.messageError)
    }

    // MARK: Scenario 4: both fail

    func testBothFail() async {
        emailFetcher.error = TestError(msg: "auth expired")
        messageFetcher.error = MessageFetcherError.permissionDenied

        let result = await builder.build(accessToken: "tok", since: 0)

        XCTAssertTrue(result.emails.isEmpty)
        XCTAssertTrue(result.messages.isEmpty)
        XCTAssertNotNil(result.emailError)
        XCTAssertNotNil(result.messageError)
    }

    // MARK: Scenario 5: empty results (no new mail)

    func testEmptyResults() async {
        emailFetcher.result = []
        messageFetcher.result = []

        let result = await builder.build(accessToken: "tok", since: 0)

        XCTAssertTrue(result.emails.isEmpty)
        XCTAssertTrue(result.messages.isEmpty)
        XCTAssertNil(result.emailError)
        XCTAssertNil(result.messageError)
    }

    // MARK: Timestamp passed through

    func testSinceTimestampPassedToMessageFetcher() async {
        var capturedSince: Double = -1
        class CaptureFetcher: MessageFetcherProtocol {
            var captured: Double = -1
            func fetch(since: Double) async throws -> [MessageItem] {
                captured = since; return []
            }
        }
        let captureFetcher = CaptureFetcher()
        let b = DigestBuilder(emailFetcher: emailFetcher, messageFetcher: captureFetcher)
        _ = await b.build(accessToken: "tok", since: 12345.0)
        XCTAssertEqual(captureFetcher.captured, 12345.0)
    }
}
