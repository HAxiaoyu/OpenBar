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

// Entry point. We use an explicit AppKit lifecycle (instead of a SwiftUI `App`)
// because OpenBar is a pure menu bar agent (LSUIElement) and manages its own
// windows (Settings, Onboarding) through `WindowPresenter`.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // LSUIElement already hides the Dock icon; this makes it explicit in case
    // the Info.plist key is ever lost.
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
