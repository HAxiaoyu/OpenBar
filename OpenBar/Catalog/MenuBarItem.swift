//
//  OpenBar — an open-source menu bar manager for macOS.
//  Copyright (C) 2026 OpenBar contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version. See the LICENSE file for details.
//

import Foundation

/// One menu-bar status item observed via Accessibility.
///
/// `id` is stable across relaunch. `windowID` is only valid for the current
/// session and is not part of the id.
struct MenuBarItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var bundleID: String
    var axIdentifier: String
    var title: String
    var label: String
    var ordinal: Int
    var positionX: Double?
    var positionY: Double?
    var width: Double?
    var height: Double?
    var windowID: UInt32?
    /// Set when a later scan no longer sees this id. Cleared if it returns.
    var missingSince: Date?

    var displayName: String {
        if !label.isEmpty { return label }
        if !title.isEmpty { return title }
        if !axIdentifier.isEmpty { return axIdentifier }
        return bundleID
    }

    static func stableID(bundleID: String, axIdentifier: String, title: String, ordinal: Int) -> String {
        [bundleID, axIdentifier, title, String(ordinal)].joined(separator: "\u{1f}")
    }

    static func assertIdentityRules() {
        let first = stableID(bundleID: "b", axIdentifier: "i", title: "t", ordinal: 0)
        let second = stableID(bundleID: "b", axIdentifier: "i", title: "t", ordinal: 1)
        assert(first != second)
        assert(first == stableID(bundleID: "b", axIdentifier: "i", title: "t", ordinal: 0))
    }
}
