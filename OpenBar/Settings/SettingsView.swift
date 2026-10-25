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
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            BehaviorSettingsView(settings: settings)
                .tabItem { Label("Behavior", systemImage: "cursorarrow.click.2") }
            HotkeySettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            ItemsSettingsView(store: .shared)
                .tabItem { Label("Items", systemImage: "list.bullet") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 480, minHeight: 400)
        .padding(.top, 8)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var requiresApproval = LaunchAtLogin.requiresApproval

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.setEnabled(newValue)
                        refreshLoginItemState()
                    }
                if requiresApproval {
                    HStack {
                        Text("Approve OpenBar in System Settings › Login Items.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open…") { LaunchAtLogin.openSystemSettings() }
                    }
                }
            }

            Section("Layout") {
                Button("Repair Layout…") {
                    NotificationCenter.default.post(name: .openBarRepairLayout, object: nil)
                }
                Text("Puts the arrow and the two divider lines back in order, then leaves them expanded. ⌘-drag icons to the left of a line to hide them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle("Show section dividers while expanded", isOn: $settings.showSectionDividers)
                Text("Dividers are the thin lines (│ and ‖) you ⌘-drag icons around. Hiding them only affects the expanded state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshLoginItemState)
    }

    private func refreshLoginItemState() {
        launchAtLogin = LaunchAtLogin.isEnabled
        requiresApproval = LaunchAtLogin.requiresApproval
    }
}

// MARK: - Behavior

private struct BehaviorSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Show hidden icons") {
                Toggle("When clicking an empty area of the menu bar", isOn: $settings.showOnClickEmptyArea)
                Toggle("When hovering over an empty area of the menu bar", isOn: $settings.showOnHover)
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(value: $settings.hoverDelay, in: 0...2, step: 0.1)
                            .frame(width: 180)
                        Text(settings.hoverDelay, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                        Text("s")
                    }
                }
                .disabled(!settings.showOnHover)
            }

            Section("Hide again") {
                Toggle("Automatically hide after a delay", isOn: $settings.autoCollapseEnabled)
                LabeledContent("Delay") {
                    HStack {
                        Slider(value: $settings.autoCollapseDelay, in: 2...60, step: 1)
                            .frame(width: 180)
                        Text(settings.autoCollapseDelay, format: .number.precision(.fractionLength(0)))
                            .monospacedDigit()
                        Text("s")
                    }
                }
                .disabled(!settings.autoCollapseEnabled)
                Toggle("Hide when the pointer leaves the menu bar (after hover)", isOn: $settings.collapseWhenMouseLeaves)
                    .disabled(!settings.showOnHover)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkeys

private struct HotkeySettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Show/hide hidden icons:", name: .toggleHiddenSection)
                KeyboardShortcuts.Recorder("Show/hide all icons:", name: .toggleAllSections)
            } footer: {
                Text("Global hotkeys work in any app and don't require Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Items

private struct ItemsSettingsView: View {
    @Bindable var store: MenuBarItemStore

    var body: some View {
        Group {
            if !store.isTrusted {
                ContentUnavailableView {
                    Label("Accessibility Needed", systemImage: "hand.raised")
                } description: {
                    Text("OpenBar lists menu bar icons so you can see what is on the bar. It does not move or click them.")
                } actions: {
                    Button("Allow Accessibility…") { AccessibilityPermission.prompt() }
                    Button("Open System Settings") { AccessibilityPermission.openSystemSettings() }
                }
            } else {
                Form {
                    Section {
                        ForEach(store.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .foregroundStyle(item.missingSince == nil ? .primary : .secondary)
                                Text(caption(for: item))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        HStack {
                            Text(store.isScanning ? "Scanning…" : "\(store.items.count) icons")
                            Spacer()
                            Button("Refresh") { Task { await store.refresh() } }
                                .disabled(store.isScanning)
                        }
                    } footer: {
                        if store.keptPreviousScan {
                            Text("The last scan returned nothing, so the previous list was kept.")
                        } else {
                            Text("Read-only. Dimmed rows were seen before and were missing on the last scan.")
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .task {
            await store.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if AccessibilityPermission.isTrusted != store.isTrusted {
                    await store.refresh()
                }
            }
        }
    }

    private func caption(for item: MenuBarItem) -> String {
        var parts = [item.bundleID]
        if let x = item.positionX, let y = item.positionY {
            parts.append("x \(Int(x)) y \(Int(y))")
        }
        if item.missingSince != nil {
            parts.append("missing")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - About

private struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("OpenBar").font(.title.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("A free, open-source menu bar manager for macOS.\nLicensed under the GNU GPL v3.")
                .multilineTextAlignment(.center)
            Text("Thanks to Ice, Hidden Bar and Dozer for pioneering the techniques used here. See CREDITS.md.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
