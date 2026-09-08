//
//  Created by Roman Chornyi
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

/// Business side of moving credits OUT of the DashPay identity — the mirror
/// of `IdentityTopUpViewModel`: one PIN/biometric gate, then the single state
/// transition the chosen target needs.
///
/// - `.transparent`: `withdrawCredits` — an IdentityCreditWithdrawal that
///   pays out to the wallet's own next Core receive address. The L1 output
///   arrives asynchronously once the network processes the withdrawal, so
///   this returns before the Dash is spendable.
/// - `.platform`: `transferCreditsToAddresses` — a credit transfer to the
///   wallet's own next Platform receive address. Stays on Platform, so it
///   settles as soon as the transition is accepted.
///
/// Shielded is absent by construction: `IdentityWithdrawalTarget` has no case
/// for it, because no single transition moves identity credits into the
/// Orchard pool.
@MainActor
final class IdentityWithdrawViewModel: ObservableObject {

    @Published var isProcessing = false
    @Published var errorMessage: String?

    private let authorizer = DWIdentityAuthorizer()

    enum WithdrawError: LocalizedError {
        case noCoreReceiveAddress
        case noPlatformReceiveAddress

        var errorDescription: String? {
            switch self {
            case .noCoreReceiveAddress:
                return NSLocalizedString(
                    "No receive address is available yet — reopen the wallet and try again.",
                    comment: "Identity withdrawal — missing Core payout address")
            case .noPlatformReceiveAddress:
                return NSLocalizedString(
                    "No Platform receive address is available yet — wait for the Platform sync to finish and try again.",
                    comment: "Identity top-up sheet — missing unshield destination")
            }
        }
    }

    /// Consensus floor for an IdentityCreditWithdrawal, mirroring
    /// `platform_version.system_limits.min_withdrawal_amount` — 1000 duffs
    /// since protocol v12 (raised from 190). Below it the resulting Core
    /// `TxOut` would be dust and the transition is rejected outright, so the
    /// screen refuses the amount before Confirm rather than letting the
    /// network do it.
    ///
    /// Applies to `.transparent` only: a credit transfer produces no L1
    /// output and carries no equivalent protocol floor.
    static let minimumWithdrawalCredits: UInt64 = 1_000_000

    /// Held back from the identity balance so the transition can pay its own
    /// fee, which is charged to the identity on top of the amount.
    ///
    /// The SDK exposes no fee estimator for either of these transitions — the
    /// same gap `PlatformPaymentIdentityFundingPolicy` documents for identity
    /// funding — so this reuses that policy's reserve rather than repeating
    /// its measurement: both bound an identity-signed transition whose
    /// observed base fee is ~0.0004 DASH, and only the real fee is deducted.
    ///
    /// TODO(SwiftDashSDK): replace with the SDK's own estimate once one is
    /// exposed for IdentityCreditWithdrawal / identity credit transfer.
    static var feeHeadroomCredits: UInt64 {
        PlatformPaymentIdentityFundingPolicy.feeHeadroomCredits
    }

    /// The largest amount `balanceCredits` can send: everything above the fee
    /// reserve. Zero when the balance cannot cover the reserve at all.
    static func spendableCredits(balanceCredits: UInt64) -> UInt64 {
        balanceCredits > feeHeadroomCredits ? balanceCredits - feeHeadroomCredits : 0
    }

    /// True on success. False = cancelled at the PIN prompt (no
    /// `errorMessage`) or failed (`errorMessage` carries the reason) — the
    /// same contract as `IdentityTopUpViewModel.topUp`'s nil.
    func withdraw(
        identityId: Data,
        amountCredits: UInt64,
        target: IdentityWithdrawalTarget
    ) async -> Bool {
        guard !isProcessing else { return false }
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            errorMessage = NSLocalizedString("Wallet is not ready", comment: "DashPay")
            return false
        }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await authorizer.authorize()
        } catch {
            // Backing out of the PIN prompt is not an error state.
            return false
        }

        do {
            let signer = KeychainSigner(modelContainer: modelContainer)
            switch target {
            case .transparent:
                guard let address = SwiftDashSDKReceiveAddressReader.receiveAddress(),
                      !address.isEmpty else {
                    throw WithdrawError.noCoreReceiveAddress
                }
                try await wallet.withdrawCredits(
                    identityId: identityId,
                    amount: amountCredits,
                    toAddress: address,
                    signer: signer)

            case .platform:
                try await transferToOwnPlatformAddress(
                    identityId: identityId,
                    amountCredits: amountCredits,
                    wallet: wallet,
                    signer: signer)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Credits → the wallet's own next Platform receive address. The address
    /// is parsed the same way the shielded top-up parses its unshield
    /// destination: 21 storage bytes, the first being the address type.
    private func transferToOwnPlatformAddress(
        identityId: Data,
        amountCredits: UInt64,
        wallet: ManagedPlatformWallet,
        signer: KeychainSigner
    ) async throws {
        guard let destination = PlatformAddressSyncCoordinator.shared
            .derivedAddresses.nextReceiveAddress?.address,
            !destination.isEmpty,
            let storageBytes = AddressTransformer.parseBech32mAddress(destination),
            storageBytes.count == 21 else {
            // Typed so the generic catch surfaces THIS message instead of
            // overwriting it with an unrelated one.
            throw WithdrawError.noPlatformReceiveAddress
        }
        let recipient = PlatformAddressCreditOutput(
            addressType: storageBytes[storageBytes.startIndex],
            hash: Data(storageBytes.dropFirst()),
            credits: amountCredits)
        try await wallet.transferCreditsToAddresses(
            fromIdentityId: identityId,
            recipients: [recipient],
            signer: signer)
        Task { await PlatformAddressSyncCoordinator.shared.syncNow() }
    }
}
