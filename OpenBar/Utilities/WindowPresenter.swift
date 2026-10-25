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

/// Hosts SwiftUI views in plain `NSWindow`s.
///
/// A menu-bar-only (LSUIElement) app cannot reliably open a SwiftUI `Settings`
/// scene from AppKit code on macOS 14+, so we manage our own windows.
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]

    func present<Content: View>(
        id: String,
        title: String,
        size: NSSize,
        @ViewBuilder content: () -> Content
    ) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content())
        window.setContentSize(size)
        window.delegate = self
        window.center()

        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close(id: String) {
        windows[id]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        windows[id] = nil
    }
}
