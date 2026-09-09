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

import Combine
import Foundation

/// Everything the confirm sheet decides, so the sheet itself only draws.
///
/// Executing the transfer is `InternalTransferRunner`'s, not this object's —
/// the work has to outlive the sheet, which closes the moment it starts. What
/// is left here is per-presentation: what the summary says and which privacy
/// note applies.
@MainActor
final class InternalTransferConfirmViewModel: ObservableObject {

    /// What is being confirmed. The sheet is handed three mutually exclusive
    /// optionals; normalising them here once means every decision below is an
    /// exhaustive switch instead of a repeated three-way `if let` chain — a
    /// fourth kind of transfer becomes a compiler error rather than a branch
    /// somebody has to remember to add.
    enum Mode: Equatable {
        case transfer(InternalTransferRequest)
        /// Nothing to execute. Not reachable from the screen, which only
        /// presents the sheet for a transfer it has already validated, but the
        /// sheet must still render something rather than force-unwrap: every
        /// figure reads as unavailable and Confirm does nothing.
        case unavailable
    }

    let mode: Mode
    let dashDuffs: Int64
    let fiatText: String

    /// Fee row (credits) and Total row (duffs) as
    /// `InternalTransferViewModel` resolved them at Continue. Frozen rather
    /// than recomputed here: for a Core-funded route the Total IS the lock
    /// value that executes, so a figure re-derived while the sheet is up could
    /// differ from the one the user is confirming.
    private let networkFeeCredits: UInt64?
    private let totalDuffs: Int64?

    /// Forwarded from the runner: a nested `ObservableObject` does not
    /// republish through its owner. The sheet closes as soon as the transfer
    /// starts, so this is the only runner state it still needs — a capacity
    /// change is the one outcome the SCREEN behind it has to act on.
    @Published private(set) var platformShieldCapacityChange:
        InternalTransferRunner.PlatformShieldCapacityChange?

    private let runner: InternalTransferRunner
    private var cancellables = Set<AnyCancellable>()

    init(
        route: InternalTransferRoute?,
        identityTopUp: IdentityTopUpTransfer?,
        identityWithdrawal: IdentityWithdrawalTransfer?,
        dashDuffs: Int64,
        amountDuffsUnsigned: UInt64,
        creditsAmount: UInt64,
        fiatText: String,
        networkFeeCredits: UInt64?,
        totalDuffs: Int64?,
        coreToPlatformLockDuffs: UInt64?,
        withdrawalFeeCredits: UInt64?,
        isFullPlatformWithdrawal: Bool,
        isFullShieldedSweep: Bool,
        platformShieldAmountWasMax: Bool,
        runner: InternalTransferRunner = .shared
    ) {
        // Precedence matches what the view did before: an identity transfer
        // wins over a route, which the screen never sets alongside one.
        let kind: InternalTransferRequest.Kind?
        if let identityTopUp {
            kind = .identityTopUp(identityTopUp)
        } else if let identityWithdrawal {
            kind = .identityWithdrawal(identityWithdrawal)
        } else if let route {
            kind = .route(route)
        } else {
            kind = nil
        }

        mode = kind.map { kind in
            .transfer(InternalTransferRequest(
                kind: kind,
                amountDuffsUnsigned: amountDuffsUnsigned,
                creditsAmount: creditsAmount,
                coreToPlatformLockDuffs: coreToPlatformLockDuffs,
                withdrawalFeeCredits: withdrawalFeeCredits,
                isFullPlatformWithdrawal: isFullPlatformWithdrawal,
                isFullShieldedSweep: isFullShieldedSweep,
                platformShieldAmountWasMax: platformShieldAmountWasMax))
        } ?? .unavailable

        self.dashDuffs = dashDuffs
        self.fiatText = fiatText
        self.networkFeeCredits = networkFeeCredits
        self.totalDuffs = totalDuffs
        self.runner = runner

        // `dropFirst` because the runner is shared: whatever a previous
        // transfer left in this property is already there at subscribe time,
        // and forwarding it would close this sheet before the user has
        // confirmed anything. Only changes that happen after this sheet
        // appeared are its own.
        runner.$platformShieldCapacityChange
            .dropFirst()
            .sink { [weak self] in self?.platformShieldCapacityChange = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Display

    /// Digits only — `SwapAmountView` draws the Dash logo beside them rather
    /// than taking a symbol inside the string.
    var dashAmountText: String {
        (request?.amountDuffsUnsigned ?? 0).dashAmount.formattedDashAmountWithoutCurrencySymbol
    }

    var summary: TransferConfirmSummary {
        TransferConfirmSummary(
            route: routeOrNil,
            identityTopUp: topUpOrNil,
            identityWithdrawal: withdrawalOrNil,
            dashDuffs: dashDuffs,
            networkFeeCredits: networkFeeCredits,
            totalDuffs: totalDuffs)
    }

    var privacyTipContext: TransferPrivacyTip.Context? {
        guard let request else { return nil }
        switch request.kind {
        case .route(let route):
            return .route(route, isFullWithdrawal: request.isFullPlatformWithdrawal)
        case .identityTopUp(let topUp):
            return .identityTopUp(from: topUp.source)
        case .identityWithdrawal(let withdrawal):
            return .identityWithdrawal(to: withdrawal.target)
        }
    }

    // MARK: - Actions

    /// Runs the auth gate, then hands the transfer off. Returns whether the
    /// sheet has finished with the user: it stays open when the PIN prompt was
    /// backed out of, so Confirm can simply be tapped again — everything else,
    /// including a refusal because another transfer is still running, is
    /// announced by a toast on the surface behind it.
    func confirm() async -> Bool {
        guard case .transfer(let request) = mode else { return false }
        return await runner.start(request) != .notAuthorized
    }

    // MARK: - Request accessors

    private var request: InternalTransferRequest? {
        if case .transfer(let request) = mode { return request }
        return nil
    }

    private var routeOrNil: InternalTransferRoute? {
        if case .route(let route)? = request?.kind { return route }
        return nil
    }

    private var topUpOrNil: IdentityTopUpTransfer? {
        if case .identityTopUp(let topUp)? = request?.kind { return topUp }
        return nil
    }

    private var withdrawalOrNil: IdentityWithdrawalTransfer? {
        if case .identityWithdrawal(let withdrawal)? = request?.kind { return withdrawal }
        return nil
    }
}
