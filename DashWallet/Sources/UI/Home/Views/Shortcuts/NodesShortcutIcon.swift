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

/// The "Nodes" shortcut's 46 pt disc: the current **epoch day** (0–9) large
/// on top, a thin divider, and the number of blocks this wallet's evonodes
/// have **proposed this epoch** on the bottom strip. Reads the shared
/// `EvonodeEpochBlocksMonitor`; the day is recomputed every minute from the
/// epoch start without any network call. Shows "–" for either number until
/// the first tally arrives.
struct NodesShortcutIcon: View {
    @ObservedObject private var monitor: EvonodeEpochBlocksMonitor

    /// Mainnet epochs are 9.125 days, so the day index runs 0…9.
    static let maxEpochDay = 9
    /// Block counts beyond this render as "99+" so they stay legible.
    static let maxDisplayedBlocks: UInt64 = 99

    init(monitor: EvonodeEpochBlocksMonitor = .shared) {
        self.monitor = monitor
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let day = Self.epochDay(start: monitor.blocks?.epochStart, now: context.date)
            let blocks = monitor.blocks?.totalBlocks
            disc(dayText: day.map(String.init) ?? "–", blocksText: Self.blocksText(blocks))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.accessibilityLabel(day: day, blocks: blocks))
        }
    }

    private func disc(dayText: String, blocksText: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.dash.blue)

            VStack(spacing: 0) {
                // Epoch day — the big number.
                Text(dayText)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(height: 24)
                    .padding(.top, 3)

                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 20, height: 1)

                // Blocks proposed this epoch — the counter strip.
                Text(blocksText)
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 15)
                    .padding(.bottom, 3)
            }
        }
        .frame(width: 46, height: 46)
    }

    /// Whole days since the epoch started, clamped to 0…`maxEpochDay`; `nil`
    /// when the epoch start isn't known yet.
    static func epochDay(start: Date?, now: Date) -> Int? {
        guard let start else { return nil }
        let days = Int(floor(now.timeIntervalSince(start) / 86_400))
        return min(max(days, 0), maxEpochDay)
    }

    static func blocksText(_ blocks: UInt64?) -> String {
        guard let blocks else { return "–" }
        return blocks > maxDisplayedBlocks ? "\(maxDisplayedBlocks)+" : "\(blocks)"
    }

    static func accessibilityLabel(day: Int?, blocks: UInt64?) -> String {
        guard let day, let blocks else {
            return NSLocalizedString("Nodes", comment: "Shortcut")
        }
        return String(
            format: NSLocalizedString("Nodes, epoch day %d, %@ blocks proposed this epoch", comment: "Nodes shortcut accessibility"),
            day,
            blocksText(blocks))
    }
}

#if DEBUG
#Preview {
    NodesShortcutIcon()
        .padding()
}
#endif
