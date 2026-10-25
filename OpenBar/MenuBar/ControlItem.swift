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
/// Hiding works with the well-known "separator length" technique: a divider's
/// `length` is set to a huge value, so it — and every status item to its left —
/// no longer fits in the menu bar and macOS stops drawing them. Showing sets the
/// length back to a small value. No Accessibility or Screen Recording
/// permission is required.
@MainActor
final class ControlItem {
    enum Role: String, CaseIterable {
        /// OpenBar's own icon. Always visible; click to expand/collapse.
        case toggle
        /// Divider: icons to its left (up to `.alwaysHidden`) form the Hidden section.
        case hidden
        /// Divider: icons to its left form the Always-Hidden section.
        case alwaysHidden

        /// Stable name so macOS remembers the item's position across launches.
        var autosaveName: String { "OpenBar_\(rawValue)" }

        /// Seed position used the very first time the item is created. Smaller
        /// numbers sit further right, so this yields `[alwaysHidden][hidden][toggle]`.
        var initialPreferredPosition: Double {
            switch self {
            case .toggle: 0
            case .hidden: 1
            case .alwaysHidden: 2
            }
        }
    }

    /// Length used to push the divider (and everything left of it) off-screen.
    /// Must exceed the widest menu bar of any connected display.
    static let collapsedLength: CGFloat = 10_000

    let role: Role
    let statusItem: NSStatusItem

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

    /// Expand or collapse a divider.
    func setDivider(expanded: Bool, showsGlyph: Bool) {
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
        } else {
            // Clear the image so nothing can flash in while the length animates.
            button.image = nil
            button.isEnabled = false
            statusItem.length = Self.collapsedLength
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
