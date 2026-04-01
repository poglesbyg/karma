import Foundation
import Combine
import AppAuth
import Security

// MARK: - FetchState

enum FetchState: Equatable {
    case idle
    case fetching
    case error(String)
}

// MARK: - Keychain helper (OIDAuthState persistence)

enum KeychainHelper {
    private static let service = "com.yourapp.karma.authState"

    static func save(_ authState: OIDAuthState) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: authState, requiringSecureCoding: true
        ) else { return }

        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecValueData: data
        ]
        SecItemDelete(attrs as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load() -> OIDAuthState? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data)
    }

    static func delete() {
        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        SecItemDelete(attrs as CFDictionary)
    }
}

// MARK: - StatusBarController

@MainActor
class StatusBarController: ObservableObject {
    @Published var lastDigest: DigestResult?
    @Published var fetchState: FetchState = .idle
    @Published var authState: OIDAuthState?

    private let lastCheckedKey = "karma.lastChecked"

    private let digestBuilder: DigestBuilder
    private lazy var scheduler: SchedulerService = SchedulerService { [weak self] in
        self?.triggerFetch()
    }

    var isFetching: Bool { fetchState == .fetching }

    // MARK: Menu bar title

    var menuBarTitle: String {
        switch fetchState {
        case .fetching where lastDigest == nil:
            return "karma ..."
        case .error:
            return "karma !"
        default:
            guard let d = lastDigest, !d.emails.isEmpty || !d.messages.isEmpty else {
                return "karma"
            }
            var parts: [String] = []
            if !d.emails.isEmpty { parts.append("\(d.emails.count) email") }
            if !d.messages.isEmpty { parts.append("\(d.messages.count) msg") }
            return parts.joined(separator: " ")
        }
    }

    // MARK: Last-checked timestamp (UserDefaults)

    var lastChecked: Double {
        get {
            let v = UserDefaults.standard.double(forKey: lastCheckedKey)
            return v > 0 ? v : Date().timeIntervalSince1970 - 7200  // default: 2 hrs ago
        }
        set { UserDefaults.standard.set(newValue, forKey: lastCheckedKey) }
    }

    // MARK: Init

    init(
        emailFetcher: EmailFetcherProtocol = EmailFetcher(),
        messageFetcher: MessageFetcherProtocol = MessageFetcher()
    ) {
        self.digestBuilder = DigestBuilder(
            emailFetcher: emailFetcher,
            messageFetcher: messageFetcher
        )
        self.authState = KeychainHelper.load()
        // Kick off scheduler + initial fetch after init
        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    private func start() {
        _ = scheduler  // force lazy init (starts timer + wake observer)
        if authState != nil { triggerFetch() }
    }

    // MARK: Fetch lifecycle

    func triggerFetch() {
        guard !isFetching else { return }
        guard authState != nil else { return }
        Task { @MainActor in await self.performFetch() }
    }

    @MainActor
    private func performFetch() async {
        guard let authState = authState else { return }
        fetchState = .fetching

        // Refresh access token via AppAuth (auto-handles expiry)
        let accessToken: String
        do {
            accessToken = try await withFreshToken(authState)
        } catch {
            self.authState = nil
            KeychainHelper.delete()
            fetchState = .error("Gmail auth expired — tap Connect Gmail")
            return
        }

        let result = await digestBuilder.build(accessToken: accessToken, since: lastChecked)
        lastDigest = result
        lastChecked = Date().timeIntervalSince1970

        if result.emailError != nil && result.messageError != nil {
            fetchState = .error(result.emailError!.localizedDescription)
        } else {
            fetchState = .idle
        }
    }

    private func withFreshToken(_ authState: OIDAuthState) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            authState.performAction { token, _, error in
                if let token {
                    cont.resume(returning: token)
                } else {
                    cont.resume(throwing: error ?? AuthError.noToken)
                }
            }
        }
    }

    // MARK: OAuth flow

    func startOAuthFlow() {
        Task { @MainActor in
            do {
                let config = try await discoverGoogleConfig()
                let request = OIDAuthorizationRequest(
                    configuration: config,
                    clientId: GmailConfig.clientID,
                    scopes: ["https://www.googleapis.com/auth/gmail.metadata"],
                    redirectURL: URL(string: GmailConfig.redirectURI)!,
                    responseType: OIDResponseTypeCode,
                    additionalParameters: nil
                )
                let agent = OIDExternalUserAgentMac()
                let appDelegate = NSApp.delegate as? AppDelegate
                let newAuthState: OIDAuthState = try await withCheckedThrowingContinuation { cont in
                    appDelegate?.currentAuthorizationFlow = OIDAuthState.authState(
                        byPresenting: request,
                        externalUserAgent: agent
                    ) { state, error in
                        if let state {
                            cont.resume(returning: state)
                        } else {
                            cont.resume(throwing: error ?? AuthError.authFailed)
                        }
                    }
                }
                self.authState = newAuthState
                KeychainHelper.save(newAuthState)
                triggerFetch()
            } catch {
                fetchState = .error("Gmail connection failed — try again")
            }
        }
    }

    private func discoverGoogleConfig() async throws -> OIDServiceConfiguration {
        try await withCheckedThrowingContinuation { cont in
            OIDAuthorizationService.discoverConfiguration(
                forIssuer: URL(string: "https://accounts.google.com")!
            ) { config, error in
                if let config {
                    cont.resume(returning: config)
                } else {
                    cont.resume(throwing: error ?? AuthError.authFailed)
                }
            }
        }
    }
}
