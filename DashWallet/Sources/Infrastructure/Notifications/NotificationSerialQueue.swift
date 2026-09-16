//
//  NotificationSerialQueue.swift
//  DashWallet
//

import Foundation

/// The ordering boundary the notification module's mutations share.
///
/// Posting a notification reads the store's unseen count and submits a request
/// carrying it; activation clears the tray, zeroes the badge and marks every
/// event seen. Both are multi-step and both suspend, so run on their own they
/// interleave: a post can compute a count, suspend, and submit it after the
/// clear has already zeroed the badge and emptied the store — leaving the tray
/// and the badge disagreeing with persisted read state, with nothing to correct
/// them until the next event.
///
/// Work runs in submission order, each item awaiting the previous one, so a
/// post and a clear can never overlap.
actor NotificationSerialQueue {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ body: @escaping @Sendable () async -> T) async -> T {
        let previous = tail
        let work = Task { () -> T in
            await previous?.value
            return await body()
        }
        tail = Task { _ = await work.value }
        return await work.value
    }
}
