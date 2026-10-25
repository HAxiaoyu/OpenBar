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

/// The capsule of hidden icons that sits just under the menu bar.
@MainActor
final class HiddenItemsBar: NSObject {
    private var panel: NSPanel?
    private var shownItems: [MenuBarItem] = []
    private var ownsClick: ((NSPoint) -> Bool)?
    private var onPress: ((MenuBarItem) -> Void)?
    private var onDismiss: (() -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var isVisible: Bool { panel?.isVisible == true }

    func show(
        items: [MenuBarItem],
        emptyMessage: String,
        anchorMidX: CGFloat,
        ownsClick: @escaping (NSPoint) -> Bool,
        onPress: @escaping (MenuBarItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.shownItems = items
        self.ownsClick = ownsClick
        self.onPress = onPress
        self.onDismiss = onDismiss

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = installContent(items: items, emptyMessage: emptyMessage, in: panel)
        guard let screen = screen(for: anchorMidX) else { return }
        let menuBar = MenuBarGeometry.menuBarFrame(on: screen)
        var frame = NSRect(
            x: anchorMidX - size.width / 2,
            y: menuBar.minY - size.height - 6,
            width: size.width,
            height: size.height
        )
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 0)
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        startDismissWatch()
    }

    func hide() {
        let wasVisible = isVisible
        panel?.orderOut(nil)
        stopDismissWatch()
        guard wasVisible else { return }
        let dismiss = onDismiss
        onDismiss = nil
        dismiss?()
    }

    // MARK: - Content

    private func makePanel() -> NSPanel {
        let panel = HiddenBarPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isFloatingPanel = true
        // isFloatingPanel resets the level. Put it back above normal windows, under menus.
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSView()
        return panel
    }

    private func installContent(items: [MenuBarItem], emptyMessage: String, in panel: NSPanel) -> NSSize {
        let buttonSide: CGFloat = 22
        let spacing: CGFloat = 8
        let padX: CGFloat = 14
        let padY: CGFloat = 8
        let font = NSFont.systemFont(ofSize: 12)
        let width: CGFloat
        let height: CGFloat
        if items.isEmpty {
            let oneLine = (emptyMessage as NSString).size(withAttributes: [.font: font])
            if oneLine.width <= 300 {
                width = ceil(oneLine.width) + 36
                height = buttonSide + padY * 2
            } else {
                width = 320
                let bounds = (emptyMessage as NSString).boundingRect(
                    with: NSSize(width: width - 32, height: 80),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font]
                )
                height = max(buttonSide + padY * 2, ceil(bounds.height) + 18)
            }
        } else {
            height = buttonSide + padY * 2
            width = padX * 2 + CGFloat(items.count) * buttonSide + CGFloat(items.count - 1) * spacing
        }

        let container = panel.contentView ?? NSView()
        panel.contentView = container
        container.subviews.forEach { $0.removeFromSuperview() }

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = height / 2
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)

        if items.isEmpty {
            let label = NSTextField(wrappingLabelWithString: emptyMessage)
            label.frame = NSRect(x: 16, y: 4, width: width - 32, height: height - 8)
            label.alignment = .center
            label.textColor = .white
            label.font = font
            label.maximumNumberOfLines = 2
            effect.addSubview(label)
        } else {
            for (index, item) in items.enumerated() {
                let button = NSButton()
                button.tag = index
                button.isBordered = false
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleProportionallyDown
                button.bezelStyle = .shadowlessSquare
                button.setButtonType(.momentaryChange)
                let image = Self.image(for: item)
                button.image = image
                if image.isTemplate {
                    button.contentTintColor = .white
                }
                button.toolTip = item.displayName
                button.setAccessibilityLabel(item.displayName)
                button.target = self
                button.action = #selector(itemPressed(_:))
                let x = padX + CGFloat(index) * (buttonSide + spacing)
                button.frame = NSRect(x: x, y: padY, width: buttonSide, height: buttonSide)
                effect.addSubview(button)
            }
        }
        return NSSize(width: width, height: height)
    }

    /// shortcut: app icon or SF Symbol, not a snapshot of the real menu-bar glyph. Upgrade when Screen Recording is an acceptable permission.
    private static func image(for item: MenuBarItem) -> NSImage {
        if let name = symbolName(for: item),
           let symbol = NSImage(systemSymbolName: name, accessibilityDescription: item.displayName) {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let image = symbol.withSymbolConfiguration(config) ?? symbol
            image.isTemplate = true
            return image
        }
        if !hostBundleIDs.contains(item.bundleID),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }
        let fallback = NSImage(systemSymbolName: "app.fill", accessibilityDescription: item.displayName) ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }

    private static func symbolName(for item: MenuBarItem) -> String? {
        let id = item.axIdentifier.lowercased()
        let name = item.displayName.lowercased()
        if id.contains("wifi") || name.contains("wi-fi") || name.contains("wifi") { return "wifi" }
        if id.contains("battery") || name.contains("battery") { return "battery.100percent" }
        if id.contains("bluetooth") || name.contains("bluetooth") { return "bluetooth" }
        if id.contains("clock") || name == "clock" { return "clock" }
        if id.contains("controlcenter") || name.contains("control center") { return "switch.2" }
        if id.contains("volume") || name.contains("sound") { return "speaker.wave.2" }
        if id.contains("display") || name.contains("display") { return "sun.max" }
        if name.contains("siri") { return "waveform" }
        if name.contains("focus") { return "moon.fill" }
        return nil
    }

    private static let hostBundleIDs: Set<String> = [
        "com.apple.MenuBarAgent",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
    ]

    private func screen(for midX: CGFloat) -> NSScreen? {
        NSScreen.screens.first { $0.frame.minX <= midX && midX <= $0.frame.maxX } ?? NSScreen.main
    }

    @objc private func itemPressed(_ sender: NSButton) {
        guard shownItems.indices.contains(sender.tag) else { return }
        onPress?(shownItems[sender.tag])
    }

    // MARK: - Dismiss

    private func startDismissWatch() {
        stopDismissWatch()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissIfOutside(NSEvent.mouseLocation)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .keyDown, event.keyCode == 53 {
                    self?.hide()
                } else {
                    self?.dismissIfOutside(NSEvent.mouseLocation)
                }
            }
            return event
        }
    }

    private func stopDismissWatch() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func dismissIfOutside(_ point: NSPoint) {
        guard let panel, panel.isVisible else { return }
        if panel.frame.contains(point) { return }
        if ownsClick?(point) == true { return }
        hide()
    }
}

private final class HiddenBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
