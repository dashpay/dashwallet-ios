//
//  SwapPendingGate.swift
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

import CoreData
import Foundation

/// Serialises consecutive swaps: after a swap's Dash transaction is broadcast, the next swap is
/// blocked until that transaction receives its InstantSend lock (or a short timeout elapses).
///
/// Rationale: submitting the next swap before the previous one has settled on the Dash side can
/// chain unsettled outputs into a fresh vault deposit. Waiting for the IS-lock (≈5–10 s) gives the
/// previous deposit a clean, instantly-final state before the next one is built.
final class SwapPendingGate {
    static let shared = SwapPendingGate()

    /// Safety cap: never block a new swap longer than this even if no IS-lock notification arrives
    /// (e.g. a non-IS-eligible tx). Keeps the gate from wedging the UI permanently.
    private let timeout: TimeInterval = 60

    private let lock = NSLock()
    /// Wire-order txid (`Transaction.txHashData` convention) of the swap tx being gated on.
    private var pendingTxidWire: Data?
    private var registeredAt: Date?
    private var observer: NSObjectProtocol?

    private init() {}

    /// True while a previously-broadcast swap tx is still awaiting its InstantSend lock.
    var isAwaitingISLock: Bool {
        lock.lock(); defer { lock.unlock() }
        guard pendingTxidWire != nil, let registeredAt else { return false }
        if Date().timeIntervalSince(registeredAt) > timeout {
            clearLocked()
            return false
        }
        return true
    }

    /// Call right after a swap's Dash tx is broadcast. Begins gating until the tx is IS-locked.
    /// - Parameter txidWire: wire-order txid returned by `WalletSendService.send`.
    func register(txidWire: Data) {
        lock.lock()
        defer { lock.unlock() }

        pendingTxidWire = txidWire
        registeredAt = Date()
        if let observer { NotificationCenter.default.removeObserver(observer) }

        // SDK re-plumb: the Rust persister updates a transaction's context byte
        // (0=mempool → 1=instantSend) and saves, which fires NSManagedObjectContextDidSave —
        // the same signal HomeViewModel uses to refresh its tx list. On each save we re-read
        // the gated tx's `state`; `.ok` means context >= 1 (InstantSend-locked or better).
        // Assign inside the lock so it can't race with `clearLocked()` (also lock-held).
        // `addObserver(forName:…)` only registers — the block is never invoked synchronously,
        // so `handle()` (which re-acquires the lock) cannot deadlock here.
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleSave()
        }
    }

    private func handleSave() {
        lock.lock()
        let expected = pendingTxidWire
        lock.unlock()

        guard let expected,
              let tx = SwiftDashSDKWalletSource.fetch(txid: expected),
              tx.state == .ok  // context >= 1: InstantSend-locked (or inBlock/chainLocked)
        else { return }

        DSLogger.log("SwapPendingGate: IS-lock observed for \(Transaction.displayHex(expected)) — gate released")
        lock.lock()
        clearLocked()
        lock.unlock()
    }

    /// Must be called with `lock` held.
    private func clearLocked() {
        pendingTxidWire = nil
        registeredAt = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}
