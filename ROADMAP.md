# OpenBar Development Roadmap

This roadmap is distilled from a DeepSeek Harness (dsh) architecture review of OpenBar v0.1 against the publicly observable behavior and common technical layers of commercial macOS menu-bar managers (e.g. Bartender). OpenBar remains a **clean-room** project: GPL-3.0, no Bartender assets or code, and a preference for public APIs over private ones.

Current baseline: v0.1 separator model (no Accessibility / Screen Recording permissions).

---

## 1. Layer comparison (v0.1 → target)

| Layer | Typical commercial approach | OpenBar v0.1 | Gap |
|---|---|---|---|
| Discovery | Accessibility (AX) + window listing | Only own 3 `NSStatusItem`s; `CGWindowListCopyWindowInfo` for hit-testing | Cannot name or locate other apps’ items |
| Identity | Stable IDs across relaunches | Own `autosaveName` only | Cannot reclaim foreign items after restart |
| Layout | Shown / Hidden / Always Hidden + order + profiles | Physical position via user ⌘-drag + macOS autosave | No logical layout model |
| Movement | Programmatic rearrange (events / system preference writers) | None | Cannot move items into sections in code |
| Hiding | Per-item or section hide | Separator `length` only (coarse) | Cannot hide a single item |
| Presentation | Floating bar, show-and-click, overflow / notch | Toggle / hover / empty-area click | Hidden items are hard to reach individually |
| Recovery | Geometry checks, move rollback, Space / Mission Control guards | Simple auto-collapse + menu heuristic | Fragile on multi-display / fullscreen / OS updates |
| Permissions | Accessibility ± Screen Recording | None | Lower ceiling, easiest distribution |

Code anchors in v0.1:

- Control items created in `OpenBar/MenuBar/MenuBarManager.swift` (order: Always Hidden → Hidden → Toggle).
- Collapse uses `collapsedLength = 10_000` in `OpenBar/MenuBar/ControlItem.swift`.
- Empty-area click uses heuristics in `OpenBar/MenuBar/MenuBarGeometry.swift` (not AX).
- Global mouse monitors in `OpenBar/Events/MenuBarEventHandler.swift`.

---

## 2. Design conclusions

1. **v0.1 “sections” are positions, not a model.** Dividers decide which *span* is hidden; the user creates sections by ⌘-dragging icons. There is no durable “this item belongs to Hidden,” so profiles, programmatic rearrange, and per-item hide are blocked.

2. **Best next step is read-only catalog + AX click — not movement.** With AX elements for foreign items you can ship a Bartender-Bar–style floating panel: expand the hidden section → `AXUIElementPerformAction(kAXPressAction)` → collapse. No moving other apps’ windows, no private APIs.

3. **Movement is the hard fork.** Synthetic drag / writing system menu-bar position preferences are high-maintenance and often private. Keep movement behind an optional advanced backend; do not block the product on it.

---

## 3. Phased plan

### Phase 0 — Harden the separator model (no new permissions)

Still in the permission-free MVP lane:

- Re-apply collapse length on display / menu-bar geometry changes.
- Detect divider order after user ⌘-drag; offer a “Repair layout” action (`statusItem.button?.window?.frame`).
- Improve “menu is open” detection so auto-collapse does not fight open menus.
- Replace the midpoint empty-area heuristic when possible; document notch / multi-display limits.
- Introduce an explicit state machine and a draft `MenuBarLayout` model (even if still user-driven).

**Done when:** Expand/collapse survives sleep, display plug/unplug, and fullscreen reliably; mis-ordered dividers are detectable.

### Phase 1 — Read-only AX catalog *(highest priority)*

New types:

- `MenuBarScanner.swift` — walk `NSWorkspace.runningApplications`, `AXUIElementCreateApplication(pid)`, read `kAXMenuBarAttribute`, recurse menu-bar items / status menus / wrappers (depth ≤ 4); batch-read `AXLabel`, `AXTitle`, `AXIdentifier`, `AXPosition`, `AXSize`.
- `MenuBarItem.swift` — stable id from `bundleID + axIdentifier + title + ordinal`; `CGWindowID` only as session routing evidence.
- `MenuBarItemStore.swift` — `@Observable` catalog, JSON persistence, tombstones for disappeared items.
- `AccessibilityPermission.swift` — `AXIsProcessTrustedWithOptions` onboarding.

Window matching with public API only: `CGWindowListCopyWindowInfo` on status-window layer, width ≤ 400pt, frame error ≤ 5pt. No private CGS.

**Acceptance:** ≥ ~90% match on common apps + system items; identity survives app relaunch; denied Accessibility shows empty state + guide, no crash.

### Phase 2 — Floating bar + AX press *(largest UX jump)*

- `HiddenItemsBar` — nonactivating `NSPanel` at menu-bar level.
- Buttons from ScreenCaptureKit snapshots when allowed; otherwise app icons.
- On click: expand section → wait for AX frame → `AXPress` → collapse after menu closes / delay.
- Keep auto-collapse from stealing focus while a menu is open.

**Acceptance:** Can open hidden Wi‑Fi / Bluetooth / stats menus; multi-display and notch OK; auto-collapse does not interrupt open menus.

### Phase 3 — Logical layout + optional movers

- `MenuBarLayout`: sections, order, profiles, insertion markers.
- `MenuBarMover` protocol:
  - `NoopMover` — record layout only; user still ⌘-drags.
  - `AXDragMover` — Accessibility + `CGEvent` (best-effort across OS versions).
  - Advanced / optional backends for OS-specific preference writers (not required for default builds).
- Transactional moves: refresh AX geometry → move → verify → rollback; one move at a time.
- Guards for Mission Control, Spaces, Spotlight, display zoom.

**Acceptance:** Items stay in Hidden / Always Hidden across relaunch; failed profile switch keeps previous layout; cancelled moves leave no stuck mouse-down.

### Phase 4 — Stability & polish

- Multi-display, resolution changes, auto-hiding menu bar, fullscreen Spaces, Stage Manager, sleep/wake.
- Diagnostic logging and a “Repair layout” entry when dividers are out of order.
- Triggers, profiles auto-switch, appearance (menu-bar tint / spacing), App Intents / scripting — as later product layers once Phases 1–3 are solid.

---

## 4. Explicitly deferred (do not start now)

- Private “assessment mode” / undocumented menu-bar hide APIs (App Store + OS-upgrade risk).
- Writing Control Center / system whitelist plists as a first-class path.
- Synthetic drag **before** stable item identity exists (easy to drag the wrong window or leave event taps stuck).

---

## 5. Recommended sequence

If OpenBar stays **free, open-source, and permission-light**:

**Phase 0 harden → Phase 1 AX catalog → Phase 2 floating bar + AX press → Phase 3 optional movers → Phase 4 stability.**

That path aims for most of the “discoverable + reachable” experience without taking on private-API maintenance first.

---

## 6. Near-term next commit

When ready to implement:

1. Accessibility permission onboarding UI.
2. `MenuBarScanner` + `MenuBarItem` + `MenuBarItemStore`.
3. Read-only Items debug list in Settings (prove catalog before building the floating bar).

License: same as the project (GPL-3.0). See `CREDITS.md` for reference projects (Ice, Hidden Bar, Dozer, KeyboardShortcuts).
