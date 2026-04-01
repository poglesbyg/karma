import SwiftUI
import AppAuth

// Handles OAuth redirect URL from Safari (com.yourapp.karma:/oauth2callback)
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var currentAuthorizationFlow: OIDExternalUserAgentSession?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let flow = currentAuthorizationFlow,
               flow.resumeExternalUserAgentFlow(with: url) {
                currentAuthorizationFlow = nil
                return
            }
        }
    }
}

@main
struct karmaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var controller = StatusBarController()

    var body: some Scene {
        MenuBarExtra {
            DigestView()
                .environmentObject(controller)
        } label: {
            Text(controller.menuBarTitle)
                .font(.system(.body, design: .monospaced))
        }
        .menuBarExtraStyle(.window)
    }
}
