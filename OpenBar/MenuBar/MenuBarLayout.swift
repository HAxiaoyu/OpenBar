//
//  OpenBar — an open-source menu bar manager for macOS.
//  Copyright (C) 2026 OpenBar contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version. See the LICENSE file for details.
//

import CoreGraphics

/// Which section is revealed. Sections are still physical spans between
/// dividers; this only records whether those spans are open.
@MainActor
enum MenuBarLayout {
    enum Phase: Equatable {
        case collapsed
        case hiddenRevealed
        case allRevealed
    }

    /// `midX` of control items whose windows currently sit on a menu bar.
    /// Items parked off the bar (collapsed length) are omitted.
    static func dividersOutOfOrder(_ midXByRole: [ControlItem.Role: CGFloat]) -> Bool {
        let xs = ControlItem.Role.leftToRight.compactMap { midXByRole[$0] }
        guard xs.count >= 2 else { return false }
        return zip(xs, xs.dropFirst()).contains { $0 >= $1 }
    }

    /// Icons sitting on the menu bar strictly between the two dividers.
    /// Off-bar frames (a collapsed divider) are not in the span.
    static func itemsInHiddenSpan(
        _ items: [MenuBarItem],
        ownBundleID: String,
        hiddenDividerMidX: CGFloat,
        alwaysHiddenDividerMidX: CGFloat?
    ) -> [MenuBarItem] {
        items.filter {
            isInHiddenSpan(
                $0,
                ownBundleID: ownBundleID,
                hiddenDividerMidX: hiddenDividerMidX,
                alwaysHiddenDividerMidX: alwaysHiddenDividerMidX
            )
        }
        .sorted { ($0.positionX ?? 0) < ($1.positionX ?? 0) }
    }

    static func isInHiddenSpan(
        _ item: MenuBarItem,
        ownBundleID: String,
        hiddenDividerMidX: CGFloat,
        alwaysHiddenDividerMidX: CGFloat?
    ) -> Bool {
        guard item.bundleID != ownBundleID else { return false }
        guard let x = item.positionX, let y = item.positionY, y >= 0, y < 80 else { return false }
        let mid = CGFloat(x + (item.width ?? 0) / 2)
        if let alwaysHiddenDividerMidX, mid <= alwaysHiddenDividerMidX { return false }
        return mid < hiddenDividerMidX
    }

    /// The icon to click. A namesake that is still in the visible menu bar
    /// (right of the hidden divider) is never chosen.
    static func pressTarget(
        for item: MenuBarItem,
        in scanned: [MenuBarItem],
        ownBundleID: String,
        hiddenDividerMidX: CGFloat,
        alwaysHiddenDividerMidX: CGFloat?
    ) -> MenuBarItem? {
        let span = itemsInHiddenSpan(
            scanned,
            ownBundleID: ownBundleID,
            hiddenDividerMidX: hiddenDividerMidX,
            alwaysHiddenDividerMidX: alwaysHiddenDividerMidX
        )
        if let exact = span.first(where: { $0.id == item.id }) { return exact }
        return span
            .filter { $0.bundleID == item.bundleID && $0.displayName == item.displayName }
            .min { abs(($0.positionX ?? 0) - (item.positionX ?? 0)) < abs(($1.positionX ?? 0) - (item.positionX ?? 0)) }
    }

    /// The divider that has to be wide for this phase. When everything is
    /// collapsed, only the hidden divider grows; the always-hidden one is
    /// already inside that span. Two wide dividers get each other ejected.
    static func dividerDrawsWide(_ role: ControlItem.Role, phase: Phase) -> Bool {
        switch role {
        case .hidden: phase == .collapsed
        case .alwaysHidden: phase == .hiddenRevealed
        case .toggle: false
        }
    }

    static func assertOrderRules() {
        assert(!dividersOutOfOrder([.alwaysHidden: 10, .hidden: 20, .toggle: 30]))
        assert(dividersOutOfOrder([.hidden: 40, .toggle: 10]))
        assert(!dividersOutOfOrder([.toggle: 10]))
        assert(dividerDrawsWide(.hidden, phase: .collapsed))
        assert(!dividerDrawsWide(.alwaysHidden, phase: .collapsed))
        assert(dividerDrawsWide(.alwaysHidden, phase: .hiddenRevealed))
        assert(!dividerDrawsWide(.hidden, phase: .hiddenRevealed))
        assert(!dividerDrawsWide(.hidden, phase: .allRevealed))
        assertSpanRules()
    }

    private static func assertSpanRules() {
        let own = "com.example.OpenBar"
        let hidden = sample(bundle: "com.follow.clash", x: 100)
        assert(isInHiddenSpan(hidden, ownBundleID: own, hiddenDividerMidX: 200, alwaysHiddenDividerMidX: 40))
        assert(!isInHiddenSpan(hidden, ownBundleID: own, hiddenDividerMidX: 80, alwaysHiddenDividerMidX: 40))
        assert(!isInHiddenSpan(hidden, ownBundleID: own, hiddenDividerMidX: 200, alwaysHiddenDividerMidX: 150))
        assert(!isInHiddenSpan(sample(bundle: own, x: 100), ownBundleID: own, hiddenDividerMidX: 200, alwaysHiddenDividerMidX: nil))
        assert(!isInHiddenSpan(sample(bundle: "com.follow.clash", x: 100, y: 900), ownBundleID: own, hiddenDividerMidX: 200, alwaysHiddenDividerMidX: nil))
        let hiddenAtoll = sample(bundle: "com.Ebullioscopic.Atoll", x: 100, id: "hidden")
        let visible = sample(bundle: "com.Ebullioscopic.Atoll", x: 500, id: "visible")
        assert(pressTarget(for: hiddenAtoll, in: [visible, hiddenAtoll], ownBundleID: own, hiddenDividerMidX: 200, alwaysHiddenDividerMidX: nil)?.positionX == 100)
        assert(pressTarget(for: visible, in: [visible], ownBundleID: own, hiddenDividerMidX: 200, alwaysHiddenDividerMidX: nil) == nil)
    }

    private static func sample(bundle: String, x: Double, y: Double = 5, id: String = "sample") -> MenuBarItem {
        MenuBarItem(
            id: id,
            bundleID: bundle,
            axIdentifier: "",
            title: "",
            label: "",
            ordinal: 0,
            positionX: x,
            positionY: y,
            width: 20,
            height: 22,
            windowID: nil,
            missingSince: nil
        )
    }
}
