//
//  OpenBar — an open-source menu bar manager for macOS.
//  Copyright (C) 2026 OpenBar contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version. See the LICENSE file for details.
//

import AppKit
import OSLog

/// Owns OpenBar's control items and the expanded/collapsed state of each section.
@MainActor
final class MenuBarManager: NSObject {
    /// What caused the most recent expansion. Some behaviors (e.g. "collapse when
    /// the mouse leaves the menu bar") only apply to certain triggers.
    enum Trigger: Equatable {
        case toggleItem
        case hotkey
        case emptyAreaClick
        case hover
        case programmatic
    }

    private let logger = Logger(subsystem: "OpenBar", category: "MenuBarManager")
    private let settings: AppSettings

    // Preferred position places the controls. On macOS 27 a smaller value sits
    // further right, so the chevron stays to the right of the hidden divider.
    private let toggleItem: ControlItem
    private let hiddenDivider: ControlItem
    private let alwaysHiddenDivider: ControlItem
    private let hiddenBar = HiddenItemsBar()

    private var phase: MenuBarLayout.Phase = .collapsed
    private var barTask: Task<Void, Never>?
    private var pressTask: Task<Void, Never>?
    /// The hidden section was opened only to see which icons belong in the bar.
    private var barOpenedSection = false
    private var openingBar = false
    private var barGeneration = 0
    private var pressGeneration = 0
    /// Collapse the section after the newest bar click, because the bar opened it.
    private var collapseAfterPress = false
    private(set) var lastExpansionTrigger: Trigger?

    var isHiddenSectionExpanded: Bool { phase != .collapsed }
    var isAlwaysHiddenSectionExpanded: Bool { phase == .allRevealed }

    var onOpenSettings: (() -> Void)?
    var onOpenOnboarding: (() -> Void)?

    private var autoCollapseTask: Task<Void, Never>?
    private var reapplyTask: Task<Void, Never>?
    private var settingsObserver: NSObjectProtocol?
    private var geometryObservers: [NSObjectProtocol] = []
    /// macOS 27 can deliver one click through both the button action and the
    /// expanded-interface delegate. Drop the second delivery.
    private var lastClickUptime: TimeInterval = -.infinity

    init(settings: AppSettings) {
        self.settings = settings
        alwaysHiddenDivider = ControlItem(role: .alwaysHidden)
        hiddenDivider = ControlItem(role: .hidden)
        toggleItem = ControlItem(role: .toggle)
        super.init()

        configureActions()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyState()
                self?.scheduleAutoCollapse()
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let geometryNames: [(NotificationCenter, Notification.Name)] = [
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification),
        ]
        for (center, name) in geometryNames {
            geometryObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleReapply() }
            })
        }
        geometryObservers.append(NotificationCenter.default.addObserver(
            forName: .openBarRepairLayout, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.repairLayout() }
        })
        MenuBarGeometry.startMenuTrackingWatch()
        MenuBarLayout.assertOrderRules()

        // Start collapsed: that's the point of the app.
        applyState()
    }

    // MARK: - Public API

    func expand(trigger: Trigger, includingAlwaysHidden: Bool = false) {
        if includingAlwaysHidden || phase == .allRevealed {
            phase = .allRevealed
        } else {
            phase = .hiddenRevealed
        }
        lastExpansionTrigger = trigger
        applyState()
        scheduleAutoCollapse()
    }

    func collapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        phase = .collapsed
        lastExpansionTrigger = nil
        applyState()
    }

    func toggle(trigger: Trigger) {
        if isHiddenSectionExpanded {
            collapse()
        } else {
            expand(trigger: trigger)
        }
    }

    /// Reveal (or hide) everything, including the Always-Hidden section.
    func toggleAlwaysHidden(trigger: Trigger) {
        if isAlwaysHiddenSectionExpanded {
            collapse()
        } else {
            expand(trigger: trigger, includingAlwaysHidden: true)
        }
    }

    /// (Re)start the auto-collapse countdown. Call on user interaction in the
    /// menu bar so the section doesn't vanish while it's being used.
    func scheduleAutoCollapse(after delay: Double? = nil) {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        guard isHiddenSectionExpanded,
              settings.autoCollapseEnabled,
              lastExpansionTrigger != .programmatic
        else { return }

        let seconds = delay ?? max(1, settings.autoCollapseDelay)
        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.autoCollapseTimerFired()
        }
    }

    // MARK: - State

    private func applyState() {
        let showsGlyph = settings.showSectionDividers
        let length = collapseLength()
        toggleItem.setToggleAppearance(expanded: isHiddenSectionExpanded || hiddenBar.isVisible)
        hiddenDivider.setDivider(
            expanded: !MenuBarLayout.dividerDrawsWide(.hidden, phase: phase),
            showsGlyph: showsGlyph,
            collapsedLength: length
        )
        alwaysHiddenDivider.setDivider(
            expanded: !MenuBarLayout.dividerDrawsWide(.alwaysHidden, phase: phase),
            showsGlyph: showsGlyph && isHiddenSectionExpanded,
            collapsedLength: length
        )
    }

    /// Length that pushes icons to the left of the divider off the menu bar.
    /// A length that still fits on macOS 27 is a blank gap; a longer one is
    /// dropped and hides nothing. Zero leaves the icons where they are.
    /// shortcut: notch turns the overflow into a visible gap, move icons when that exists.
    private func collapseLength() -> CGFloat {
        guard #available(macOS 27, *) else { return ControlItem.collapsedLength }
        return 0
    }

    /// AppKit drops a collapsed divider's length across sleep, Space changes
    /// (fullscreen), and display changes. Put the current phase back.
    private func scheduleReapply() {
        reapplyTask?.cancel()
        reapplyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.applyState()
        }
    }

    /// Mid-X of our items that are actually on a menu bar right now.
    private func onBarMidX() -> [ControlItem.Role: CGFloat] {
        let bars = NSScreen.screens.map { MenuBarGeometry.menuBarFrame(on: $0) }
        var midX: [ControlItem.Role: CGFloat] = [:]
        for item in [alwaysHiddenDivider, hiddenDivider, toggleItem] {
            guard let frame = item.statusItem.button?.window?.frame,
                  bars.contains(where: { $0.intersects(frame) })
            else { continue }
            midX[item.role] = frame.midX
        }
        return midX
    }

    /// Put the three controls back in always-hidden, hidden, toggle order and
    /// leave them expanded so the user can ⌘-drag icons between the lines.
    private func repairLayout() {
        for item in [toggleItem, hiddenDivider, alwaysHiddenDivider] {
            item.removeFromStatusBar()
        }
        // Preferred position, not creation order, decides left-to-right.
        for item in [alwaysHiddenDivider, hiddenDivider, toggleItem] {
            item.installAtPreferredPosition()
        }
        configureActions()
        expand(trigger: .programmatic, includingAlwaysHidden: true)
    }

    private func autoCollapseTimerFired() {
        autoCollapseTask = nil
        // Don't yank icons away while the user is pointing at them or has
        // one of their menus open; check again shortly.
        if MenuBarGeometry.isMenuOpen() || MenuBarGeometry.isMouseInMenuBar() {
            scheduleAutoCollapse(after: 2)
            return
        }
        logger.debug("Auto-collapsing hidden section")
        collapse()
    }

    // MARK: - Actions

    private func configureActions() {
        if let button = toggleItem.statusItem.button {
            button.target = self
            button.action = #selector(toggleItemClicked(_:))
            // macOS 27 delivers the menu-bar click as an AppKit-defined event,
            // not leftMouseUp, so the button never fires unless that mask is included.
            var mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
            if #available(macOS 27.0, *) {
                mask.insert(.appKitDefined)
                toggleItem.statusItem.expandedInterfaceDelegate = self
            }
            button.sendAction(on: mask)
        }
        for divider in [hiddenDivider, alwaysHiddenDivider] {
            divider.statusItem.button?.target = self
            divider.statusItem.button?.action = #selector(dividerClicked(_:))
            if #available(macOS 27.0, *) {
                divider.statusItem.expandedInterfaceDelegate = self
            }
        }
    }

    /// Left click toggles. Option-click includes Always-Hidden. Right click opens the menu.
    private func handleToggleClick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastClickUptime < 0.05 { return }
        lastClickUptime = now

        let event = NSApp.currentEvent
        let flags = event?.modifierFlags ?? []
        let type = event?.type
        if type == .rightMouseUp || type == .rightMouseDown || flags.contains(.control) {
            showMenu()
        } else if flags.contains(.option) {
            toggleAlwaysHidden(trigger: .toggleItem)
        } else {
            toggleHiddenBar()
        }
    }

    /// Show or hide the capsule of icons that live in the hidden section.
    func toggleHiddenBar() {
        barGeneration += 1
        if hiddenBar.isVisible || openingBar {
            barTask?.cancel()
            let shouldCollapse = barOpenedSection
            barOpenedSection = false
            openingBar = false
            hiddenBar.hide()
            if shouldCollapse { collapse() }
            return
        }
        openingBar = true
        let generation = barGeneration
        barTask = Task { await openHiddenBar(generation: generation) }
    }

    private func openHiddenBar(generation: Int) async {
        defer {
            if generation == barGeneration { openingBar = false }
        }
        guard generation == barGeneration, !Task.isCancelled else { return }

        var hidden: [MenuBarItem] = []
        var message = String(localized: "Allow Accessibility to show hidden icons.")
        if AccessibilityPermission.isTrusted {
            message = String(localized: "Only icons that leave the menu bar are listed. One still up top is not hidden.")
            var visibleOnBar = Set<String>()
            if !isHiddenSectionExpanded {
                let before = await scanNow()
                guard generation == barGeneration else { return }
                visibleOnBar = Set(before.compactMap { onBarID($0) })
                barOpenedSection = true
                expand(trigger: .programmatic)
            }
            hidden = await collectHiddenItems(generation: generation)
            hidden.removeAll { visibleOnBar.contains($0.id) }
            guard generation == barGeneration else { return }
            if barOpenedSection {
                barOpenedSection = false
                collapse()
            }
        }
        guard generation == barGeneration, openingBar, !Task.isCancelled else { return }
        let ownClick: (NSPoint) -> Bool = { [weak self] point in
            self?.toggleItem.statusItem.button?.window?.frame.insetBy(dx: -8, dy: -8).contains(point) ?? false
        }
        hiddenBar.show(
            items: hidden,
            emptyMessage: message,
            anchorMidX: toggleItem.statusItem.button?.window?.frame.midX ?? NSScreen.main?.frame.midX ?? 0,
            ownsClick: ownClick,
            onPress: { [weak self] item in self?.pressFromBar(item) },
            onDismiss: { [weak self] in self?.applyState() }
        )
        applyState()
    }

    private func collectHiddenItems(generation: Int) async -> [MenuBarItem] {
        let own = Bundle.main.bundleIdentifier ?? "com.example.OpenBar"
        var hidden: [MenuBarItem] = []
        var scansWithDivider = 0
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled || generation != barGeneration { return hidden }
            guard onBarMidX()[.hidden] != nil else { continue }
            let scanned = await scanNow()
            if Task.isCancelled || generation != barGeneration { return hidden }
            guard let dividerX = onBarMidX()[.hidden] else { continue }
            hidden = MenuBarLayout.itemsInHiddenSpan(
                scanned,
                ownBundleID: own,
                hiddenDividerMidX: dividerX,
                alwaysHiddenDividerMidX: onBarMidX()[.alwaysHidden]
            )
            scansWithDivider += 1
            if !hidden.isEmpty || scansWithDivider >= 3 { break }
        }
        return hidden
    }

    private func scanNow() async -> [MenuBarItem] {
        let targets = MenuBarScanner.currentTargets()
        return await Task.detached(priority: .userInitiated) {
            MenuBarScanner.scan(targets)
        }.value
    }

    private func pressFromBar(_ item: MenuBarItem) {
        if !isHiddenSectionExpanded { collapseAfterPress = true }
        pressGeneration += 1
        let generation = pressGeneration
        pressTask?.cancel()
        pressTask = Task { await press(item, generation: generation) }
    }

    private func onBarID(_ item: MenuBarItem) -> String? {
        guard let y = item.positionY, y >= 0, y < 80 else { return nil }
        return item.id
    }

    /// Reveal the hidden copy and click that one. A namesake still on the menu bar is not clicked.
    private func press(_ item: MenuBarItem, generation: Int) async {
        if !isHiddenSectionExpanded { expand(trigger: .programmatic) }
        let own = Bundle.main.bundleIdentifier ?? "com.example.OpenBar"
        var target: MenuBarItem?
        for _ in 0..<16 {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled || generation != pressGeneration { return }
            guard let dividerX = onBarMidX()[.hidden] else { continue }
            let scanned = await scanNow()
            if Task.isCancelled || generation != pressGeneration { return }
            target = MenuBarLayout.pressTarget(
                for: item,
                in: scanned,
                ownBundleID: own,
                hiddenDividerMidX: dividerX,
                alwaysHiddenDividerMidX: onBarMidX()[.alwaysHidden]
            )
            if target != nil { break }
        }
        guard generation == pressGeneration else { return }
        guard let target else {
            logger.debug("Left the visible menu bar icon alone")
            finishPress(generation: generation)
            return
        }
        let before = MenuBarGeometry.overlayWindowIDs()
        await click(target)
        guard generation == pressGeneration else { return }
        let appear = Date().addingTimeInterval(1.5)
        while Date() < appear, !itemUIIsOpen(since: before) {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled || generation != pressGeneration { return }
        }
        let close = Date().addingTimeInterval(30)
        while Date() < close, itemUIIsOpen(since: before) {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled || generation != pressGeneration { return }
        }
        finishPress(generation: generation)
    }

    private func itemUIIsOpen(since before: Set<UInt32>) -> Bool {
        MenuBarGeometry.isMenuOpen() || !MenuBarGeometry.overlayWindowIDs().subtracting(before).isEmpty
    }

    private func finishPress(generation: Int) {
        guard generation == pressGeneration else { return }
        if collapseAfterPress {
            collapseAfterPress = false
            collapse()
        }
    }

    /// AX position is top-left, the same space `CGEvent` uses.
    private func click(_ item: MenuBarItem) async {
        guard let x = item.positionX, let y = item.positionY,
              let width = item.width, let height = item.height,
              width > 8, width <= 160, height > 8, height <= 40,
              y >= 0, y < 80
        else { return }
        let point = CGPoint(x: x + width / 2, y: y + height / 2)
        let saved = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { return }
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(40))
        up.post(tap: .cghidEventTap)
        if let saved { CGWarpMouseCursorPosition(saved) }
    }

    @objc private func toggleItemClicked(_ sender: NSStatusBarButton) {
        handleToggleClick()
    }

    /// Clicking a visible divider collapses everything.
    @objc private func dividerClicked(_ sender: NSStatusBarButton) {
        collapse()
    }

    private func showMenu() {
        let item = toggleItem.statusItem
        item.menu = makeMenu()
        item.button?.performClick(nil) // opens the menu synchronously
        item.menu = nil                // restore normal click handling
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let barTitle = hiddenBar.isVisible
            ? String(localized: "Hide Hidden Bar")
            : String(localized: "Show Hidden Bar")
        menu.addItem(item(barTitle, #selector(menuShowHiddenBar)))

        let toggleTitle = isHiddenSectionExpanded
            ? String(localized: "Collapse Hidden Section")
            : String(localized: "Expand Hidden Section")
        menu.addItem(item(toggleTitle, #selector(menuToggle)))

        let allTitle = isAlwaysHiddenSectionExpanded
            ? String(localized: "Hide All Icons")
            : String(localized: "Show All Icons (incl. Always-Hidden)")
        menu.addItem(item(allTitle, #selector(menuToggleAll)))

        menu.addItem(.separator())
        let repairTitle = MenuBarLayout.dividersOutOfOrder(onBarMidX())
            ? String(localized: "Repair Layout… (Out of Order)")
            : String(localized: "Repair Layout…")
        menu.addItem(item(repairTitle, #selector(menuRepair)))
        menu.addItem(item(String(localized: "How to Arrange Icons…"), #selector(menuOnboarding)))
        menu.addItem(item(String(localized: "Settings…"), #selector(menuSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit OpenBar"), #selector(menuQuit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func menuRepair() { repairLayout() }
    @objc private func menuShowHiddenBar() { toggleHiddenBar() }
    @objc private func menuToggle() { toggle(trigger: .toggleItem) }
    @objc private func menuToggleAll() { toggleAlwaysHidden(trigger: .toggleItem) }
    @objc private func menuSettings() { onOpenSettings?() }
    @objc private func menuOnboarding() { onOpenOnboarding?() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}

extension Notification.Name {
    static let openBarRepairLayout = Notification.Name("OpenBarRepairLayout")
}

@available(macOS 27.0, *)
extension MenuBarManager: NSStatusItemExpandedInterfaceDelegate {
    nonisolated func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        // AppKit calls this on the main thread. The parameters are not Sendable.
        nonisolated(unsafe) let statusItem = statusItem
        nonisolated(unsafe) let session = session
        MainActor.assumeIsolated {
            if statusItem === toggleItem.statusItem {
                handleToggleClick()
            } else {
                collapse()
            }
            // No panel under the icon. End the session or the menu bar swallows later clicks.
            session.cancel()
        }
    }

    nonisolated func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {}
}
