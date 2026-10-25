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

/// Turns raw mouse events into "show on click", "show on hover" and
/// "collapse when the mouse leaves" behaviors.
@MainActor
final class MenuBarEventHandler {
    private weak var manager: MenuBarManager?
    private let settings: AppSettings
    private var monitors: [GlobalEventMonitor] = []

    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?

    /// Grace period before a hover-triggered expansion collapses after the
    /// pointer leaves the menu bar (lets the user move diagonally).
    private let leaveGracePeriod: Double = 0.5

    init(manager: MenuBarManager, settings: AppSettings) {
        self.manager = manager
        self.settings = settings
    }

    func start() {
        guard monitors.isEmpty else { return }
        monitors = [
            GlobalEventMonitor(mask: [.leftMouseDown]) { [weak self] event in
                self?.handleMouseDown(event)
            },
            GlobalEventMonitor(mask: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                self?.handleMouseMoved(event)
            },
        ]
        monitors.forEach { $0.start() }
    }

    func stop() {
        monitors.forEach { $0.stop() }
        monitors.removeAll()
        hoverTask?.cancel()
        leaveTask?.cancel()
    }

    // MARK: - Click

    private func handleMouseDown(_ event: NSEvent) {
        guard let manager else { return }
        let location = NSEvent.mouseLocation
        guard MenuBarGeometry.isMouseInMenuBar(location) else { return }

        if settings.showOnClickEmptyArea,
           MenuBarGeometry.isEmptyMenuBarSpace(at: location) {
            hoverTask?.cancel()
            hoverTask = nil
            manager.toggle(trigger: .emptyAreaClick)
            return
        }

        // Any other click in the menu bar while expanded = user is working
        // with the revealed icons; restart the auto-collapse countdown.
        if manager.isHiddenSectionExpanded {
            manager.scheduleAutoCollapse()
        }
    }

    // MARK: - Hover

    private func handleMouseMoved(_ event: NSEvent) {
        guard let manager else { return }
        let location = NSEvent.mouseLocation
        let inMenuBar = MenuBarGeometry.isMouseInMenuBar(location)

        updateHover(manager: manager, location: location, inMenuBar: inMenuBar)
        updateLeave(manager: manager, inMenuBar: inMenuBar)
    }

    private func updateHover(manager: MenuBarManager, location: NSPoint, inMenuBar: Bool) {
        // Cheap checks first; `isEmptyMenuBarSpace` queries the window list.
        let shouldArm = settings.showOnHover
            && !manager.isHiddenSectionExpanded
            && inMenuBar
            && MenuBarGeometry.isEmptyMenuBarSpace(at: location)

        guard shouldArm else {
            hoverTask?.cancel()
            hoverTask = nil
            return
        }
        guard hoverTask == nil else { return } // already counting down

        let delay = max(0, settings.hoverDelay)
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.hoverTask = nil
            guard let manager = self.manager,
                  !manager.isHiddenSectionExpanded,
                  MenuBarGeometry.isEmptyMenuBarSpace(at: NSEvent.mouseLocation)
            else { return }
            manager.expand(trigger: .hover)
        }
    }

    // MARK: - Leave

    private func updateLeave(manager: MenuBarManager, inMenuBar: Bool) {
        let applies = settings.collapseWhenMouseLeaves
            && manager.isHiddenSectionExpanded
            && manager.lastExpansionTrigger == .hover

        guard applies, !inMenuBar else {
            leaveTask?.cancel()
            leaveTask = nil
            return
        }
        guard leaveTask == nil else { return }

        let grace = leaveGracePeriod
        leaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(grace))
            guard !Task.isCancelled, let self else { return }
            self.leaveTask = nil
            guard let manager = self.manager,
                  manager.isHiddenSectionExpanded,
                  !MenuBarGeometry.isMouseInMenuBar(),
                  !MenuBarGeometry.isMenuOpen() // user is inside a revealed item's menu
            else { return }
            manager.collapse()
        }
    }
}
