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
import Observation

/// Catalog of menu-bar items. Missing ids stay as tombstones so a relaunch
/// can recognize an icon that comes back.
@MainActor
@Observable
final class MenuBarItemStore {
    static let shared = MenuBarItemStore()

    private(set) var items: [MenuBarItem] = []
    private(set) var isTrusted = false
    private(set) var isScanning = false
    /// Last scan saw nothing, so existing tombstones were left alone.
    private(set) var keptPreviousScan = false

    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL? = nil) {
        MenuBarItem.assertIdentityRules()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenBar", isDirectory: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("menu-bar-items.json")
        items = Self.load(from: self.fileURL)
        isTrusted = AccessibilityPermission.isTrusted
    }

    func refresh() async {
        isTrusted = AccessibilityPermission.isTrusted
        guard isTrusted else { return }
        let targets = MenuBarScanner.currentTargets()
        isScanning = true
        let scanned = await Task.detached(priority: .userInitiated) {
            MenuBarScanner.scan(targets)
        }.value
        isScanning = false
        guard !scanned.isEmpty else {
            keptPreviousScan = !items.isEmpty
            return
        }
        keptPreviousScan = false
        merge(scanned)
        save()
    }

    private func merge(_ scanned: [MenuBarItem]) {
        var byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var seen = Set<String>()
        for item in scanned {
            seen.insert(item.id)
            byID[item.id] = item
        }
        let now = Date()
        for (id, var old) in byID where !seen.contains(id) {
            if old.missingSince == nil { old.missingSince = now }
            byID[id] = old
        }
        items = byID.values.sorted { lhs, rhs in
            if (lhs.missingSince == nil) != (rhs.missingSince == nil) {
                return lhs.missingSince == nil
            }
            let lx = lhs.positionX ?? .greatestFiniteMagnitude
            let rx = rhs.positionX ?? .greatestFiniteMagnitude
            if lx != rx { return lx < rx }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(items).write(to: fileURL, options: .atomic)
        } catch {
            // The in-memory list still works. The next successful scan retries the write.
        }
    }

    private static func load(from url: URL) -> [MenuBarItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MenuBarItem].self, from: data)) ?? []
    }
}
