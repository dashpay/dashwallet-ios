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

    /// Platform's minimum fee for the transition a withdrawal to `target`
    /// runs, mirroring `STATE_TRANSITION_MIN_FEES_VERSION1`. Consensus checks
    /// the identity balance against amount + this minimum before executing.
    ///
    /// - `.transparent`: IdentityCreditWithdrawal — `credit_withdrawal`,
    ///   400,000,000 credits (0.004 DASH).
    /// - `.platform`: IdentityCreditTransferToAddresses to one address —
    ///   `credit_transfer_to_addresses` (500,000) plus one
    ///   `address_funds_transfer_output_cost` (6,000,000).
    static func minimumFeeCredits(target: IdentityWithdrawalTarget) -> UInt64 {
        switch target {
        case .transparent: return 400_000_000
        case .platform: return 500_000 + 6_000_000
        }
    }

    /// Held back from the identity balance so the transition can pay its own
    /// fee, which is charged to the identity on top of the amount. Must be at
    /// least `minimumFeeCredits(target:)`, or consensus refuses every Max.
    ///
    /// - `.transparent`: the minimum plus 0.001 DASH of margin. Masternode
    ///   withdrawals run the same transition and read their reserve from here
    ///   (`EvonodeWithdrawalViewModel.feeReserveCredits`).
    /// - `.platform`: 0.002 DASH, well above its 0.000065 DASH minimum.
    ///
    /// Owned here rather than borrowed from
    /// `PlatformPaymentIdentityFundingPolicy.feeHeadroomCredits`: that reserve
    /// bounds the opposite direction and must stay small, which is below the
    /// withdrawal minimum.
    ///
    /// TODO(SwiftDashSDK): replace with the SDK's own estimate once one is
    /// exposed for IdentityCreditWithdrawal / identity credit transfer.
    static func feeReserveCredits(target: IdentityWithdrawalTarget) -> UInt64 {
        switch target {
        case .transparent: return minimumFeeCredits(target: .transparent) + 100_000_000
        case .platform: return 200_000_000
        }
    }

    /// The largest amount `balanceCredits` can send to `target`: everything
    /// above that target's fee reserve. Zero when the balance cannot cover the
    /// reserve at all.
    static func spendableCredits(
        balanceCredits: UInt64,
        target: IdentityWithdrawalTarget
    ) -> UInt64 {
        TransferSpendAmountPolicy.spendableCredits(
            balanceCredits: balanceCredits,
            feeReserveCredits: feeReserveCredits(target: target))
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
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    /// Wording for a failed withdrawal: Platform's balance refusal
    /// (`IdentityInsufficientBalanceError`, possible when the balance moved
    /// between Continue and Confirm — the reserve above keeps Max itself clear
    /// of it) as a sentence; everything else keeps the SDK's own description.
    ///
    /// TODO(SwiftDashSDK): the SDK this builds against still reports that
    /// refusal from `withdrawCredits` / `transferCreditsToAddresses` as an
    /// untyped `InvalidIdentityData` carrying the protocol text, so the
    /// `.insufficientIdentityCredits` branch below is not reached yet. It
    /// takes effect once the SDK ships dashpay/platform#5206, which types it.
    static func userFacingMessage(for error: Error) -> String {
        if case .insufficientIdentityCredits? = error as? PlatformWalletError {
            return NSLocalizedString(
                "Your Identity balance can't cover this amount plus the network fee. Enter a smaller amount and try again.",
                comment: "Identity withdrawal — Platform refused the amount as more than the balance can cover")
        }
        return error.localizedDescription
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
