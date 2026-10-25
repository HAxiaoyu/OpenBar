# OpenBar

A free, open-source menu bar manager for macOS. Hide the status-bar icons you
rarely need, reveal them with a click, hover or hotkey, and keep your menu bar
tidy — no subscription, no license key.

> **Status:** v0.1 scaffold (MVP). Builds with Xcode; requires macOS 14 Sonoma or later.
> **No permissions required** in v0.1 — no Accessibility, no Screen Recording.

## How it works

macOS has no public API for hiding *other* apps' status items. OpenBar uses the
well-known "separator" technique (pioneered by Hidden Bar, also used by Dozer and Ice):

```
[always-hidden icons] ‖ [hidden icons] │ [visible icons] ‹  [Control Center] [clock]
                      ↑                ↑                 ↑
              Always-Hidden         Hidden            OpenBar
                 divider            divider         (toggle icon)
```

* OpenBar owns three status items: its chevron toggle icon and two thin dividers.
* **Collapse** = set a divider's `NSStatusItem.length` to 10 000 pt. It no longer
  fits in the menu bar, so macOS stops drawing it *and every item to its left*.
* **Expand** = set the length back to normal; the icons reappear.
* You decide which icons go where by **⌘-dragging** them once; macOS remembers
  their positions. (Programmatic re-ordering is on the roadmap.)

## Features (v0.1)

| Feature | Notes |
|---|---|
| Hidden + Always-Hidden sections | Two dividers. ⌥-click the chevron (or use the second hotkey) to reveal Always-Hidden too. |
| Click the chevron to toggle | Right-click (or ⌃-click) for the menu: Settings, arrange help, Quit. |
| Show on click in empty menu bar space | On by default. |
| Show on hover over empty menu bar space | Off by default; configurable delay (0–2 s). |
| Auto-hide after N seconds | Default 15 s; postponed while the pointer is in the menu bar or a menu is open. |
| Hide when pointer leaves the menu bar | Applies to hover-triggered reveals. |
| Global hotkeys | Via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts); no default — record one in Settings › Hotkeys. |
| Launch at login | `SMAppService.mainApp`. |
| Settings window (SwiftUI) | Persisted to `UserDefaults`. |
| First-run onboarding | Explains the ⌘-drag arrangement. Reopen from the menu: *How to Arrange Icons…* |
| Menu bar only | `LSUIElement = YES`, no Dock icon. Double-click the app in Finder while running to open Settings. |

## Building

Requirements: **Xcode 26** or later (the KeyboardShortcuts 3.x package uses
swift-tools-version 6.2), macOS 14+.

1. Open `OpenBar.xcodeproj` in Xcode. It will resolve the KeyboardShortcuts
   Swift package automatically (File › Packages › Resolve Package Versions if not).
2. Select the **OpenBar** target › **Signing & Capabilities**:
   * **Team:** pick your Apple ID / Developer ID team. (Out of the box the project
     is set to "Sign to Run Locally", which is enough for running from Xcode.)
   * **Bundle Identifier:** change `com.example.OpenBar` to something you own,
     e.g. `com.yourname.OpenBar`.
3. Press **⌘R**. A chevron appears in the menu bar and the onboarding window opens.

Notes:
* *Launch at login* needs a properly signed app in a stable location
  (e.g. `/Applications`). Running from DerivedData with an ad-hoc signature may
  fail to register or show as "requires approval".
* If macOS (26+) hides new menu bar items, allow OpenBar under
  System Settings › Menu Bar.
* To distribute builds outside your Mac: Product › Archive › Distribute App ›
  Developer ID, then notarize.

## Project layout

```
OpenBar/
├── App/            main.swift (AppKit entry), AppDelegate
├── MenuBar/        ControlItem (status items + length trick), MenuBarManager (state,
│                   menu, auto-collapse), MenuBarGeometry (permission-free hit-testing)
├── Events/         GlobalEventMonitor, MenuBarEventHandler (click/hover/leave)
├── Hotkeys/        KeyboardShortcuts names + registration
├── Settings/       AppSettings (@Observable + UserDefaults), SettingsView, LaunchAtLogin
├── Onboarding/     OnboardingView
├── Utilities/      WindowPresenter (SwiftUI views in NSWindows)
├── Assets.xcassets
└── Info.plist
```

The Xcode project uses a *synchronized folder* (Xcode 16+), so any file you add
under `OpenBar/` is compiled automatically — no project-file edits needed.

## Known limitations in v0.1

* "Empty menu bar space" is detected heuristically without permissions: right of
  the notch on notched displays, otherwise right of the screen's midpoint and not
  over a status item. Very wide app menus may be misdetected.
* No programmatic re-ordering — arrange icons with ⌘-drag (expand first).
* If a status item is wider than the remaining space, macOS (not OpenBar) may hide
  it on small/notched screens.

## Roadmap

Detailed plan (from architecture review): see **[ROADMAP.md](ROADMAP.md)**.

* **v0.1 (this)** — permission-free MVP described above.
* **Phase 0** — Harden separator model (display changes, layout repair).
* **Phase 1** — Read-only Accessibility catalog of menu-bar items.
* **Phase 2** — Floating bar + AX press for hidden items.
* **Phase 3** — Logical layout + optional movers / profiles.
* **Phase 4** — Multi-display / fullscreen stability and polish.

## Clean-room & license

OpenBar is licensed under **GPL-3.0-or-later** (see [LICENSE](LICENSE)). It is a
clean-room implementation: features are modeled on publicly observable
behavior of menu bar managers; no proprietary application was decompiled or
disassembled, and no third-party names, icons or assets are used. Because the
project is GPL-3.0, code from [Ice](https://github.com/jordanbaird/Ice)
(GPL-3.0) may be reused with attribution; see [CREDITS.md](CREDITS.md) for all
references and dependencies.
