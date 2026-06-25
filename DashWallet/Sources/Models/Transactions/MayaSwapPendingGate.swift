//
//  MayaSwapPendingGate.swift
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

/// Serialises consecutive swaps: after a swap's Dash transaction is broadcast, the next swap is
/// blocked until that transaction receives its InstantSend lock (or a short timeout elapses).
///
/// Rationale: submitting the next swap before the previous one has settled on the Dash side can
/// chain unsettled outputs into a fresh vault deposit. Waiting for the IS-lock (≈5–10 s) gives the
/// previous deposit a clean, instantly-final state before the next one is built.
final class MayaSwapPendingGate {
    static let shared = MayaSwapPendingGate()

    /// Safety cap: never block a new swap longer than this even if no IS-lock notification arrives
    /// (e.g. a non-IS-eligible tx). Keeps the gate from wedging the UI permanently.
    private let timeout: TimeInterval = 60

    private let lock = NSLock()
    private var pendingTxid: String?
    private var registeredAt: Date?
    private var observer: NSObjectProtocol?

    private init() {}

    /// True while a previously-broadcast swap tx is still awaiting its InstantSend lock.
    var isAwaitingISLock: Bool {
        lock.lock(); defer { lock.unlock() }
        guard pendingTxid != nil, let registeredAt else { return false }
        if Date().timeIntervalSince(registeredAt) > timeout {
            clearLocked()
            return false
        }
        return true
    }

    /// Call right after a swap's Dash tx is published. Begins gating until the tx is IS-locked.
    func register(txid: String) {
        lock.lock()
        defer { lock.unlock() }

        pendingTxid = txid
        registeredAt = Date()
        if let observer { NotificationCenter.default.removeObserver(observer) }

        // Assign inside the lock so it can't race with `clearLocked()` (also lock-held).
        // `addObserver(forName:…)` only registers — the block is never invoked synchronously,
        // so `handle()` (which re-acquires the lock) cannot deadlock here.
        observer = NotificationCenter.default.addObserver(
            forName: .DSTransactionManagerTransactionStatusDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handle(notification)
        }
    }

    private func handle(_ notification: Notification) {
        lock.lock()
        let expected = pendingTxid
        lock.unlock()

        guard let expected,
              let userInfo = notification.userInfo,
              let tx = userInfo[DSTransactionManagerNotificationTransactionKey] as? DSTransaction,
              tx.txHashHexString == expected,
              let changes = userInfo[DSTransactionManagerNotificationTransactionChangesKey] as? [String: Any],
              changes[DSTransactionManagerNotificationInstantSendTransactionLockKey] != nil
        else { return }

        DSLogger.log("MayaSwapPendingGate: IS-lock received for \(expected) — gate released")
        lock.lock()
        clearLocked()
        lock.unlock()
    }

    /// Must be called with `lock` held.
    private func clearLocked() {
        pendingTxid = nil
        registeredAt = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}
