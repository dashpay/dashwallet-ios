//  
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

import Foundation
import Combine

enum ToolsMenuNavigationDestination {
    case importPrivateKey
    case extendedPublicKeys
    case masternodeKeys
    case csvExport
    case zenLedger
    case swiftDashSDKSPVStatus
    case platformSyncStatus
    case storageExplorer
}

@MainActor
class ToolsMenuViewModel: ObservableObject {
    @Published var items: [MenuItemModel] = []
    @Published var navigationDestination: ToolsMenuNavigationDestination?
    @Published var showCSVExportActivity = false
    @Published var csvExportData: (fileName: String, file: URL)?
    @Published var safariLink: String?
    @Published var showCoinJoinSweepConfirmation = false

    private var cancellables = Set<AnyCancellable>()

    /// Minimum CoinJoin-account balance (duffs) worth surfacing a sweep for.
    /// Mirrors `SettingsMenuViewModel.minCoinJoinSweepDuffs`.
    private static let minCoinJoinSweepDuffs: UInt64 = 1000

    /// Live CoinJoin-account spendable balance (duffs) — the SDK source of truth.
    private var coinJoinLeftoverDuffs: UInt64 {
        SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs
    }

    /// Whether to show the conditional "Move CoinJoin Funds" row.
    var hasCoinJoinLeftover: Bool {
        coinJoinLeftoverDuffs > Self.minCoinJoinSweepDuffs
    }

    /// Formatted leftover amount for the confirmation dialog.
    var coinJoinLeftoverFormatted: String {
        String(format: "%.6f DASH", Double(coinJoinLeftoverDuffs) / Double(DUFFS))
    }

    init() {
        setupMenuItems()
        setupCoinJoinObserver()
    }

    /// Rebuild the list when the CoinJoin balance crosses the sweep threshold, so
    /// the "Move CoinJoin Funds" row appears while an unswept leftover exists and
    /// self-removes once the post-sweep refresh drops it below the threshold.
    private func setupCoinJoinObserver() {
        SwiftDashSDKWalletState.shared.$coinJoinBalanceDuffs
            .map { $0 > Self.minCoinJoinSweepDuffs }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupMenuItems()
            }
            .store(in: &cancellables)
    }
    
    private func setupMenuItems() {
        items = [
            MenuItemModel(
                title: NSLocalizedString("Import Private Key", comment: ""),
                icon: .custom("image.import.private.key", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .importPrivateKey
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Extended public key (BIP44)", comment: ""),
                icon: .custom("image.extend.public.key", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .extendedPublicKeys
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Show Masternode Keys", comment: ""),
                icon: .custom("image.masternode.keys", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .masternodeKeys
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("CSV Export", comment: ""),
                icon: .custom("image.csv.export", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .csvExport
                }
            ),
            MenuItemModel(
                title: "SwiftDashSDK SPV Status",
                icon: .system("arrow.triangle.2.circlepath"),
                action: { [weak self] in
                    self?.navigationDestination = .swiftDashSDKSPVStatus
                }
            ),
            MenuItemModel(
                title: "Platform Sync Status",
                icon: .system("globe"),
                action: { [weak self] in
                    self?.navigationDestination = .platformSyncStatus
                }
            ),
            MenuItemModel(
                title: "Storage Explorer",
                icon: .system("cylinder.split.1x2"),
                action: { [weak self] in
                    self?.navigationDestination = .storageExplorer
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("ZenLedger", comment: ""),
                subtitle: NSLocalizedString("Simplify your crypto taxes", comment: ""),
                icon: .custom("zenledger"),
                action: { [weak self] in
                    self?.navigationDestination = .zenLedger
                }
            )
        ]

        // Conditional production row, directly below "Storage Explorer": appears
        // only while unswept CoinJoin (mixed) funds remain, and self-removes after
        // the sweep (the $coinJoinBalanceDuffs observer rebuilds the list).
        // Mirrors the Settings "Move CoinJoin Funds" row and the post-sync popup.
        if hasCoinJoinLeftover,
           let storageIdx = items.firstIndex(where: { $0.title == "Storage Explorer" }) {
            items.insert(
                MenuItemModel(
                    title: NSLocalizedString("Move CoinJoin Funds", comment: "CoinJoin"),
                    subtitle: NSLocalizedString("CoinJoin is no longer supported", comment: "CoinJoin"),
                    icon: .custom("image.coinjoin.menu", maxHeight: 22),
                    action: { [weak self] in
                        self?.showCoinJoinSweepConfirmation = true
                    }
                ),
                at: storageIdx + 1
            )
        }
    }

    /// Sweep the leftover CoinJoin-account balance into the user's spendable
    /// balance via the shared `WalletSendService` flow (PIN → resolve own BIP44
    /// address → sweep → balance refresh). Mirrors the Settings row + popup; the
    /// "Move CoinJoin Funds" row self-removes once the balance drops below the
    /// threshold.
    func performCoinJoinSweep() async {
        do {
            _ = try await WalletSendService.shared.sweepCoinJoin()
        } catch {
            // Auth-cancel is an expected no-op; on other failures the row stays
            // visible (balance unchanged) so the user can retry.
            #if DEBUG
            print("🎯 CoinJoin sweep failed: \(error)")
            #endif
        }
    }
    
    func resetNavigation() {
        navigationDestination = nil
        showCSVExportActivity = false
        csvExportData = nil
        safariLink = nil
    }
    
    func exportCSV() async throws {
        let result = try await generateCSVReport()
        csvExportData = result
        showCSVExportActivity = true
    }
    
    private func generateCSVReport() async throws -> (fileName: String, file: URL) {
        try await withCheckedThrowingContinuation { continuation in
            TaxReportGenerator.generateCSVReport(
                completionHandler: { fileName, file in
                    continuation.resume(returning: (fileName, file))
                },
                errorHandler: { error in
                    continuation.resume(throwing: error)
                }
            )
        }
    }
}
