//
//  OpenBar — an open-source menu bar manager for macOS.
//  Copyright (C) 2026 OpenBar contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version. See the LICENSE file for details.
//

import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Toggle the Hidden section. No default — the user records one in Settings.
    static let toggleHiddenSection = Self("toggleHiddenSection")
    /// Toggle everything, including the Always-Hidden section.
    static let toggleAllSections = Self("toggleAllSections")
}

/// Registers global hotkeys. KeyboardShortcuts uses Carbon `RegisterEventHotKey`,
/// which works without Accessibility permission and persists the chosen
/// shortcuts in UserDefaults on its own.
@MainActor
final class HotkeyController {
    init(manager: MenuBarManager) {
        KeyboardShortcuts.onKeyUp(for: .toggleHiddenSection) { [weak manager] in
            manager?.toggle(trigger: .hotkey)
        }
        KeyboardShortcuts.onKeyUp(for: .toggleAllSections) { [weak manager] in
            manager?.toggleAlwaysHidden(trigger: .hotkey)
        }
    }
}
