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

    func disconnect() {
        authState = nil
        KeychainHelper.delete()
        fetchState = .idle
        lastDigest = nil
    }

    // MARK: OAuth flow

    func startOAuthFlow(loginHint: String = "") {
        Task { @MainActor in
            do {
                print("[karma] Starting OAuth flow...")
                let config = try await discoverGoogleConfig()
                print("[karma] OAuth config discovered")
                
                let hint = loginHint.trimmingCharacters(in: .whitespacesAndNewlines)
                let request = OIDAuthorizationRequest(
                    configuration: config,
                    clientId: GmailConfig.clientID,
                    scopes: ["https://www.googleapis.com/auth/gmail.metadata"],
                    redirectURL: URL(string: GmailConfig.redirectURI)!,
                    responseType: OIDResponseTypeCode,
                    additionalParameters: hint.isEmpty ? nil : ["login_hint": hint]
                )
                
                // Create external user agent without a specific window — let AppAuth handle it
                // Passing a window can cause issues if the popover dismisses while OAuth is in progress
                let agent = OIDExternalUserAgentMac()
                print("[karma] External user agent created")
                
                guard let delegate = AppDelegate.shared else {
                    throw AuthError.authFailed
                }
                
                let newAuthState: OIDAuthState = try await withCheckedThrowingContinuation { cont in
                    var resumed = false
                    print("[karma] Creating OAuth flow...")
                    
                    let flow = OIDAuthState.authState(
                        byPresenting: request,
                        externalUserAgent: agent
                    ) { state, error in
                        guard !resumed else { 
                            print("[karma] OAuth callback called multiple times (ignored)")
                            return 
                        }
                        resumed = true
                        if let state {
                            print("[karma] OAuth succeeded")
                            cont.resume(returning: state)
                        } else {
                            print("[karma] OAuth failed: \(error?.localizedDescription ?? "unknown error")")
                            cont.resume(throwing: error ?? AuthError.authFailed)
                        }
                    }
                    
                    if flow == nil {
                        print("[karma] Failed to create OAuth flow session")
                        resumed = true
                        cont.resume(throwing: AuthError.authFailed)
                    } else {
                        print("[karma] OAuth flow session created, waiting for callback...")
                        delegate.currentAuthorizationFlow = flow
                    }
                }
                
                self.authState = newAuthState
                KeychainHelper.save(newAuthState)
                print("[karma] OAuth state saved to keychain, starting fetch...")
                triggerFetch()
            } catch {
                print("[karma] OAuth error: \(error) — \(error.localizedDescription)")
                fetchState = .error("Gmail connection failed: \(error.localizedDescription)")
            }
        }
    }

    private func discoverGoogleConfig() async throws -> OIDServiceConfiguration {
        print("[karma] Discovering Google OAuth config...")
        return try await withCheckedThrowingContinuation { cont in
            var resumed = false
            
            // Schedule a timeout to prevent hanging
            let timeout = DispatchWorkItem {
                guard !resumed else { return }
                resumed = true
                print("[karma] Google config discovery timed out after 15 seconds")
                cont.resume(throwing: AuthError.authFailed)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
            
            OIDAuthorizationService.discoverConfiguration(
                forIssuer: URL(string: "https://accounts.google.com")!
            ) { config, error in
                guard !resumed else { 
                    print("[karma] Config discovery callback called multiple times (ignored)")
                    return 
                }
                resumed = true
                timeout.cancel()  // Cancel the timeout since we got a response
                
                if let config {
                    print("[karma] Google OAuth config discovered successfully")
                    cont.resume(returning: config)
                } else {
                    print("[karma] Google config discovery failed: \(error?.localizedDescription ?? "unknown error")")
                    cont.resume(throwing: error ?? AuthError.authFailed)
                }
            }
        }
    }
}
