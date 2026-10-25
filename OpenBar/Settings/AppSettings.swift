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
import Observation

/// All user-facing preferences, persisted to `UserDefaults`.
///
/// Observable so SwiftUI views can bind to it directly; AppKit code simply
/// reads the current values at the moment it needs them, and listens to
/// `AppSettings.didChangeNotification` for changes that need re-applying.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    static let didChangeNotification = Notification.Name("OpenBarSettingsDidChange")

    private enum Key {
        static let showOnClickEmptyArea = "showOnClickEmptyArea"
        static let showOnHover = "showOnHover"
        static let hoverDelay = "hoverDelay"
        static let autoCollapseEnabled = "autoCollapseEnabled"
        static let autoCollapseDelay = "autoCollapseDelay"
        static let collapseWhenMouseLeaves = "collapseWhenMouseLeaves"
        static let showSectionDividers = "showSectionDividers"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Behavior

    /// Expand the hidden section when the user clicks an empty part of the menu bar.
    var showOnClickEmptyArea: Bool {
        didSet { save(showOnClickEmptyArea, Key.showOnClickEmptyArea) }
    }

    /// Expand the hidden section when the pointer rests on an empty part of the menu bar.
    var showOnHover: Bool {
        didSet { save(showOnHover, Key.showOnHover) }
    }

    /// Seconds the pointer must rest before a hover expands the section.
    var hoverDelay: Double {
        didSet { save(hoverDelay, Key.hoverDelay) }
    }

    /// Automatically collapse after `autoCollapseDelay` seconds.
    var autoCollapseEnabled: Bool {
        didSet { save(autoCollapseEnabled, Key.autoCollapseEnabled) }
    }

    var autoCollapseDelay: Double {
        didSet { save(autoCollapseDelay, Key.autoCollapseDelay) }
    }

    /// Collapse as soon as the pointer leaves the menu bar (only for hover-triggered expansions).
    var collapseWhenMouseLeaves: Bool {
        didSet { save(collapseWhenMouseLeaves, Key.collapseWhenMouseLeaves) }
    }

    // MARK: Appearance

    /// Draw thin divider glyphs where the sections begin while expanded.
    var showSectionDividers: Bool {
        didSet { save(showSectionDividers, Key.showSectionDividers) }
    }

    // MARK: State

    var hasCompletedOnboarding: Bool {
        didSet { save(hasCompletedOnboarding, Key.hasCompletedOnboarding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showOnClickEmptyArea: true,
            Key.showOnHover: false,
            Key.hoverDelay: 0.3,
            Key.autoCollapseEnabled: true,
            Key.autoCollapseDelay: 15.0,
            Key.collapseWhenMouseLeaves: true,
            Key.showSectionDividers: true,
            Key.hasCompletedOnboarding: false,
        ])
        showOnClickEmptyArea = defaults.bool(forKey: Key.showOnClickEmptyArea)
        showOnHover = defaults.bool(forKey: Key.showOnHover)
        hoverDelay = defaults.double(forKey: Key.hoverDelay)
        autoCollapseEnabled = defaults.bool(forKey: Key.autoCollapseEnabled)
        autoCollapseDelay = defaults.double(forKey: Key.autoCollapseDelay)
        collapseWhenMouseLeaves = defaults.bool(forKey: Key.collapseWhenMouseLeaves)
        showSectionDividers = defaults.bool(forKey: Key.showSectionDividers)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
