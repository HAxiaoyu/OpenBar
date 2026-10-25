//
//  OpenBar — an open-source menu bar manager for macOS.
//  Copyright (C) 2026 OpenBar contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version. See the LICENSE file for details.
//

import SwiftUI

/// First-run guide. v0.1 can't move other apps' icons programmatically, so the
/// user arranges them once with ⌘-drag; macOS remembers the positions.
struct OnboardingView: View {
    let onFinish: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Welcome to OpenBar").font(.title.bold())
                    Text("Tidy up your menu bar in three steps.").foregroundStyle(.secondary)
                }
            }

            // A schematic of the layout, drawn with SF Symbols (no third-party assets).
            LayoutDiagram()

            VStack(alignment: .leading, spacing: 12) {
                Step(number: 1,
                     title: "Find the dividers",
                     detail: "OpenBar added a chevron icon plus two thin dividers to your menu bar: │ (Hidden) and ‖ (Always Hidden). They're visible right now.")
                Step(number: 2,
                     title: "Hold ⌘ and drag icons",
                     detail: "Drag icons to the left of │ to hide them, or to the left of ‖ to keep them hidden until you ask for everything. Icons right of │ always stay visible.")
                Step(number: 3,
                     title: "Click the chevron to show/hide",
                     detail: "Click OpenBar's chevron (or an empty part of the menu bar, or your hotkey) to reveal hidden icons. ⌥-click reveals the Always-Hidden ones too. Right-click for Settings.")
            }

            Text("Tip: if an icon won't move, make sure the menu bar section is expanded first — you can't drag icons that are off-screen.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Got It") { onFinish() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 560)
    }
}

private struct Step: View {
    let number: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "\(number).circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LayoutDiagram: View {
    var body: some View {
        HStack(spacing: 6) {
            Group {
                Image(systemName: "circle.dotted")
                Image(systemName: "circle.dotted")
            }
            .foregroundStyle(.secondary.opacity(0.5))
            Text("‖").bold()
            Group {
                Image(systemName: "square.dashed")
                Image(systemName: "square.dashed")
            }
            .foregroundStyle(.secondary)
            Text("│").bold()
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "chevron.compact.left").bold()
            Spacer()
            Text("12:00").monospacedDigit()
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 0) {
                Text("Always hidden").frame(width: 70, alignment: .leading)
                Text("Hidden").frame(width: 70, alignment: .leading).padding(.leading, 14)
                Text("Visible").padding(.leading, 14)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .offset(x: 12, y: 18)
        }
        .padding(.bottom, 16)
    }
}
