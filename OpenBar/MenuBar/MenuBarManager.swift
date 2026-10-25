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

    // Creation order matters on first launch: each new status item is placed
    // to the left of existing ones, which (together with the seeded preferred
    // positions) yields [alwaysHidden][hidden][toggle].
    private let toggleItem: ControlItem
    private let hiddenDivider: ControlItem
    private let alwaysHiddenDivider: ControlItem

    private(set) var isHiddenSectionExpanded = false
    private(set) var isAlwaysHiddenSectionExpanded = false
    private(set) var lastExpansionTrigger: Trigger?

    var onOpenSettings: (() -> Void)?
    var onOpenOnboarding: (() -> Void)?

    private var autoCollapseTask: Task<Void, Never>?
    private var settingsObserver: NSObjectProtocol?

    init(settings: AppSettings) {
        self.settings = settings
        toggleItem = ControlItem(role: .toggle)
        hiddenDivider = ControlItem(role: .hidden)
        alwaysHiddenDivider = ControlItem(role: .alwaysHidden)
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

        // Start collapsed: that's the point of the app.
        applyState()
    }

    // MARK: - Public API

    func expand(trigger: Trigger, includingAlwaysHidden: Bool = false) {
        isHiddenSectionExpanded = true
        if includingAlwaysHidden {
            isAlwaysHiddenSectionExpanded = true
        }
        lastExpansionTrigger = trigger
        applyState()
        scheduleAutoCollapse()
    }

    func collapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        isHiddenSectionExpanded = false
        isAlwaysHiddenSectionExpanded = false
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
        toggleItem.setToggleAppearance(expanded: isHiddenSectionExpanded)
        hiddenDivider.setDivider(expanded: isHiddenSectionExpanded, showsGlyph: showsGlyph)
        alwaysHiddenDivider.setDivider(
            expanded: isHiddenSectionExpanded && isAlwaysHiddenSectionExpanded,
            showsGlyph: showsGlyph
        )
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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        for divider in [hiddenDivider, alwaysHiddenDivider] {
            divider.statusItem.button?.target = self
            divider.statusItem.button?.action = #selector(dividerClicked(_:))
        }
    }

    @objc private func toggleItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let flags = event?.modifierFlags ?? []
        if event?.type == .rightMouseUp || flags.contains(.control) {
            showMenu()
        } else if flags.contains(.option) {
            toggleAlwaysHidden(trigger: .toggleItem)
        } else {
            toggle(trigger: .toggleItem)
        }
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

        let toggleTitle = isHiddenSectionExpanded
            ? String(localized: "Hide Icons")
            : String(localized: "Show Hidden Icons")
        menu.addItem(item(toggleTitle, #selector(menuToggle)))

        let allTitle = isAlwaysHiddenSectionExpanded
            ? String(localized: "Hide All Icons")
            : String(localized: "Show All Icons (incl. Always-Hidden)")
        menu.addItem(item(allTitle, #selector(menuToggleAll)))

        menu.addItem(.separator())
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

    @objc private func menuToggle() { toggle(trigger: .toggleItem) }
    @objc private func menuToggleAll() { toggleAlwaysHidden(trigger: .toggleItem) }
    @objc private func menuSettings() { onOpenSettings?() }
    @objc private func menuOnboarding() { onOpenOnboarding?() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
