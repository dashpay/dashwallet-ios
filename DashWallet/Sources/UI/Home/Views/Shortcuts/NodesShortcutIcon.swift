//
//  NodesShortcutIcon.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI

// MARK: - NodesShortcutIcon

/// The "Nodes" shortcut's 46 pt disc: the rim is a **progress ring** for how
/// far the current epoch has run, the **epoch day** (0–9) sits large in the
/// centre, and a white badge on the bottom edge carries the blocks this
/// wallet's evonodes have **proposed this epoch**. The disc colour is the
/// fleet's health: blue when every node is proposing, yellow when one
/// hasn't proposed a block in 2 days, red when we're on epoch day 4+ and a
/// node still has none this epoch.
///
/// Reads the shared `EvonodeEpochBlocksMonitor`; everything time-based is
/// recomputed every minute locally. Shows "–" until the first tally.
struct NodesShortcutIcon: View {
    @ObservedObject private var monitor: EvonodeEpochBlocksMonitor

    /// Mainnet epochs are 9.125 days (`EPOCH_CHANGE_TIME_MS`), so the day
    /// index runs 0…9 and the ring fills over that span.
    static let epochLength: TimeInterval = 9.125 * 24 * 60 * 60
    static let maxEpochDay = 9
    /// Block counts beyond this render as "99+" so they stay legible.
    static let maxDisplayedBlocks: UInt64 = 99

    init(monitor: EvonodeEpochBlocksMonitor = .shared) {
        self.monitor = monitor
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let start = monitor.blocks?.epochStart
            let day = Self.epochDay(start: start, now: now)
            let blocks = monitor.blocks?.totalBlocks
            let health = EvonodeHealth.evaluate(
                blocks: monitor.blocks,
                activity: monitor.activity,
                epochDay: day,
                now: now)
            disc(
                progress: Self.epochProgress(start: start, now: now),
                dayText: day.map(String.init) ?? "–",
                blocksText: Self.blocksText(blocks),
                tint: Self.tint(for: health))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.accessibilityLabel(day: day, blocks: blocks, health: health))
        }
    }

    private func disc(progress: Double, dayText: String, blocksText: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint)

            // Epoch progress ring: faint track, solid arc from 12 o'clock.
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 2.5)
                .padding(3)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)

            // Epoch day — the big number.
            Text(dayText)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .offset(y: -3)

            // Blocks proposed this epoch — badge on the bottom edge.
            Text(blocksText)
                .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 5)
                .frame(height: 12)
                .background(Capsule().fill(Color.white))
                .offset(y: 16)
        }
        .frame(width: 46, height: 46)
    }

    static func tint(for health: EvonodeHealth) -> Color {
        switch health {
        case .healthy: return Color.dash.blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    /// Whole days since the epoch started, clamped to 0…`maxEpochDay`; `nil`
    /// when the epoch start isn't known yet.
    static func epochDay(start: Date?, now: Date) -> Int? {
        guard let start else { return nil }
        let days = Int(floor(now.timeIntervalSince(start) / 86_400))
        return min(max(days, 0), maxEpochDay)
    }

    /// Fraction of the epoch elapsed, 0…1 (0 while the start is unknown).
    static func epochProgress(start: Date?, now: Date) -> Double {
        guard let start else { return 0 }
        return min(max(now.timeIntervalSince(start) / epochLength, 0), 1)
    }

    static func blocksText(_ blocks: UInt64?) -> String {
        guard let blocks else { return "–" }
        return blocks > maxDisplayedBlocks ? "\(maxDisplayedBlocks)+" : "\(blocks)"
    }

    static func accessibilityLabel(day: Int?, blocks: UInt64?, health: EvonodeHealth) -> String {
        guard let day, let blocks else {
            return NSLocalizedString("Nodes", comment: "Shortcut")
        }
        var label = String(
            format: NSLocalizedString("Nodes, epoch day %d, %@ blocks proposed this epoch", comment: "Nodes shortcut accessibility"),
            day,
            blocksText(blocks))
        switch health {
        case .healthy:
            break
        case .warning:
            label += ", " + NSLocalizedString("an evonode has not proposed a block in 2 days", comment: "Nodes shortcut accessibility")
        case .critical:
            label += ", " + NSLocalizedString("an evonode has no blocks this epoch", comment: "Nodes shortcut accessibility")
        }
        return label
    }
}

#if DEBUG
#Preview {
    NodesShortcutIcon()
        .padding()
}
#endif
