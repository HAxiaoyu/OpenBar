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

/// Wraps `NSEvent.addGlobalMonitorForEvents`.
///
/// Global monitors receive copies of events sent to *other* apps. Mouse events
/// don't need any permission; key events would need Accessibility, which is
/// why the hotkey uses KeyboardShortcuts (Carbon hot keys) instead.
@MainActor
final class GlobalEventMonitor {
    private let mask: NSEvent.EventTypeMask
    private let handler: @MainActor (NSEvent) -> Void
    private var token: Any?

    init(mask: NSEvent.EventTypeMask, handler: @escaping @MainActor (NSEvent) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    func start() {
        guard token == nil else { return }
        let handler = self.handler
        token = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            // AppKit delivers monitor callbacks on the main thread.
            MainActor.assumeIsolated {
                handler(event)
            }
        }
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }
}
