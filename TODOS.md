# karma TODOS

## P1 — Verify Timer + wake notification on macOS Sequoia (15)
**What:** Manual verification test: build and run karma on macOS 15. Sleep/wake the machine and confirm NSWorkspace.didWakeNotification fires and SchedulerService.triggerFetch() runs.
**Why:** macOS 15 Sequoia tightened background execution policies. NSTimer on the main RunLoop in a MenuBarExtra app should be unaffected, but this hasn't been confirmed.
**Context:** Run once before first distribution. If it breaks: NSBackgroundModes key in Info.plist may be required.
**Effort:** S | **Priority:** P1

## P2 — Google OAuth verification (for public distribution)
**What:** Go through Google's OAuth app verification process to remove the "unverified app" warning.
**Why:** Personal use is fine in "testing" mode. But if karma is ever shared via GitHub Releases or Homebrew, users will see a scary consent screen. Verification requires a privacy policy and security assessment.
**Context:** For now, distribute as personal use only (add yourself as test user in GCP console). Pursue verification when/if making it public. Using gmail.metadata scope (non-sensitive) means tokens don't expire after 7 days — verification is for UX polish, not functional necessity.
**Effort:** L (human: weeks of Google back-and-forth) → M with CC | **Priority:** P2

## Resolved
- **Deduplication mechanism** — Resolved in eng review (2026-03-31): boolean gate (StatusBarController.isFetching) + 30s DispatchWorkItem debounce on wake notifications.
