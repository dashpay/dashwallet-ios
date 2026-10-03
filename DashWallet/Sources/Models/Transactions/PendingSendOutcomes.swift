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

/// Sends whose broadcast ended without a word from the network ("status
/// unknown"), followed until the network answers.
///
/// Such a send is handed back to the history instead of an error: its row
/// reads "Waiting for the network" until the SDK's broadcast probe reports the
/// network has it (`OutgoingTransactionVerdict.accepted`), or its stored row is
/// InstantSend-locked or mined. Either moves it to "Sent" and raises a one-time
/// notice. An `.unresolved` verdict changes nothing — the send keeps waiting.
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
        let address: String
        let amount: UInt64
        let sentAt: Date
        /// The probe heard the network take it; the stored row has not caught
        /// up yet (still mempool). Shown as "Sent".
        var networkAccepted: Bool
    }

    /// What a history row shows for a send that is still unconfirmed locally.
    enum DisplayStatus {
        case waiting
        case accepted
    }

    /// A send that went through after all. Equatable for the toast's animation.
    struct Notice: Equatable {
        let amount: UInt64
    }

    @Published private(set) var entries: [Data: Entry] = [:]
    @Published var notice: Notice?
    private(set) var noticeRaisedAt: Date?

    /// Read by `Transaction.stateTitle`, which is not main-actor isolated.
    /// Mirrors `entries`, written only from the main actor.
    private nonisolated static let displayStatuses =
        OSAllocatedUnfairLock<[Data: DisplayStatus]>(initialState: [:])

    private static let defaultsKey = "PendingSendOutcomes.entries.v1"
    /// A row that is still missing this long after its send is taken as gone
    /// (removed or swept) rather than not yet written by the persister.
    private static let missingRowGrace: TimeInterval = 60 * 60

    private var verdictWatch: AnyCancellable?
    private var saveWatch: AnyCancellable?
    private var reconcileInFlight = false
    private var reconcileRequestedAgain = false

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Dictionary(stored.map { ($0.txidWire, $0) }, uniquingKeysWith: { a, _ in a })
        }
        publishDisplayStatuses()
        // A save that touched the wallet's transactions may have locked or
        // mined a waiting send. Throttled: during sync the persister saves
        // several times a second.
        saveWatch = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcile() }
            }
    }

    // MARK: - Recording

    /// The broadcast of `txidWire` ended with no answer from the network.
    @objc func recordUnknownOutcome(txidWire: Data, address: String, amount: UInt64) {
        guard let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
            DWLogger.log("💸 TXSEND :: unknown outcome not tracked, no active wallet")
            return
        }
        entries[txidWire] = Entry(
            txidWire: txidWire,
            walletId: walletId,
            address: address,
            amount: amount,
            sentAt: Date(),
            networkAccepted: false)
        DWLogger.log("💸 TXSEND :: waiting for the network on \(Transaction.displayHex(txidWire))")
        didChangeEntries()
        // A verdict may already be in (the probe runs right after an
        // uncertain broadcast); otherwise it arrives through the watch.
        if let manager = SwiftDashSDKHost.shared.manager {
            apply(Array(manager.outgoingTransactionVerdicts.values))
        }
        reconcile()
    }

    // MARK: - Reading

    nonisolated static func displayStatus(txidWire: Data) -> DisplayStatus? {
        displayStatuses.withLock { $0[txidWire] }
    }

    /// The newest send to `address` that the network has not confirmed yet,
    /// in the active wallet.
    func waitingPayment(to address: String) -> Entry? {
        let walletId = SwiftDashSDKHost.shared.wallet?.walletId
        return entries.values
            .filter { $0.address == address && $0.walletId == walletId && !$0.networkAccepted }
            .max { $0.sentAt < $1.sentAt }
    }

    // MARK: - Verdicts

    /// Follow `manager`'s probe verdicts. Called for each manager the host
    /// configures; replaces the previous watch.
    func observeVerdicts(of manager: PlatformWalletManager) {
        verdictWatch = manager.$outgoingTransactionVerdicts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] verdicts in
                MainActor.assumeIsolated { self?.apply(Array(verdicts.values)) }
            }
    }

    private func apply(_ events: [OutgoingTransactionProbeEvent]) {
        var changed = false
        for event in events {
            guard var entry = entries[event.txidWire],
                  entry.walletId == event.walletId,
                  !entry.networkAccepted else { continue }
            switch event.verdict {
            case .accepted:
                entry.networkAccepted = true
                entries[event.txidWire] = entry
                changed = true
                DWLogger.log("💸 TXSEND :: network has \(event.txidDisplayHex), shown as sent")
                raiseNotice(for: entry)
            case .unresolved:
                continue
            }
        }
        if changed { didChangeEntries() }
    }

    // MARK: - Settling against the stored rows

    /// Drop the sends whose stored row is now InstantSend-locked or mined (or
    /// gone). A send that settles without an earlier `.accepted` verdict
    /// raises the notice here.
    private func reconcile() {
        guard !entries.isEmpty else { return }
        guard !reconcileInFlight else {
            reconcileRequestedAgain = true
            return
        }
        reconcileInFlight = true
        let pending = entries
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = SwiftDashSDKWalletSource.fetch(txids: Set(pending.keys))
            await MainActor.run {
                guard let self else { return }
                if let snapshot {
                    self.settle(pending: pending, snapshot: snapshot)
                }
                self.reconcileInFlight = false
                if self.reconcileRequestedAgain {
                    self.reconcileRequestedAgain = false
                    self.reconcile()
                }
            }
        }
    }

    private func settle(pending: [Data: Entry], snapshot: SwiftDashSDKWalletTransactionSnapshot) {
        let rows = Dictionary(snapshot.transactions.map { ($0.txHashData, $0) },
                              uniquingKeysWith: { a, _ in a })
        var changed = false
        for entry in pending.values where entry.walletId == snapshot.walletId {
            if let row = rows[entry.txidWire] {
                guard row.state != .processing else { continue }
                DWLogger.log("💸 TXSEND :: \(Transaction.displayHex(entry.txidWire)) settled on chain")
                if entries[entry.txidWire]?.networkAccepted == false {
                    raiseNotice(for: entry)
                }
            } else {
                guard Date().timeIntervalSince(entry.sentAt) > Self.missingRowGrace else { continue }
                DWLogger.log("💸 TXSEND :: \(Transaction.displayHex(entry.txidWire)) left the wallet, no longer tracked")
            }
            entries.removeValue(forKey: entry.txidWire)
            changed = true
        }
        if changed { didChangeEntries() }
    }

    // MARK: - Private

    private func raiseNotice(for entry: Entry) {
        noticeRaisedAt = Date()
        notice = Notice(amount: entry.amount)
    }

    private func didChangeEntries() {
        publishDisplayStatuses()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        if let data = try? JSONEncoder().encode(Array(entries.values)) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func publishDisplayStatuses() {
        let statuses = entries.mapValues { $0.networkAccepted ? DisplayStatus.accepted : .waiting }
        Self.displayStatuses.withLock { $0 = statuses }
    }
}
