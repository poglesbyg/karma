# Design System — karma

## Product Context
- **What this is:** A macOS menu bar app that replaces ambient email and message monitoring with one intentional 15-second digest
- **Who it's for:** Mac users who want to break the compulsive checking habit without disconnecting entirely
- **Space/industry:** Focus tools, digital minimalism, intentional computing
- **Project type:** macOS native app (menu bar) + landing page

## Aesthetic Direction
- **Direction:** Wire Dispatch
- **Decoration level:** None. Typography does all the work.
- **Mood:** The visual language of a telegraph service or a well-worn field notebook. Information presented plainly, then gone. Not a wellness app, not a developer tool — something in between that neither category has occupied.
- **Competitive position:** Every product in the focus/minimalism space uses either zero color (Light Phone — cold, hardware-limited) or a single restrained accent (Things 3 — blue; Bear — red; Mela — yellow). The warm achromatic monospace position is unclaimed.

## Typography
- **All type:** DM Mono — a humanist-influenced monospace readable enough for body copy, warm enough to not feel like a terminal
- **Display/Hero:** DM Mono Medium, large, tight tracking (-0.02em)
- **Display italic:** DM Mono Light Italic — supporting voice, contrast to medium weight
- **Body:** DM Mono Regular, 15px, line-height 1.7
- **UI labels:** DM Mono Regular, 10–11px, letter-spacing 0.10–0.14em, uppercase
- **Data rows (app):** DM Mono Regular, 12px, line-height 1.5
- **Loading:** Google Fonts CDN — `https://fonts.googleapis.com/css2?family=DM+Mono:ital,wght@0,300;0,400;0,500;1,400&display=swap`
- **In-app (SwiftUI):** `.font(.system(.body, design: .monospaced))` — system monospace, consistent with macOS

## Color
- **Approach:** Achromatic with warmth. Zero accent color anywhere — not even blue links.
- **Rationale:** Color is attention. karma's entire premise is refusing to compete for your attention. The design holds that position.

| Token      | Light Mode | Dark Mode  | Usage |
|------------|-----------|-----------|-------|
| background | `#f5f3ef` | `#1a1816` | Page/app background |
| surface    | `#ffffff`  | `#242220` | Cards, popover |
| text       | `#1a1816` | `#f0ede8` | Primary content |
| muted      | `#767270` | `#6e6b68` | Secondary labels, metadata |
| divider    | `#e8e5e0` | `#2e2c2a` | Borders, rules |

- **No semantic colors** (no green success, no red error, no blue info) — use weight and position to convey state
- **Dark mode:** Same warmth, inverted. `#1a1816` background, `#f0ede8` text. Not pure black.

## Spacing
- **Base unit:** 8px
- **Density:** Comfortable — not sparse, not dense
- **Scale:** 8 / 16 / 24 / 32 / 48 / 64px
- **App popover:** 12px internal padding, 14px horizontal padding for content rows

## Layout
- **Approach:** Grid-disciplined (app) / editorial typographic (landing page)
- **App popover:** 300px fixed width, single column, no border radius
- **Landing page:** max-width 680px, centered, single-column dominant
- **Border radius:** 0 everywhere. No rounded corners on anything — buttons, inputs, cards, the icon.
- **Reason:** Every app in this space uses rounded corners as a "friendliness" signal. Zero radius makes karma feel more like an instrument than a consumer app.

## Motion
- **App:** None. State changes are instant.
- **Landing page:** Minimal fade only — no slides, no bounces, no scroll-driven animation

## App Icon
- **Concept:** Lowercase `k` in DM Mono Medium, centered in a square
- **Light variant:** `#1a1816` on `#f5f3ef`
- **Dark/macOS icon:** `#f0ede8` on `#1a1816`
- **Menu bar representation:** The text "karma" in the system monospace — no icon glyph needed

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-01 | Zero accent color | Color is attention; refusing to compete for it |
| 2026-04-01 | DM Mono everywhere | Warm enough for body copy, distinctive in the category |
| 2026-04-01 | Border radius 0 | Instrument feel over consumer app friendliness |
| 2026-04-01 | Wire Dispatch aesthetic | Unclaimed position in the focus/minimalism space |
| 2026-04-01 | Warm near-black (#1a1816) over pure black | Pure black feels harsh; warmth is intentional |
