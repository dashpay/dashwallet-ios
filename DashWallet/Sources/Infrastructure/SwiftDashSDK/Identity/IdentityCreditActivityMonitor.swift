//
//  IdentityCreditActivityMonitor.swift
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

import Foundation
import SwiftDashSDK
import SwiftData

/// Reads the Current identity's balance from the network and hands it to `IdentityCreditActivityRecorder`
/// (ADR-0077). Asked after each Platform-address sync pass (`PlatformAddressSyncCoordinator`) and when Home appears.
///
/// Shared because both callers must go through one in-flight guard: two reads answered out of order would compare a
/// newer baseline with an older balance.
@MainActor
final class IdentityCreditActivityMonitor {
    static let shared = IdentityCreditActivityMonitor()

    private var isReading = false

    func check(reason: String) async {
        guard !isReading else { return }
        let host = SwiftDashSDKHost.shared
        guard let wallet = host.wallet,
              let network = host.runningNetwork,
              let container = host.modelContainer,
              let identityId = DWCurrentUserIdentityInfo.shared.identityId else { return }
        isReading = true
        defer { isReading = false }

        // Taken before the read: a trace written while it runs counts for the next read, and a wipe during it
        // drops its answer.
        let readStart = Date()
        let generation = IdentityCreditActivityDAO.shared.generation
        let balance: UInt64
        do {
            balance = try await wallet.refreshIdentityBalance(identityId: identityId)
        } catch {
            DWLogger.log("IDENTITY-CREDITS: balance read failed (\(reason)): \(type(of: error))")
            return
        }
        // A wallet or network switch during the read: the answer belongs to the previous scope.
        guard host.wallet === wallet, host.runningNetwork == network,
              DWCurrentUserIdentityInfo.shared.identityId == identityId else {
            DWLogger.log("IDENTITY-CREDITS: read dropped, wallet or network changed (\(reason))")
            return
        }
        let walletId = wallet.walletId
        let networkRaw = Int64(network.rawValue)
        var ownCount = 0
        let outcome = IdentityCreditActivityRecorder.observe(
            balanceCredits: balance, identityId: identityId, walletId: walletId, networkRaw: networkRaw,
            readStart: readStart, generation: generation,
            ownCredits: { after in
                let credits = IdentityCreditActivityRecorder.ownCredits(
                    identityId: identityId, walletId: walletId, networkRaw: networkRaw, after: after,
                    container: container)
                ownCount = credits.count
                return credits
            })
        switch outcome {
        case .seeded:
            DWLogger.log("IDENTITY-CREDITS: baseline seeded (\(reason))")
        case .unchanged:
            break
        case .received(let duffs):
            DWLogger.log("IDENTITY-CREDITS: Received row +\(duffs) duffs, own operations since the previous read: "
                + "\(ownCount) (\(reason))")
        case .failed:
            DWLogger.log("IDENTITY-CREDITS: store write failed, baseline kept (\(reason))")
        case .dropped:
            DWLogger.log("IDENTITY-CREDITS: read dropped, the wallet's history was deleted during it (\(reason))")
        }
    }
}
