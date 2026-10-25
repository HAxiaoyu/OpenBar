//
//  OpenBar — an open-source menu bar manager for macOS.
//  Copyright (C) 2026 OpenBar contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version. See the LICENSE file for details.
//

import ApplicationServices
import AppKit
import CoreGraphics

/// Read-only walk of status items. Does not press or move anything.
enum MenuBarScanner {
    struct Target: Sendable {
        var pid: pid_t
        var bundleID: String
    }

    private static let hostBundleIDs: Set<String> = [
        "com.apple.MenuBarAgent",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
    ]

    private static let itemRoles: Set<String> = [
        "AXMenuBarItem", "AXButton", "AXMenuButton", "AXCheckBox", "AXPopUpButton",
    ]

    /// Processes to scan. Includes menu-bar hosts that are not normal apps.
    @MainActor
    static func currentTargets() -> [Target] {
        var seen = Set<pid_t>()
        var targets: [Target] = []
        func add(_ app: NSRunningApplication) {
            let pid = app.processIdentifier
            guard pid > 0, seen.insert(pid).inserted else { return }
            targets.append(Target(pid: pid, bundleID: app.bundleIdentifier ?? "pid:\(pid)"))
        }
        NSWorkspace.shared.runningApplications.forEach(add)
        for id in hostBundleIDs {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach(add)
        }
        return targets
    }

    /// Safe to call off the main actor. Returns nothing when Accessibility is denied.
    static func scan(_ targets: [Target]) -> [MenuBarItem] {
        let hits = assignOrdinals(dedupe(collect(targets)))
        return items(from: hits, windows: statusWindows())
    }

    private static func collect(_ targets: [Target]) -> [RawHit] {
        guard AXIsProcessTrusted() else { return [] }
        var raw: [RawHit] = []
        for target in targets {
            let app = AXUIElementCreateApplication(target.pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            if let extras = element(app, kAXExtrasMenuBarAttribute as CFString) {
                walk(extras, bundleID: target.bundleID, depth: 0, menuBarBandOnly: false, into: &raw)
            }
            // The app menu bar is File/Edit/Window/Help. Status items live on
            // AXExtrasMenuBar. Some third-party icons are only buttons inside
            // a menu-bar host window (their name is AXHelp).
            if hostBundleIDs.contains(target.bundleID) {
                for child in children(of: app) where attributes(of: child).role == "AXWindow" {
                    walk(child, bundleID: target.bundleID, depth: 0, menuBarBandOnly: true, into: &raw)
                }
            }
        }
        return raw
    }

    // MARK: - Walk

    private struct RawHit {
        var bundleID: String
        var axIdentifier: String
        var title: String
        var label: String
        var ordinal = 0
        var position: CGPoint?
        var size: CGSize?

        var stableID: String {
            MenuBarItem.stableID(
                bundleID: bundleID,
                axIdentifier: axIdentifier,
                title: title,
                ordinal: ordinal
            )
        }
    }

    /// `menuBarBandOnly`: keep buttons that actually sit in the menu bar, so a
    /// host app's ordinary windows are ignored.
    private static func walk(
        _ element: AXUIElement,
        bundleID: String,
        depth: Int,
        menuBarBandOnly: Bool,
        into hits: inout [RawHit]
    ) {
        guard depth <= 4 else { return }
        let values = attributes(of: element)
        if depth > 0, itemRoles.contains(values.role) {
            let label = firstText(values.label, firstText(values.description, values.help))
            let title = firstText(values.title, label)
            let inBand = !menuBarBandOnly || isInMenuBarBand(values.position, values.size)
            if inBand, !label.isEmpty || !title.isEmpty || !values.identifier.isEmpty {
                hits.append(RawHit(
                    bundleID: bundleID,
                    axIdentifier: values.identifier,
                    title: title,
                    label: label,
                    position: values.position,
                    size: values.size
                ))
            }
        }
        guard depth < 4 else { return }
        for child in children(of: element) {
            walk(child, bundleID: bundleID, depth: depth + 1, menuBarBandOnly: menuBarBandOnly, into: &hits)
        }
    }

    private static func isInMenuBarBand(_ position: CGPoint?, _ size: CGSize?) -> Bool {
        guard let position, let size else { return false }
        return position.y >= 0 && position.y < 80 && size.height > 0 && size.height <= 40
    }

    private static func dedupe(_ hits: [RawHit]) -> [RawHit] {
        var kept: [RawHit] = []
        for hit in hits {
            if let index = kept.firstIndex(where: { samePlace($0, hit) }) {
                if hostBundleIDs.contains(kept[index].bundleID), !hostBundleIDs.contains(hit.bundleID) {
                    kept[index] = hit
                }
            } else {
                kept.append(hit)
            }
        }
        return kept
    }

    private static func samePlace(_ a: RawHit, _ b: RawHit) -> Bool {
        guard let ap = a.position, let bp = b.position else { return false }
        return abs(ap.x - bp.x) <= 5 && abs(ap.y - bp.y) <= 5
    }

    private static func assignOrdinals(_ hits: [RawHit]) -> [RawHit] {
        var counts: [String: Int] = [:]
        return hits.map { hit in
            var hit = hit
            let key = "\(hit.bundleID)\u{1f}\(hit.axIdentifier)\u{1f}\(hit.title)"
            let ordinal = counts[key, default: 0]
            counts[key] = ordinal + 1
            hit.ordinal = ordinal
            return hit
        }
    }

    private static func items(from hits: [RawHit], windows: [StatusWindow]) -> [MenuBarItem] {
        hits.map { hit in
            MenuBarItem(
                id: hit.stableID,
                bundleID: hit.bundleID,
                axIdentifier: hit.axIdentifier,
                title: hit.title,
                label: hit.label,
                ordinal: hit.ordinal,
                positionX: hit.position.map { Double($0.x) },
                positionY: hit.position.map { Double($0.y) },
                width: hit.size.map { Double($0.width) },
                height: hit.size.map { Double($0.height) },
                windowID: matchWindow(hit, windows: windows),
                missingSince: nil
            )
        }
    }

    // MARK: - Windows

    private struct StatusWindow {
        var id: CGWindowID
        var bounds: CGRect
    }

    /// Status-layer windows no wider than 400pt. Matched frames must agree within 5pt.
    private static func statusWindows() -> [StatusWindow] {
        let level = Int(CGWindowLevelForKey(.statusWindow))
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == level,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width <= 400, bounds.width > 0
            else { return nil }
            return StatusWindow(id: CGWindowID(number), bounds: bounds)
        }
    }

    private static func matchWindow(_ hit: RawHit, windows: [StatusWindow]) -> UInt32? {
        guard let origin = hit.position, let size = hit.size, size.width <= 400 else { return nil }
        let frame = CGRect(origin: origin, size: size)
        let match = windows.min { error($0.bounds, frame) < error($1.bounds, frame) }
        guard let match, error(match.bounds, frame) <= 5 else { return nil }
        return match.id
    }

    private static func error(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height))
    }

    // MARK: - AX

    private struct Attributes {
        var role = ""
        var label = ""
        var description = ""
        var title = ""
        var help = ""
        var identifier = ""
        var position: CGPoint?
        var size: CGSize?
    }

    private static func attributes(of element: AXUIElement) -> Attributes {
        let names = ["AXRole", "AXLabel", "AXDescription", "AXTitle", "AXHelp", "AXIdentifier", "AXPosition", "AXSize"] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, [], &values) == .success,
              let values = values as? [Any], values.count == 8
        else { return Attributes() }
        return Attributes(
            role: text(values[0]),
            label: text(values[1]),
            description: text(values[2]),
            title: text(values[3]),
            help: text(values[4]),
            identifier: text(values[5]),
            position: point(values[6]),
            size: size(values[7])
        )
    }

    private static func text(_ value: Any) -> String {
        value as? String ?? ""
    }

    private static func point(_ value: Any) -> CGPoint? {
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetType(ax) == .cgPoint, AXValueGetValue(ax, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(_ value: Any) -> CGSize? {
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetType(ax) == .cgSize, AXValueGetValue(ax, .cgSize, &size) else { return nil }
        return size
    }

    private static func element(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func firstText(_ a: String, _ b: String) -> String {
        a.isEmpty ? b : a
    }
}
