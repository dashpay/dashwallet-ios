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
import SwiftData
import SwiftDashSDK

/// The explanation of the current wallet's charged Shielded registration failure.
///
/// `refresh()` first turns the scope's unresolved create into a charged-failure record once the
/// SDK's activity row proves its inputs consumed (`ShieldedChargedFailureStore.reconcileUnresolved`),
/// then reads the record of one (network, wallet) scope, fixes the returned amount from the
/// fallback address's balance the first time it is seen, and builds the text from the figures as
/// they are now. No record in scope means no text.
@MainActor
final class ShieldedChargedFailureExplanationModel: ObservableObject {
    private typealias Policy = PlatformPaymentIdentityFundingPolicy

    private let store: ShieldedChargedFailureStore
    private let networkRawValue: Int
    private let walletIdHex: String?
    /// nil when the Platform balance read failed — unknown, never an empty wallet.
    private let candidates: () -> [Policy.Candidate]?
    private let nextReceive: () -> Policy.Candidate?
    private let fundingDuffs: (_ isContested: Bool) -> UInt64
    private let inputsConsumed: (_ identityId: Data) -> Bool

    /// nil when there is no record in scope.
    @Published private(set) var text: (block1: String, block2: String?)?
    /// A record exists and the returned amount is not fixed yet.
    @Published private(set) var needsBalanceUpdates = false
    /// A record exists in scope, whatever its figures.
    @Published private(set) var hasRecord = false
    /// The name of the registration the record is about; nil without a record.
    @Published private(set) var username: String?
    /// A create whose outcome the SDK has not proven yet is kept in scope.
    @Published private(set) var hasUnresolvedAttempt = false

    init(
        store: ShieldedChargedFailureStore,
        networkRawValue: Int,
        walletIdHex: String?,
        candidates: @escaping () -> [PlatformPaymentIdentityFundingPolicy.Candidate]?,
        nextReceive: @escaping () -> PlatformPaymentIdentityFundingPolicy.Candidate?,
        fundingDuffs: @escaping (_ isContested: Bool) -> UInt64,
        inputsConsumed: @escaping (_ identityId: Data) -> Bool = { _ in false }
    ) {
        self.store = store
        self.networkRawValue = networkRawValue
        self.walletIdHex = walletIdHex
        self.candidates = candidates
        self.nextReceive = nextReceive
        self.fundingDuffs = fundingDuffs
        self.inputsConsumed = inputsConsumed
    }

    /// The model of the active network and wallet, reading the live Platform balances.
    static func forCurrentScope() -> ShieldedChargedFailureExplanationModel {
        ShieldedChargedFailureExplanationModel(
            store: ShieldedChargedFailureStore(),
            networkRawValue: WalletEnvironment.networkKind.rawValue,
            walletIdHex: WalletEnvironment.activeWalletIdHex as String?,
            candidates: { try? Policy.currentCandidates() },
            nextReceive: {
                // The derived row carries the bech32m address only; its type and hash come from the
                // same decoder the funding code uses. Its balance is read from the persisted rows.
                guard let address = PlatformAddressSyncCoordinator.shared.derivedAddresses.nextReceiveAddress,
                      let parsed = PlatformAddressSyncCoordinator.parsePlatformRecipient(bech32m: address.address),
                      let candidates = try? Policy.currentCandidates()
                else { return nil }
                let balance = candidates.first {
                    $0.addressType == parsed.ffiAddressType && $0.hash == parsed.hash
                }?.balance ?? 0
                return Policy.Candidate(addressType: parsed.ffiAddressType, hash: parsed.hash, balance: balance)
            },
            fundingDuffs: {
                ContestedUsernameFee.shared.amounts.newIdentityFundingDuffs(isContested: $0, fromShielded: false)
            },
            inputsConsumed: activityProvesInputsConsumed(identityId:))
    }

    /// Whether an activity row of the active wallet for the Type-20 create `identityId` has
    /// the SDK's `InputsConsumed` status: its inputs are spent and its identity was not
    /// created. `Failed` proves no charge (a create that never left the wallet, notes released),
    /// nor does `Confirmed` prove the identity created (a scan confirms a create's row from its
    /// outputs before the outcome is read). False when the rows cannot be read.
    static func activityProvesInputsConsumed(identityId: Data) -> Bool {
        guard let container = SwiftDashSDKHost.shared.modelContainer,
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId else { return false }
        let kind = ShieldedActivityItem.Kind.identityCreate.rawValue
        let inputsConsumed = ShieldedActivityItem.Status.inputsConsumed.rawValue
        var descriptor = FetchDescriptor<PersistentShieldedActivity>(predicate: #Predicate {
            $0.walletId == walletId && $0.kindTag == kind && $0.identityId == identityId
                && $0.status == inputsConsumed
        })
        descriptor.fetchLimit = 1
        return ((try? ModelContext(container).fetchCount(descriptor)) ?? 0) > 0
    }

    func refresh() {
        store.reconcileUnresolved(
            networkRawValue: networkRawValue, walletIdHex: walletIdHex, inputsConsumed: inputsConsumed)
        hasUnresolvedAttempt = store.unresolvedAttempt(networkRawValue: networkRawValue, walletIdHex: walletIdHex) != nil
        guard var record = store.record(networkRawValue: networkRawValue, walletIdHex: walletIdHex) else {
            text = nil
            needsBalanceUpdates = false
            hasRecord = false
            username = nil
            return
        }
        hasRecord = true
        username = record.username
        let current = candidates()

        if record.returnedDuffs == nil, let current {
            let fallbackCredits = current.first {
                Data([$0.addressType]) + $0.hash == record.fallbackAddress
            }?.balance ?? 0
            if let returned = Policy.returnedDuffs(
                snapshotCredits: record.snapshotCredits,
                currentCredits: fallbackCredits,
                exitDenominationDuffs: record.exitDenominationDuffs) {
                store.fixReturnedAmount(returned, networkRawValue: networkRawValue, walletIdHex: walletIdHex)
                // Re-read: the form may have fixed another value first, and the first wins.
                record = store.record(networkRawValue: networkRawValue, walletIdHex: walletIdHex) ?? record
            }
        }

        needsBalanceUpdates = record.returnedDuffs == nil
        guard let returned = record.returnedDuffs else {
            text = ShieldedChargedFailureExplanation.text(returnedDuffs: nil, amountToAddDuffs: nil)
            return
        }
        // Unknown until the next receive address is derived again, e.g. right after a relaunch,
        // and while the balance cannot be read.
        var toAdd: UInt64?
        if let current, let next = nextReceive() {
            toAdd = Policy.amountToAddDuffs(
                candidates: current, nextReceive: next, fundingDuffs: fundingDuffs(record.isContested))
        }
        text = ShieldedChargedFailureExplanation.text(returnedDuffs: returned, amountToAddDuffs: toAdd)
    }
}
