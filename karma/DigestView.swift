import SwiftUI
import AppKit

struct DigestView: View {
    @EnvironmentObject var controller: StatusBarController
    @State private var clientIDInput = ""
    @State private var emailInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            contentArea
        }
        .frame(width: 300)
        .font(.system(.body, design: .monospaced))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Text("KARMA").fontWeight(.bold)
            Spacer()
            if let d = controller.lastDigest {
                Text(d.fetchedAt, style: .time)
                    .foregroundColor(.secondary)
                    .font(.system(.caption, design: .monospaced))
            }
            Button(action: { controller.triggerFetch() }) {
                Text("↻")
            }
            .buttonStyle(.plain)
            .disabled(controller.fetchState == .fetching)
            .opacity(controller.fetchState == .fetching ? 0.4 : 1.0)
            .help("Refresh now")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content routing

    @ViewBuilder
    private var contentArea: some View {
        if controller.clientID == nil {
            setupView
        } else if controller.authState == nil {
            connectView
        } else if let digest = controller.lastDigest {
            digestContent(digest)
        } else {
            loadingView
        }
    }

    // MARK: - Setup (no Client ID yet)

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your Google OAuth Client ID.")
                .foregroundColor(.secondary)
            Text("GCP Console → APIs & Services → Credentials → OAuth 2.0 Client IDs")
                .foregroundColor(.secondary)
                .font(.system(.caption, design: .monospaced))
            TextField("xxx.apps.googleusercontent.com", text: $clientIDInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
            Button("Save") {
                controller.saveClientID(clientIDInput)
            }
            .disabled(clientIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }

    // MARK: - Sign in (Client ID set, no auth)

    private var connectView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your Gmail address to sign in.")
                .foregroundColor(.secondary)
            TextField("you@gmail.com", text: $emailInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { signIn() }
            Button("Sign in with Google") { signIn() }
                .disabled(emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }

    private func signIn() {
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return }
        controller.startOAuthFlow(loginHint: email)
    }

    // MARK: - Loading (auth exists, no digest yet)

    private var loadingView: some View {
        Text("Loading...")
            .foregroundColor(.secondary)
            .padding(12)
    }

    // MARK: - Digest content

    @ViewBuilder
    private func digestContent(_ d: DigestResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let hasEmail = !d.emails.isEmpty || d.emailError != nil
            let hasMsg = !d.messages.isEmpty || d.messageError != nil

            if hasEmail {
                emailSection(d)
                if hasMsg { Divider().padding(.horizontal, 12) }
            }
            if hasMsg {
                messagesSection(d)
            }
            if !hasEmail && !hasMsg {
                Text("Nothing new since last check.")
                    .foregroundColor(.secondary)
                    .padding(12)
            }
            Divider()
            footerBar(d)
        }
    }

    // MARK: - Email section

    private func emailSection(_ d: DigestResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EMAIL (\(d.emails.count))")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            if let err = d.emailError {
                Text("Gmail: \(err.localizedDescription)")
                    .foregroundColor(.red)
            } else {
                ForEach(d.emails.indices, id: \.self) { i in
                    Text("· \(d.emails[i].from): \"\(cap(d.emails[i].subject, 28))\"")
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
    }

    // MARK: - Messages section

    private func messagesSection(_ d: DigestResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MESSAGES (\(d.messages.count))")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            if let err = d.messageError {
                if isPermissionError(err) {
                    HStack(spacing: 4) {
                        Text("iMessage unavailable —")
                        Button("Open Settings") { openFDASettings() }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                    }
                } else {
                    Text("iMessage: \(err.localizedDescription)")
                        .foregroundColor(.red)
                }
            } else {
                ForEach(d.messages.indices, id: \.self) { i in
                    Text("· \(d.messages[i].sender): \"\(cap(d.messages[i].text, 28))\"")
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
    }

    // MARK: - Footer

    private func footerBar(_ d: DigestResult) -> some View {
        let nextCheck = d.fetchedAt.addingTimeInterval(90 * 60)
        let remaining = max(0, nextCheck.timeIntervalSinceNow)
        let mins = Int(remaining / 60)
        return Text("Next check in \(mins) min")
            .foregroundColor(.secondary)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func cap(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n)) + "..."
    }

    private func isPermissionError(_ error: Error) -> Bool {
        if let e = error as? MessageFetcherError, case .permissionDenied = e { return true }
        return false
    }

    private func openFDASettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        )
    }
}
