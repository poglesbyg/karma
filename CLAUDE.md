# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**karma** — a macOS menu bar app that replaces 40+ ambient email/text checks per day with one 15-second intentional brief. Information satiety, not information resistance. The paradigm is "Light Phone for your Mac": strip the dopamine layer off the computer rather than fighting it with blockers.

## Build & test

```bash
# Build and run (Xcode required)
xcodebuild -scheme karma -configuration Debug build

# Run tests
xcodebuild test -scheme karma -destination 'platform=macOS'

# Single test class
xcodebuild test -scheme karma -destination 'platform=macOS' -only-testing:karmaTests/DigestBuilderTests

# Archive for distribution (requires Developer ID signing)
xcodebuild archive -scheme karma -archivePath build/karma.xcarchive
```

## Architecture

8 Swift source files. No third-party UI libraries. All communication between components goes through `StatusBarController`.

```
karmaApp.swift            — @main, MenuBarExtra scene (macOS 13+)
StatusBarController.swift — owns @Published var lastDigest: DigestResult?
                            owns @Published var fetchState: FetchState
                            DigestView reads these; menu bar title updates from them
EmailFetcher.swift        — Gmail REST API via URLSession. Conforms to EmailFetcherProtocol.
MessageFetcher.swift      — Direct SQLite3 read of ~/Library/Messages/chat.db. Conforms to MessageFetcherProtocol.
DigestBuilder.swift       — Runs EmailFetcher + MessageFetcher concurrently via async let.
                            Injected with protocols (not concrete types) for testability.
DigestView.swift          — SwiftUI popover. Text-only, monospace, no color. Reads lastDigest.
SchedulerService.swift    — 90-min Timer + NSWorkspace wake notification → triggers DigestBuilder.
PermissionManager.swift   — Full Disk Access check. Called at startup AND inside MessageFetcher.fetch().
```

## Data flow

```
TRIGGER: 90-min Timer OR NSWorkspace.didWakeNotification
  │
  ▼
SchedulerService.triggerFetch()  [guard: !isFetching]
  │
  ▼
DigestBuilder.build() async
  ├── async let emails = emailFetcher.fetch()   → Gmail REST API
  └── async let msgs   = messageFetcher.fetch() → SQLite3 chat.db (concurrent)
  │
  ▼
StatusBarController.lastDigest = DigestResult
StatusBarController.lastChecked → UserDefaults
```

Popover opens instantly from cached `lastDigest`. Only first launch shows a loading state.

## Key technical constraints

**iMessage SQLite:**
- Requires Full Disk Access (macOS System Settings → Privacy & Security → Full Disk Access). Not grantable in code — user must grant manually.
- chat.db uses Mac Absolute Time in **nanoseconds** (epoch: Jan 1, 2001). To query messages since a Unix timestamp: `macAbsoluteNanos = (unixTimestamp - 978307200) * 1_000_000_000`. Bind this as a parameter — do not do arithmetic on the indexed column or the index won't be used.
- Relevant tables: `message`, `handle`, `chat_message_join`. `message.handle_id` is a foreign key to `handle.ROWID`; join `handle` to get the phone number/email (`h.id`).
- Open with `PRAGMA journal_mode=WAL; PRAGMA query_only=ON;`. If WAL read returns 0 rows unexpectedly, retry once after 500ms.

**Gmail:**
- Uses Gmail REST API, NOT IMAP. IMAP has no good Swift-native library.
- OAuth2 scope: `gmail.metadata` (non-sensitive — avoids 7-day token revocation for unverified apps).
- OAuth redirect URI `com.yourapp.karma:/oauth2callback` must be registered in Info.plist under `CFBundleURLTypes` before adding AppAuth, or the OAuth callback will hang.
- Fetch flow: `GET /gmail/v1/users/me/messages?q=after:{unix}&maxResults=5` returns IDs, then `withTaskGroup` fetches all 5 `?format=metadata` in parallel (~300ms total).
- AppAuth-macOS: SPM `https://github.com/openid/AppAuth-iOS` (ships macOS targets). Also add GTM-AppAuth-macOS.
- OAuth tokens stored in Keychain via `kSecClassGenericPassword`. Requires `keychain-access-groups` entitlement + explicit App ID (not wildcard).

**Signing & distribution:**
- Not App Store — Full Disk Access is incompatible with App Store sandbox.
- Requires Apple Developer ID + explicit App ID + Developer ID provisioning profile.
- Distribution: GitHub Releases (.dmg) + Homebrew cask.
- CI: `.github/workflows/release.yml` on tag push — restore cert from `CERT_P12_BASE64`/`CERT_PASSWORD`, `xcodebuild archive`, `xcrun notarytool submit`, create DMG, upload to release.
- Google OAuth stays in "testing" mode for personal use (add yourself as test user in GCP console). Pursuing verification is tracked in TODOS.md.

## Testing

XCTest. `DigestBuilder` is the core testable component — it accepts injected protocols:

```swift
protocol EmailFetcherProtocol  { func fetch() async throws -> [EmailItem] }
protocol MessageFetcherProtocol { func fetch() async throws -> [MessageItem] }
```

Use mock implementations in tests. Do not test OAuth flow or Full Disk Access in automated tests — those require real credentials and OS permissions.

What is unit-testable:
- `DigestBuilder` with mock fetchers (all four result scenarios: both ok, email fails, iMessage fails, both fail)
- `MessageFetcher` date conversion math (pure function, no DB access)
- `SchedulerService` deduplication logic

## Design constraints (don't violate these)

- **Text-only.** No color, no emoji, no images, no badges. Not in the menu bar title, not in the popover.
- **No ambient presence.** The app should be invisible until clicked. No periodic notifications, no badges.
- **No metrics or streaks.** Adding any gamification or tracking defeats the purpose of the product.
- **v1 scope is fixed.** Slack, Outlook, AI summarization, behavioral timing are explicitly deferred. See TODOS.md.

## Design System
Always read DESIGN.md before making any visual or UI decisions.
All font choices, colors, spacing, and aesthetic direction are defined there.
Do not deviate without explicit user approval.
- Font: DM Mono everywhere (landing page); system monospace in SwiftUI
- Colors: warm achromatic — #f5f3ef bg, #1a1816 text, #767270 muted, zero accent
- Border radius: 0 everywhere
- No color for state — use weight and position instead
