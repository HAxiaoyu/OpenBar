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
    /// Heuristic (v0.1, no permissions): the point must be
    ///   1. inside the menu bar,
    ///   2. right of the notch on notched displays, or right of the screen's
    ///      midpoint otherwise (where app menus normally end), and
    ///   3. not over any status-item window.
    /// TODO(v0.2): with Accessibility permission, read the frontmost app's
    /// menu bar item frames via AX to replace rule 2 with an exact check.
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
    static func isMenuOpen() -> Bool {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return onScreenWindows().contains { $0.layer == menuLevel }
    }

    // MARK: - Private

    private struct WindowInfo {
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
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            return WindowInfo(layer: layer, bounds: bounds)
        }
    }

    /// Converts an AppKit global point (origin bottom-left of the primary
    /// screen) to a CoreGraphics global point (origin top-left).
    private static func cgPoint(from point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
