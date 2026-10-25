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

/// One of OpenBar's own `NSStatusItem`s.
///
/// Layout, left → right, once the user has arranged things:
///
///     [always-hidden icons] ┃ [hidden icons] │ [visible icons] ‹OpenBar›   [Control Center, clock]
///                           ↑                ↑                  ↑
///                  .alwaysHidden          .hidden            .toggle
///
/// Hiding works with the separator-length technique: a divider's `length`
/// grows until items to its left no longer fit. On macOS 27 a length past the
/// status area is dropped from the layout and hides nothing, so the caller
/// passes a length that still fits. No Accessibility permission is required.
@MainActor
final class ControlItem {
    enum Role: String, CaseIterable {
        /// OpenBar's own icon. Always visible; click to show the hidden bar.
        case toggle
        /// Divider: icons to its left (up to `.alwaysHidden`) form the Hidden section.
        case hidden
        /// Divider: icons to its left form the Always-Hidden section.
        case alwaysHidden

        /// Stable name so macOS remembers the item's position across launches.
        var autosaveName: String { "OpenBar_v6_\(rawValue)" }

        /// Where the item wants to sit. On macOS 27 a smaller value sits further
        /// right, and 0 is the default slot on the left, so these stay in the
        /// hundreds. Before macOS 27, smaller sat further right as 0, 1, 2.
        var initialPreferredPosition: Double {
            if #available(macOS 27, *) {
                switch self {
                case .alwaysHidden: 400
                case .hidden: 180
                case .toggle: 80
                }
            } else {
                switch self {
                case .toggle: 0
                case .hidden: 1
                case .alwaysHidden: 2
                }
            }
        }

        /// Left to right. This is the only order in which the sections work.
        static let leftToRight: [Role] = [.alwaysHidden, .hidden, .toggle]
    }

    /// Length used to push the divider (and everything left of it) off-screen.
    /// Must exceed the widest menu bar of any connected display.
    static let collapsedLength: CGFloat = 10_000

    let role: Role
    private(set) var statusItem: NSStatusItem

    private(set) var isExpanded = true

    init(role: Role) {
        self.role = role
        Self.seedDefaultsIfNeeded(for: role)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = role.autosaveName
        // Users may ⌘-drag our items to reposition them, but never remove them
        // (removing a divider would make hidden icons unreachable).
        statusItem.behavior = []
        statusItem.isVisible = true
        configureButton()
    }

    func removeFromStatusBar() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Drop the current item and create a new one at `initialPreferredPosition`.
    /// Overwrites a position the user (or AppKit) previously saved.
    func installAtPreferredPosition() {
        let defaults = UserDefaults.standard
        defaults.set(role.initialPreferredPosition, forKey: "NSStatusItem Preferred Position \(role.autosaveName)")
        defaults.set(true, forKey: "NSStatusItem Visible \(role.autosaveName)")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = role.autosaveName
        item.behavior = []
        item.isVisible = true
        statusItem = item
        configureButton()
    }

    // MARK: - State

    /// Update the toggle icon's glyph to reflect the hidden section's state.
    func setToggleAppearance(expanded: Bool) {
        precondition(role == .toggle)
        isExpanded = expanded
        guard let button = statusItem.button else { return }
        let symbol = expanded ? "chevron.compact.right" : "chevron.compact.left"
        let description = expanded
            ? String(localized: "Hide menu bar icons")
            : String(localized: "Show hidden menu bar icons")
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(config)
        button.image?.isTemplate = true
        button.toolTip = description
    }

    /// Expand or collapse a divider. `collapsedLength` has to stay in the menu
    /// bar; a longer value is removed from the layout and hides nothing.
    func setDivider(expanded: Bool, showsGlyph: Bool, collapsedLength: CGFloat = ControlItem.collapsedLength) {
        precondition(role != .toggle)
        isExpanded = expanded
        guard let button = statusItem.button else { return }
        if expanded {
            if showsGlyph {
                button.image = Self.dividerImage(for: role)
                statusItem.length = NSStatusItem.variableLength
            } else {
                button.image = nil
                statusItem.length = 0
            }
            button.isEnabled = true
            button.alphaValue = 1
        } else {
            button.image = nil
            button.isEnabled = false
            button.alphaValue = 0
            statusItem.length = collapsedLength
        }
    }

    // MARK: - Private

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        switch role {
        case .toggle:
            button.setAccessibilityLabel("OpenBar")
            setToggleAppearance(expanded: true)
        case .hidden:
            button.setAccessibilityLabel(String(localized: "OpenBar hidden section divider"))
            button.toolTip = String(localized: "Icons left of this line are hidden. ⌘-drag icons to move them.")
            button.image = Self.dividerImage(for: role)
        case .alwaysHidden:
            button.setAccessibilityLabel(String(localized: "OpenBar always-hidden section divider"))
            button.toolTip = String(localized: "Icons left of this line are always hidden. ⌘-drag icons to move them.")
            button.image = Self.dividerImage(for: role)
        }
    }

    /// Seeds macOS's per-item status bar defaults the first time we run, so
    /// the three items start out next to each other in the right order.
    /// These keys are read by AppKit when `autosaveName` is assigned.
    private static func seedDefaultsIfNeeded(for role: Role) {
        let defaults = UserDefaults.standard
        let positionKey = "NSStatusItem Preferred Position \(role.autosaveName)"
        if #available(macOS 27, *) {
            // A bad seed put the chevron on the left of the divider. Put the
            // three controls back on the smaller-is-righter axis, once.
            let migratedKey = "OpenBar.macOS27PositionOrder"
            if defaults.integer(forKey: migratedKey) < 2 {
                defaults.set(role.initialPreferredPosition, forKey: positionKey)
                if role == .toggle {
                    defaults.set(2, forKey: migratedKey)
                }
            }
        }
        if defaults.object(forKey: positionKey) == nil {
            defaults.set(role.initialPreferredPosition, forKey: positionKey)
        }
        // Make sure a previously hidden item comes back.
        defaults.set(true, forKey: "NSStatusItem Visible \(role.autosaveName)")
    }

    /// A thin vertical bar (single for Hidden, double for Always-Hidden).
    /// `nonisolated` so the drawing closure is not main-actor isolated —
    /// AppKit may invoke it during rendering.
    private nonisolated static func dividerImage(for role: Role) -> NSImage {
        let isDouble = role == .alwaysHidden
        let size = NSSize(width: isDouble ? 7 : 4, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let lineWidth: CGFloat = 1.5
            let inset: CGFloat = 2
            let height = rect.height - inset * 2
            if isDouble {
                NSBezierPath(roundedRect: NSRect(x: 1, y: inset, width: lineWidth, height: height),
                             xRadius: lineWidth / 2, yRadius: lineWidth / 2).fill()
                NSBezierPath(roundedRect: NSRect(x: rect.width - 1 - lineWidth, y: inset, width: lineWidth, height: height),
                             xRadius: lineWidth / 2, yRadius: lineWidth / 2).fill()
            } else {
                NSBezierPath(roundedRect: NSRect(x: (rect.width - lineWidth) / 2, y: inset, width: lineWidth, height: height),
                             xRadius: lineWidth / 2, yRadius: lineWidth / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
