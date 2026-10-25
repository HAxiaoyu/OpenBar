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
import CoreGraphics

/// Permission-free geometry helpers for the menu bar.
///
/// Uses `CGWindowListCopyWindowInfo` only for window *bounds* and *layers*,
/// which do not require Screen Recording permission (window titles would).
@MainActor
enum MenuBarGeometry {
    /// Height of the menu bar on `screen` (taller on notched displays).
    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        return max(NSStatusBar.system.thickness, reserved)
    }

    /// The menu bar's frame on `screen`, in AppKit (bottom-left origin) coordinates.
    static func menuBarFrame(on screen: NSScreen) -> NSRect {
        let height = menuBarHeight(on: screen)
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                      width: screen.frame.width, height: height)
    }

    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    static func isMouseInMenuBar(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = screen(containing: location) else { return false }
        return NSMouseInRect(location, menuBarFrame(on: screen), false)
    }

    /// `true` if `location` is on a part of the menu bar that holds neither an
    /// app menu nor a status item.
    ///
    /// Heuristic (permission-free). The point must be
    ///   1. inside the menu bar,
    ///   2. right of the notch on notched displays, or right of that screen's
    ///      midpoint otherwise, and
    ///   3. not over any status-item window.
    ///
    /// Limits: a very wide app menu is treated as empty space; each display
    /// uses its own frame, including one without a notch. The menu bar's own
    /// window sits at main-menu level, so that level is not "a menu is open".
    /// Phase 1 replaces rule 2 with Accessibility frames (see ROADMAP.md).
    static func isEmptyMenuBarSpace(at location: NSPoint) -> Bool {
        guard let screen = screen(containing: location),
              NSMouseInRect(location, menuBarFrame(on: screen), false)
        else { return false }

        let minX: CGFloat
        if let rightOfNotch = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            minX = screen.frame.maxX - rightOfNotch.width
        } else {
            minX = screen.frame.midX
        }
        guard location.x >= minX else { return false }

        let point = cgPoint(from: location)
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return !onScreenWindows().contains { window in
            window.layer == statusLevel && window.bounds.contains(point)
        }
    }

    /// `true` while any app (including ours) shows a menu — e.g. the user
    /// clicked a revealed status item and its menu is open.
    ///
    /// Popup windows cover other apps. `NSMenu` tracking covers our own menu
    /// when the window list has not caught up yet. Torn-off menu level is the
    /// same as floating windows, so it is not used here.
    static func isMenuOpen() -> Bool {
        if menuTrackingDepth > 0 { return true }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return onScreenWindows().contains { $0.layer == menuLevel }
    }

    /// Windows above the menu bar, such as a status item's panel.
    /// The cursor and other system overlays sit at extreme levels and are ignored.
    static func overlayWindowIDs() -> Set<UInt32> {
        let status = Int(CGWindowLevelForKey(.statusWindow))
        return Set(onScreenWindows().compactMap { window in
            guard window.layer > status, window.layer < 2000,
                  window.bounds.width >= 40, window.bounds.height >= 20
            else { return nil }
            return window.id
        })
    }

    static func startMenuTrackingWatch() {
        guard !menuTrackingStarted else { return }
        menuTrackingStarted = true
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { menuTrackingDepth += 1 }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { menuTrackingDepth = max(0, menuTrackingDepth - 1) }
        }
    }

    // MARK: - Private

    private static var menuTrackingDepth = 0
    private static var menuTrackingStarted = false

    private struct WindowInfo {
        let id: UInt32
        let layer: Int
        /// CoreGraphics global coordinates (top-left origin).
        let bounds: CGRect
    }

    private static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            return WindowInfo(id: UInt32(number), layer: layer, bounds: bounds)
        }
    }

    /// Converts an AppKit global point (origin bottom-left of the primary
    /// screen) to a CoreGraphics global point (origin top-left).
    private static func cgPoint(from point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
