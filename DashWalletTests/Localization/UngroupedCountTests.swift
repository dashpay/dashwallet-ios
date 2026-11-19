//
//  UngroupedCountTests.swift
//  DashWalletTests
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

import XCTest

/// Block heights and list counts that the Baseline built with the locale-less
/// `String(format:)` ("block #2123456") stay without thousands separators after the move to
/// `String(localized:)`, whose integer interpolation groups by locale ("2,123,456").
///
/// The route is the Baseline's own: `String(format: String(localized: "<Baseline key>", comment: …), args)`.
/// That keeps the Baseline key and renders the integers through `%d`/`%u` without grouping. The
/// zero-loss check formats both sides with `String(format:locale:)`, so it cannot see the route;
/// the source check below does.
final class UngroupedCountTests: XCTestCase {
    /// (file under DashWallet/Sources, the Baseline key at that site, read from `git show 088eead15:<file>`)
    /// of each `String(format:)` + integer site whose value can reach 1000: block and list heights,
    /// list counts, transaction input/output counts and indexes, address-pool counts, epoch day,
    /// contact requests.
    private let sites: [(file: String, key: String)] = [
        ("UI/Home/Syncing Views/Sync View/SyncView.swift", "header #%d of %d"),
        ("UI/Home/Syncing Views/Sync View/SyncView.swift", "masternode list #%d of %d"),
        ("UI/Home/Syncing Views/Sync View/SyncView.swift", "block #%d of %d"),
        ("UI/Home/Syncing Views/Alert/SyncingAlertView.swift", "block #%d of %d"),
        ("UI/Menu/Settings/About/DWAboutModel+MasternodeSync.swift", "Masternode list: %u of %u"),
        ("UI/Menu/Settings/About/DWAboutModel+MasternodeSync.swift", "Masternode list: synced at %u"),
        ("UI/Menu/Settings/About/DWAboutModel+MasternodeSync.swift", "Block #%d of %d"),
        ("UI/Menu/Tools/MasternodesScreen.swift", "Height %u"),
        ("UI/Menu/Tools/Tracked Masternodes/TrackedMasternodeDetailScreen.swift", "Height %u"),
        ("UI/Menu/SyncInfo/SwiftDashSDKSPVStatusScreen.swift",
         "Confirming saves birth height %u and clears this network's chain data at the next app launch, re-downloading it and rescanning filters from that height. Fully close and relaunch the app to start; the in-app Restart button does not apply this reset."),
        ("UI/Menu/SyncInfo/SwiftDashSDKSPVStatusScreen.swift", "Rescan started from height %u \u{2014} watch the Filters row."),
        ("UI/Menu/SyncInfo/SwiftDashSDKSPVStatusScreen.swift",
         "Resync armed from height %u. Fully close the app, then launch it again to start. The in-app Restart button does not apply this reset."),
        ("UI/Tx/Details/RawTransactionView.swift", "Inputs (%d)"),
        ("UI/Tx/Details/RawTransactionView.swift", "Outputs (%d)"),
        ("UI/Tx/Details/RawTransactionView.swift", "Input %d"),
        ("UI/Tx/Details/RawTransactionView.swift", "Input %d \u{2014} outpoint"),
        ("UI/Tx/Details/RawTransactionView.swift", "Output %d"),
        ("Models/Transactions/Model/RawTransactionInspector.swift", "Credit output %d"),
        ("UI/Menu/Security/Wallets/WalletAccountDetailScreen.swift", "%@ Addresses (%d)"),
        ("UI/Home/Views/Shortcuts/NodesShortcutIcon.swift", "Nodes, epoch day %d, %@ blocks proposed this epoch"),
        ("UI/DashPay/Contacts/SwiftUI/ContactsScreen.swift", "Contact Requests (%d)"),
    ]

    /// Every site looks its Baseline key up as `String(format: String(localized: "<key>"`: the literal
    /// is the key whole, so it holds no `\(` interpolation.
    func testEverySiteKeepsItsBaselineKeyInsideStringFormat() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DashWallet/Sources")
        for site in sites {
            let source = try String(contentsOf: root.appendingPathComponent(site.file), encoding: .utf8)
            let pattern = "String\\(\\s*format:\\s*String\\(\\s*localized:\\s*\"" + NSRegularExpression.escapedPattern(for: site.key) + "\""
            let regex = try NSRegularExpression(pattern: pattern)
            let found = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
            XCTAssertTrue(found, "\(site.file): no String(format: String(localized: \"\(site.key.prefix(40))…\"")
        }
    }

    /// The route renders a height ungrouped in the host's locale.
    func testBaselineKeyRouteRendersHeightWithoutSeparators() {
        let key = "block #%d of %d"
        let text = String(format: String(localized: String.LocalizationValue(key)), Int32(2123456), Int32(2200000))
        XCTAssertTrue(text.contains("2123456"), text)
        XCTAssertTrue(text.contains("2200000"), text)
    }
}
