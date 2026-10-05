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
import os
import SwiftDashSDK
import UIKit

/// Sends whose broadcast ended without a word from the network ("status
/// unknown"), followed until the network answers.
///
/// Such a send is handed back to the history instead of an error: its row
/// reads "Waiting for the network" until its stored row is InstantSend-locked
/// or mined, which moves it to "Sent" and raises a one-time notice. The SDK's
/// broadcast probe only prompts that check: an `.accepted` verdict means a
/// node took the bytes, not that the payment will settle, so it is never
/// shown as "Sent" on its own. An `.unresolved` verdict changes nothing.
///
/// A shared instance, not an injected one: the record has to outlive the send
/// screen that made it and be read by the history rows, the home notice and a
/// later send to the same address. It is persisted, so a relaunch keeps a send
/// waiting rather than turning it back into "Sending".
@objc(DWPendingSendOutcomes)
@MainActor
final class PendingSendOutcomes: NSObject, ObservableObject {
    @objc static let shared = PendingSendOutcomes()

    /// Posted on the main queue whenever a send starts or stops waiting, or
    /// the network is heard to have it — a history row's title changes
    /// without its stored row changing.
    nonisolated static let didChangeNotification = Notification.Name("PendingSendOutcomes.didChange")

    struct Entry: Codable, Equatable {
        /// 32 bytes, wire order (`Transaction.txHashData`).
        let txidWire: Data
        let walletId: Data
        /// Nil for a route that does not know the recipient's address.
        let address: String?
        let amount: UInt64
        let sentAt: Date
        /// False for a send that is not a payment to someone (a CoinJoin sweep
        /// chunk) or whose amount is not known here: it settles without the
        /// "went through" notice. Nil in entries stored before it existed.
        var notifies: Bool? = nil
    }

    /// Sends that went through after all: one, or several that settled while
    /// an earlier notice was still up, told together. Each raise is a new `id`,
    /// so two payments of the same amount are two notices.
    struct Notice: Equatable {
        let id = UUID()
        let count: Int
        let total: UInt64
    }

    /// How long a notice stays up.
    static let noticeDuration: TimeInterval = 3

    @Published private(set) var entries: [Data: Entry] = [:]
    @Published private(set) var notice: Notice?

    /// Read by `Transaction.stateTitle`, which is not main-actor isolated.
    /// Mirrors `entries`, written only from the main actor; seeded from the
    /// stored entries on first read, so a row titled before `shared` exists
    /// still reads "Waiting for the network".
    private nonisolated static let waitingTxids =
        OSAllocatedUnfairLock<Set<Data>>(initialState: Set(storedEntries().map(\.txidWire)))

    private nonisolated static let defaultsKey = "PendingSendOutcomes.entries.v1"
    /// A row that is still missing this long after its send is taken as gone
    /// (removed or swept) rather than not yet written by the persister — long,
    /// because on a large wallet the persister can lag by hours.
    nonisolated static let missingRowGrace: TimeInterval = 24 * 60 * 60
    /// A send still unconfirmed this long after it was recorded is no longer
    /// followed: one the network will never take (it spends coins the chain
    /// never had) would otherwise read "Waiting for the network", and warn
    /// on every payment to its address, for good. Its row goes back to
    /// "Sending", where Remove if Not on Network is offered.
    nonisolated static let maxFollowAge: TimeInterval = 7 * 24 * 60 * 60
    /// A send that settles this soon after it was recorded settled while its
    /// "Waiting for the network" notice is still being read: no second
    /// "went through" message on top of it.
    nonisolated static let quietSettleWindow: TimeInterval = 10

    private nonisolated static func storedEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private var verdictWatch: AnyCancellable?
    private var saveWatch: AnyCancellable?
    private var reconcileInFlight = false
    private var reconcileRequestedAgain = false
    /// Waiting sends whose `.accepted` verdict has already been acted on.
    private var acceptedHeard: Set<Data> = []

    private override init() {
        super.init()
        let stored = Self.storedEntries()
        entries = Dictionary(stored.map { ($0.txidWire, $0) }, uniquingKeysWith: { a, _ in a })
        publishWaitingTxids()
        updateSaveWatch()
    }

    /// Watches saves only while a send is waiting. A save that touched the
    /// wallet's transactions may have locked or mined one; the bookkeeping
    /// saves are skipped with the home feed's filter (inspected on the
    /// posting thread, before the hop). Throttled: during sync the persister
    /// saves several times a second.
    private func updateSaveWatch() {
        guard !entries.isEmpty else {
            saveWatch = nil
            return
        }
        guard saveWatch == nil else { return }
        saveWatch = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .filter { HomeViewModel.saveTouchesFeedRows($0) }
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcile() }
            }
    }

    // MARK: - Recording

    /// The broadcast of `txidWire` ended with no answer from the network.
    /// Called through `WalletSendService.followUnknownOutcome` (by
    /// `unknownOutcomeError`, for every route it maps to `broadcastUnknown`,
    /// and for the headless BIP70 broadcast handed off after the merchant's
    /// acknowledgement), by the CoinJoin sweep for a
    /// chunk (`SwiftDashSDKTransactionSender.sweepCoinJoin`) and by the
    /// awaited headless BIP70 payment (`SendCoinsService.payWithDashUrl`).
    ///
    /// - Parameter walletId: the sending wallet when the caller knows it (a
    ///   sweep that may outlive a wallet switch); the active wallet otherwise.
    /// - Returns: false when the send could not be followed (no active
    ///   wallet), so its row will not say "Waiting for the network".
    @discardableResult
    func recordUnknownOutcome(
        txidWire: Data, address: String?, amount: UInt64, notifies: Bool = true, walletId: Data? = nil
    ) -> Bool {
        guard let walletId = walletId ?? SwiftDashSDKHost.shared.wallet?.walletId else {
            DWLogger.log("💸 TXSEND :: unknown outcome not tracked, no active wallet")
            return false
        }
        entries[txidWire] = Entry(
            txidWire: txidWire,
            walletId: walletId,
            address: address,
            amount: amount,
            sentAt: Date(),
            notifies: notifies)
        DWLogger.log("💸 TXSEND :: waiting for the network on \(Transaction.displayHex(txidWire))")
        didChangeEntries()
        reconcile()
        return true
    }

    /// Stop following `txidsWire` — their rows were removed by the user
    /// (`UnconfirmedTransactionRemover`).
    func forget(txidsWire: [Data], reason: String = "removed") {
        var changed = false
        for txid in txidsWire where entries.removeValue(forKey: txid) != nil {
            changed = true
            DWLogger.log("💸 TXSEND :: \(Transaction.displayHex(txid)) \(reason), no longer tracked")
        }
        if changed { didChangeEntries() }
    }

    /// Stop following every send: the wallet they belong to was wiped. (A
    /// network switch keeps them: entries are per wallet, and the other
    /// network's sends are settled once its wallet runs again.)
    @objc func forgetAll() {
        // A raised notice not yet shown goes too: it is the wiped wallet's.
        notice = nil
        guard !entries.isEmpty else { return }
        DWLogger.log("💸 TXSEND :: \(entries.count) waiting send(s) no longer tracked: wallet wiped")
        entries = [:]
        notice = nil
        didChangeEntries()
    }

    // MARK: - Reading

    /// Whether `txidWire` is a send still waiting for the network.
    nonisolated static func isWaiting(txidWire: Data) -> Bool {
        waitingTxids.withLock { $0.contains(txidWire) }
    }

    /// The newest send to `address` that the network has not confirmed yet,
    /// in the active wallet.
    func waitingPayment(to address: String) -> Entry? {
        let walletId = SwiftDashSDKHost.shared.wallet?.walletId
        return entries.values
            .filter { $0.address == address && $0.walletId == walletId }
            .max { $0.sentAt < $1.sentAt }
    }

    // MARK: - Verdicts

    /// A wallet removed from the device takes its waiting sends with it: they
    /// would never settle against any wallet again. Checked when a wallet's
    /// host is published, not on every save; only with the keychain readable
    /// (a locked device lists no wallets) and a non-empty list.
    func dropSendsOfRemovedWallets() {
        guard !entries.isEmpty, UIApplication.shared.isProtectedDataAvailable,
              let stored = try? SwiftDashSDKHost.persistedWalletIds(), !stored.isEmpty else { return }
        let orphans = entries.values.filter { !stored.contains($0.walletId) }.map(\.txidWire)
        if !orphans.isEmpty {
            forget(txidsWire: orphans, reason: "its wallet was removed")
        }
    }

    /// Follow `manager`'s probe verdicts. Called for each manager the host
    /// configures; replaces the previous watch. Also settles, once, the sends
    /// that went through while the app was closed.
    func observeVerdicts(of manager: PlatformWalletManager) {
        dropSendsOfRemovedWallets()
        reconcile()
        verdictWatch = manager.$outgoingTransactionVerdicts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] verdicts in
                MainActor.assumeIsolated { self?.apply(Array(verdicts.values)) }
            }
    }

    /// An `.accepted` verdict on a waiting send re-reads the stored rows: the
    /// lock or block that settles it may already be there. The verdict itself
    /// changes nothing — a node that took the bytes is not a settled payment.
    private func apply(_ events: [OutgoingTransactionProbeEvent]) {
        let heard = Self.acceptances(
            in: events.map { (txidWire: $0.txidWire, walletId: $0.walletId, accepted: $0.verdict == .accepted) },
            following: entries, alreadyHeard: acceptedHeard)
        acceptedHeard = heard.accepted
        if heard.isNew { reconcile() }
    }

    // MARK: - Settling against the stored rows

    /// Drop the sends whose stored row is now InstantSend-locked or mined (or
    /// gone). Each one that settled raises the notice.
    private func reconcile() {
        guard !entries.isEmpty else { return }
        guard !reconcileInFlight else {
            reconcileRequestedAgain = true
            return
        }
        // Only the active wallet's sends can settle against its rows.
        let activeWalletId = SwiftDashSDKHost.shared.wallet?.walletId
        let pending = entries.filter { $0.value.walletId == activeWalletId }
        guard !pending.isEmpty else { return }
        reconcileInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = SwiftDashSDKWalletSource.fetch(txids: Set(pending.keys))
            await MainActor.run {
                guard let self else { return }
                if let activeWalletId {
                    // A failed read is a nil snapshot: the policy decides
                    // nothing for it.
                    self.settle(
                        pending: pending,
                        walletId: snapshot?.walletId ?? activeWalletId,
                        rows: snapshot.map(Self.rowStates(of:)))
                }
                self.reconcileInFlight = false
                if self.reconcileRequestedAgain {
                    self.reconcileRequestedAgain = false
                    self.reconcile()
                }
            }
        }
    }

    private static func rowStates(of snapshot: SwiftDashSDKWalletTransactionSnapshot) -> [Data: RowState] {
        Dictionary(
            snapshot.transactions.map { ($0.txHashData, $0.state == .processing ? RowState.processing : .settled) },
            uniquingKeysWith: { a, _ in a })
    }

    private func settle(pending: [Data: Entry], walletId: Data, rows: [Data: RowState]?) {
        let decision = Self.settlement(
            of: pending, stillFollowed: { [entries] in entries[$0] != nil },
            walletId: walletId, rows: rows, now: Date())
        for txid in decision.expired {
            DWLogger.log("💸 TXSEND :: \(Transaction.displayHex(txid)) still unconfirmed after a week, no longer tracked")
        }
        for txid in decision.settled {
            DWLogger.log("💸 TXSEND :: \(Transaction.displayHex(txid)) settled on chain")
        }
        for txid in decision.gone {
            DWLogger.log("💸 TXSEND :: \(Transaction.displayHex(txid)) left the wallet, no longer tracked")
        }
        for entry in decision.notifying {
            notice = Self.merged(notice, adding: entry.amount)
        }
        guard !decision.isEmpty else { return }
        entries = Self.applying(decision, to: entries)
        didChangeEntries()
    }

    /// Clear `notice` if it is still the one with `id` — a notice raised
    /// meanwhile stays.
    func dismissNotice(id: UUID) {
        guard notice?.id == id else { return }
        notice = nil
    }

    // MARK: - Private

    private func didChangeEntries() {
        publishWaitingTxids()
        updateSaveWatch()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        if let data = try? JSONEncoder().encode(Array(entries.values)) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func publishWaitingTxids() {
        let txids = Set(entries.keys)
        Self.waitingTxids.withLock { $0 = txids }
    }
}

// MARK: - Settlement policy

/// The rules that decide when a waiting send settles, expires or is dropped,
/// and how notices merge. Pure (no store, no clock, no SDK), so they can be
/// tested on their own; `PendingSendOutcomes` applies them.
extension PendingSendOutcomes {
    /// A stored row as the policy sees it.
    enum RowState: Equatable {
        /// Neither InstantSend-locked nor mined.
        case processing
        /// Locked, mined (or otherwise final).
        case settled
    }

    struct SettlementDecision: Equatable {
        /// Locked or mined: no longer followed.
        var settled: [Data] = []
        /// The settled ones that raise the "went through" notice.
        var notifying: [Entry] = []
        /// Still unconfirmed after `maxFollowAge`: no longer followed.
        var expired: [Data] = []
        /// Missing from the rows after `missingRowGrace`: no longer followed.
        var gone: [Data] = []

        var isEmpty: Bool { settled.isEmpty && expired.isEmpty && gone.isEmpty }
    }

    /// What a read of the stored rows decides for `pending`.
    ///
    /// - Parameters:
    ///   - stillFollowed: whether a send is still followed now; one forgotten
    ///     (removed, wiped) while the rows were being read is left alone.
    ///   - walletId: the wallet whose rows were read; other wallets' sends are
    ///     left alone.
    ///   - rows: the rows found, by wire-order txid; nil when the read failed,
    ///     which decides nothing (a failed read is not "the row is gone").
    nonisolated static func settlement(
        of pending: [Data: Entry],
        stillFollowed: (Data) -> Bool,
        walletId: Data,
        rows: [Data: RowState]?,
        now: Date
    ) -> SettlementDecision {
        var decision = SettlementDecision()
        guard let rows else { return decision }
        for entry in pending.values.sorted(by: { $0.sentAt < $1.sentAt })
        where entry.walletId == walletId && stillFollowed(entry.txidWire) {
            let age = now.timeIntervalSince(entry.sentAt)
            switch rows[entry.txidWire] {
            case .processing:
                if age > maxFollowAge { decision.expired.append(entry.txidWire) }
            case .settled:
                decision.settled.append(entry.txidWire)
                // No second message on top of the unknown-outcome notice that
                // may still be up for a send that settled straight away.
                if entry.notifies != false, age > quietSettleWindow {
                    decision.notifying.append(entry)
                }
            case nil:
                if age > missingRowGrace { decision.gone.append(entry.txidWire) }
            }
        }
        return decision
    }

    /// `entries` without the sends `decision` stops following.
    nonisolated static func applying(_ decision: SettlementDecision, to entries: [Data: Entry]) -> [Data: Entry] {
        var remaining = entries
        for txid in decision.expired + decision.settled + decision.gone {
            remaining.removeValue(forKey: txid)
        }
        return remaining
    }

    /// `current` with one more payment of `amount` in it — a notice not yet
    /// dismissed absorbs the next settlement instead of being overwritten.
    /// Each result is a new notice (new `id`); the total saturates.
    nonisolated static func merged(_ current: Notice?, adding amount: UInt64) -> Notice {
        guard let current else { return Notice(count: 1, total: amount) }
        let (total, overflow) = current.total.addingReportingOverflow(amount)
        return Notice(count: current.count + 1, total: overflow ? UInt64.max : total)
    }

    /// The followed sends with an `.accepted` verdict from their own wallet,
    /// and whether any of them was not heard before (only then are the rows
    /// read again: the verdicts are republished on every probe change).
    nonisolated static func acceptances(
        in verdicts: [(txidWire: Data, walletId: Data, accepted: Bool)],
        following entries: [Data: Entry],
        alreadyHeard: Set<Data>
    ) -> (accepted: Set<Data>, isNew: Bool) {
        let accepted = Set(verdicts.filter { verdict in
            verdict.accepted && entries[verdict.txidWire]?.walletId == verdict.walletId
        }.map(\.txidWire))
        return (accepted, !accepted.subtracting(alreadyHeard).isEmpty)
    }
}
