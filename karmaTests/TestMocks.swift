import Foundation
@testable import karma

// MARK: - Shared test mocks

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

class MockMessageFetcher: MessageFetcherProtocol {
    var result: [MessageItem] = []
    var error: Error? = nil

    func fetch(since: Double) async throws -> [MessageItem] {
        if let error { throw error }
        return result
    }
}

struct TestError: Error { let msg: String }
