import Foundation

// MARK: - Gmail configuration

enum GmailConfig {
    static let clientID = "1029267595598-jloelo7q4o5reevrp151ou1otd3r9c25.apps.googleusercontent.com"
    static let redirectURI = "com.yourapp.karma:/oauth2callback"
}

// MARK: - Auth errors

enum AuthError: Error, LocalizedError {
    case noToken
    case authFailed
    case noAuthState

    var errorDescription: String? {
        switch self {
        case .noToken:      return "Gmail token unavailable — please reconnect"
        case .authFailed:   return "Gmail authentication failed"
        case .noAuthState:  return "Not connected to Gmail"
        }
    }
}

// MARK: - Gmail API response types (Codable)

private struct GmailMessageList: Codable {
    let messages: [GmailMessageRef]?
    struct GmailMessageRef: Codable { let id: String }
}

private struct GmailMessageDetail: Codable {
    let payload: Payload?
    struct Payload: Codable {
        let headers: [Header]?
        struct Header: Codable {
            let name: String
            let value: String
        }
    }
}

// MARK: - EmailFetcher

class EmailFetcher: EmailFetcherProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(accessToken: String, since unixTimestamp: Double) async throws -> [EmailItem] {
        // Step 1: get message IDs
        let sinceSeconds = Int(unixTimestamp)
        let listURL = URL(string:
            "https://gmail.googleapis.com/gmail/v1/users/me/messages" +
            "?q=after:\(sinceSeconds)&maxResults=5"
        )!
        let list = try await get(listURL, token: accessToken, as: GmailMessageList.self)
        guard let refs = list.messages, !refs.isEmpty else { return [] }

        // Step 2: fetch metadata for each message in parallel
        return try await withThrowingTaskGroup(of: EmailItem?.self) { group in
            for ref in refs {
                group.addTask {
                    let url = URL(string:
                        "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(ref.id)" +
                        "?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date"
                    )!
                    let detail = try await self.get(url, token: accessToken, as: GmailMessageDetail.self)
                    return self.parseDetail(detail)
                }
            }
            var items: [EmailItem] = []
            for try await item in group {
                if let item { items.append(item) }
            }
            return items
        }
    }

    // MARK: Helpers

    private func get<T: Decodable>(_ url: URL, token: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw AuthError.noToken
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func parseDetail(_ detail: GmailMessageDetail) -> EmailItem? {
        let headers = detail.payload?.headers ?? []
        func h(_ name: String) -> String {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
        }
        let from = h("From")
        let subject = h("Subject")
        let dateStr = h("Date")
        guard !from.isEmpty || !subject.isEmpty else { return nil }

        // Strip angle-bracketed email from "Display Name <email@example.com>"
        let displayFrom = from.components(separatedBy: " <").first.map {
            $0.trimmingCharacters(in: .init(charactersIn: "\""))
        } ?? from

        return EmailItem(from: displayFrom, subject: subject, date: parseRFC2822(dateStr))
    }

    private func parseRFC2822(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z",
                    "EEE, d MMM yyyy HH:mm:ss Z"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return Date()
    }
}
