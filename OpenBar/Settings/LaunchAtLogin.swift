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
import OSLog
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` (macOS 13+).
///
/// The system — not UserDefaults — is the source of truth here, because the
/// user can also toggle the login item in System Settings › General › Login Items.
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: "OpenBar", category: "LaunchAtLogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `true` when the user must approve the item in System Settings.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status != .notRegistered else { return }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
