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
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let windowPresenter = WindowPresenter()
    private var menuBarManager: MenuBarManager?
    private var eventHandler: MenuBarEventHandler?
    private var hotkeys: HotkeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = MenuBarManager(settings: settings)
        manager.onOpenSettings = { [weak self] in self?.showSettings() }
        manager.onOpenOnboarding = { [weak self] in self?.showOnboarding() }
        menuBarManager = manager

        let handler = MenuBarEventHandler(manager: manager, settings: settings)
        handler.start()
        eventHandler = handler

        hotkeys = HotkeyController(manager: manager)

        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventHandler?.stop()
        // Leave everything visible on quit so the user never "loses" icons
        // that were pushed off-screen by a collapsed divider.
        menuBarManager?.expand(trigger: .programmatic, includingAlwaysHidden: true)
    }

    /// Re-opening the app (e.g. double-clicking it in Finder while it is
    /// already running) opens Settings, since there is no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: - Windows

    func showSettings() {
        windowPresenter.present(
            id: "settings",
            title: String(localized: "OpenBar Settings"),
            size: NSSize(width: 560, height: 520)
        ) {
            SettingsView(settings: AppSettings.shared)
        }
    }

    func showOnboarding() {
        // Expand so the dividers are visible while the user reads the guide
        // and starts ⌘-dragging icons around them.
        menuBarManager?.expand(trigger: .programmatic, includingAlwaysHidden: true)
        windowPresenter.present(
            id: "onboarding",
            title: String(localized: "Welcome to OpenBar"),
            size: NSSize(width: 560, height: 520)
        ) {
            OnboardingView { [windowPresenter] in
                AppSettings.shared.hasCompletedOnboarding = true
                windowPresenter.close(id: "onboarding")
            }
        }
    }
}
