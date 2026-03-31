import Foundation

// MARK: - Data models

struct EmailItem {
    let from: String
    let subject: String
    let date: Date
}

struct MessageItem {
    let sender: String
    let text: String
    let date: Date
}

struct DigestResult {
    let emails: [EmailItem]
    let messages: [MessageItem]
    let emailError: Error?
    let messageError: Error?
    let fetchedAt: Date
}

// MARK: - Protocols (for testability via mock injection)

protocol EmailFetcherProtocol {
    func fetch(accessToken: String, since: Double) async throws -> [EmailItem]
}

protocol MessageFetcherProtocol {
    func fetch(since: Double) async throws -> [MessageItem]
}

// MARK: - DigestBuilder

class DigestBuilder {
    let emailFetcher: EmailFetcherProtocol
    let messageFetcher: MessageFetcherProtocol

    init(emailFetcher: EmailFetcherProtocol, messageFetcher: MessageFetcherProtocol) {
        self.emailFetcher = emailFetcher
        self.messageFetcher = messageFetcher
    }

    func build(accessToken: String, since timestamp: Double) async -> DigestResult {
        async let emailResult = fetchEmails(accessToken: accessToken, since: timestamp)
        async let messageResult = fetchMessages(since: timestamp)
        let (er, mr) = await (emailResult, messageResult)
        return DigestResult(
            emails: er.items,
            messages: mr.items,
            emailError: er.error,
            messageError: mr.error,
            fetchedAt: Date()
        )
    }

    private func fetchEmails(accessToken: String, since: Double) async -> (items: [EmailItem], error: Error?) {
        do {
            return (try await emailFetcher.fetch(accessToken: accessToken, since: since), nil)
        } catch {
            return ([], error)
        }
    }

    private func fetchMessages(since: Double) async -> (items: [MessageItem], error: Error?) {
        do {
            return (try await messageFetcher.fetch(since: since), nil)
        } catch {
            return ([], error)
        }
    }
}
