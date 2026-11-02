//
//  DashConnectStore.swift
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
import os

protocol DashConnectStore {
    func load() -> [DAppConnection]
    func save(_ connections: [DAppConnection])
    /// Names the wallet and network whose rows this store reads and writes
    /// right now; `nil` when it has no scope.
    var scopeKey: String? { get }
    /// This store fixed to one wallet, and to the network scope it has now.
    /// An operation that outlasts a wallet switch reads and writes through
    /// it, so its rows stay with the wallet it ran for.
    func pinned(toWalletIdHex walletIdHex: String) -> any DashConnectStore
}

final class UserDefaultsDashConnectStore: DashConnectStore {
    /// Posted after a save, with the `scopeKey` written under
    /// (`scopeKeyUserInfoKey`). `PlatformDashConnectDataSource` republishes
    /// its rows on it, whichever store instance wrote them.
    static let didSaveNotification = Notification.Name("UserDefaultsDashConnectStore.didSave")
    static let scopeKeyUserInfoKey = "scopeKey"

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let network: DashConnectNetwork
    private let walletIdHexProvider: () -> String?
    private let devnetNameProvider: () -> String?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        network: DashConnectNetwork,
        walletIdHexProvider: @escaping () -> String? = {
            WalletEnvironment.activeWalletIdHex as String?
        },
        devnetNameProvider: @escaping () -> String? = { DevnetConfiguration.devnetName },
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.network = network
        self.walletIdHexProvider = walletIdHexProvider
        self.devnetNameProvider = devnetNameProvider

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "dashconnect.store")

    /// `nil` until a wallet identifier exists. Connections are wallet-scoped,
    /// so a shared placeholder scope would let one wallet's rows be saved and
    /// then loaded back in a different wallet context — reporting a connection
    /// status that belongs to someone else.
    ///
    /// On devnet the segment also names the configured devnet: every devnet
    /// shares the network code, and the same wallet on devnet B would otherwise
    /// load the connections it approved on devnet A. An unnamed devnet has no
    /// scope, so nothing is stored or loaded for it.
    var storageKey: String? { scopedKey(prefix: "dashconnect.connections.v1") }

    /// `prefix` followed by the network and wallet scope `storageKey` is
    /// built from; `nil` when there is no scope. Other per-wallet DashConnect
    /// stores are keyed the same way.
    func scopedKey(prefix: String) -> String? {
        guard let walletScope = walletIdHexProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !walletScope.isEmpty else { return nil }
        guard let networkScope else { return nil }
        return "\(prefix).\(networkScope).\(walletScope)"
    }

    var scopeKey: String? { storageKey }

    func pinned(toWalletIdHex walletIdHex: String) -> any DashConnectStore {
        pinnedStore(toWalletIdHex: walletIdHex)
    }

    func pinnedStore(toWalletIdHex walletIdHex: String) -> UserDefaultsDashConnectStore {
        let devnetName = devnetNameProvider()
        return UserDefaultsDashConnectStore(
            defaults: defaults,
            network: network,
            walletIdHexProvider: { walletIdHex },
            devnetNameProvider: { devnetName },
            notificationCenter: notificationCenter
        )
    }

    private var networkScope: String? {
        guard network == .devnet else { return network.rawValue }
        guard let name = devnetNameProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty else { return nil }
        return "\(network.rawValue)-\(name)"
    }

    func load() -> [DAppConnection] {
        guard let storageKey else { return [] }
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        guard let rawRows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            logDrop("stored value is not a JSON array")
            return []
        }

        var restored: [DAppConnection] = []
        restored.reserveCapacity(rawRows.count)

        for rawRow in rawRows {
            guard JSONSerialization.isValidJSONObject(rawRow),
                  let rowData = try? JSONSerialization.data(withJSONObject: rawRow),
                  let row = try? decoder.decode(StoredConnection.self, from: rowData) else {
                logDrop("row could not be decoded")
                continue
            }

            guard let contractIdBytes = Self.base58Decode(row.contractId),
                  contractIdBytes.count == 32 else {
                logDrop("row has invalid contractId Base58")
                continue
            }

            restored.append(
                DAppConnection(
                    id: row.contractId,
                    name: row.label,
                    url: row.url,
                    status: row.status,
                    updatedAt: row.updatedAt,
                    loginKind: row.loginKind ?? .twoQR
                )
            )
        }

        return restored
    }

    func save(_ connections: [DAppConnection]) {
        // No wallet scope (or an unnamed devnet) means there is no key this
        // state may be written under; dropping the write is correct, not a
        // silent failure.
        guard let storageKey else { return }

        guard !connections.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            didSave(under: storageKey)
            return
        }

        let rows = connections.map {
            StoredConnection(
                contractId: $0.id,
                label: $0.name,
                url: $0.url,
                status: $0.status,
                updatedAt: $0.updatedAt,
                loginKind: $0.loginKind == .twoQR ? nil : $0.loginKind
            )
        }

        do {
            defaults.set(try encoder.encode(rows), forKey: storageKey)
            didSave(under: storageKey)
        } catch {
            Self.logger.error(
                "DashConnectStore: failed to encode connections on \(self.network.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func didSave(under storageKey: String) {
        notificationCenter.post(
            name: Self.didSaveNotification, object: nil, userInfo: [Self.scopeKeyUserInfoKey: storageKey])
    }

    /// The storage key embeds the wallet id, a persistent user identifier, so
    /// it stays out of the log; the network and the reason are what diagnose a
    /// dropped row anyway.
    private func logDrop(_ reason: String) {
        Self.logger.warning(
            "DashConnectStore: dropping stored row on \(self.network.rawValue, privacy: .public): \(reason, privacy: .public)")
    }

    private struct StoredConnection: Codable {
        let contractId: String
        let label: String
        let url: String
        let status: ConnectionStatus
        let updatedAt: Date
        /// Absent for a two-QR connection, which is every row written before
        /// the one-QR login existed.
        let loginKind: DashConnectLoginKind?
    }

    private static func base58Decode(_ string: String) -> Data? {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
        let input = Array(string.utf8)
        guard !input.isEmpty else { return nil }

        var reverse = [Int8](repeating: -1, count: 128)
        for (index, byte) in alphabet.enumerated() {
            reverse[Int(byte)] = Int8(index)
        }

        var leadingZeros = 0
        while leadingZeros < input.count, input[leadingZeros] == alphabet[0] {
            leadingZeros += 1
        }

        let size = (input.count - leadingZeros) * 733 / 1000 + 1
        var buffer = [UInt8](repeating: 0, count: size)

        for i in leadingZeros ..< input.count {
            let byte = input[i]
            guard byte < 128 else { return nil }
            let digit = reverse[Int(byte)]
            guard digit >= 0 else { return nil }

            var carry = Int(digit)
            for j in stride(from: size - 1, through: 0, by: -1) {
                carry += 58 * Int(buffer[j])
                buffer[j] = UInt8(carry % 256)
                carry /= 256
            }
        }

        var start = 0
        while start < size, buffer[start] == 0 {
            start += 1
        }

        var result = Data(repeating: 0, count: leadingZeros)
        result.append(contentsOf: buffer[start...])
        return result
    }
}

/// An app disconnected on this wallet, as the Connections page lists it
/// under Disconnected. Kept for as long as the wallet is; a later approval
/// of the app removes it.
struct DisconnectedConnection: Codable, Equatable, Identifiable {
    /// The app's contract id (Base58).
    let id: String
    let name: String
    let url: String
    let identityId: String?
    let username: String?
    let disconnectedAt: Date
    /// What the connection gave the app when it was disconnected.
    let access: ConnectionAccess?
    /// When the connection was made; absent in entries from before it was
    /// kept.
    var connectedAt: Date? = nil

    /// The same entry, disconnected at `date`.
    func disconnected(at date: Date) -> DisconnectedConnection {
        DisconnectedConnection(
            id: id, name: name, url: url, identityId: identityId, username: username, disconnectedAt: date,
            access: access, connectedAt: connectedAt)
    }
}

/// The disconnected apps of one wallet and network.
protocol DashConnectHistoryStore {
    /// `nil` when the stored entries cannot be read: unknown, not none.
    func load() -> [DisconnectedConnection]?
    /// Records `entry`, in place of an earlier one of the same app; `false`
    /// when it could not be saved (the stored entries cannot be read, or
    /// writing failed).
    @discardableResult
    func record(_ entry: DisconnectedConnection) -> Bool
    /// Forgets the app: it is connected again.
    func remove(appId: String)
    /// This store fixed to one wallet, as `DashConnectStore.pinned`.
    func pinned(toWalletIdHex walletIdHex: String) -> any DashConnectHistoryStore
}

/// Keyed like `UserDefaultsDashConnectStore`, by network and wallet.
final class UserDefaultsDashConnectHistoryStore: DashConnectHistoryStore {
    private let defaults: UserDefaults
    private let scope: UserDefaultsDashConnectStore

    init(defaults: UserDefaults = .standard, scope: UserDefaultsDashConnectStore) {
        self.defaults = defaults
        self.scope = scope
    }

    convenience init(defaults: UserDefaults = .standard, network: DashConnectNetwork) {
        self.init(defaults: defaults, scope: UserDefaultsDashConnectStore(defaults: defaults, network: network))
    }

    private static let logger = Logger(subsystem: "org.dashfoundation.dash", category: "dashconnect.history")

    private var storageKey: String? { scope.scopedKey(prefix: Self.storagePrefix) }

    /// Entry by entry: one this build cannot read is left out, and the
    /// others still read. `nil` only when the stored value is not a list.
    /// One entry per app, the latest.
    func load() -> [DisconnectedConnection]? {
        guard let stored = readRows() else { return nil }
        if !stored.unreadable.isEmpty {
            Self.logger.warning("DashConnect history: \(stored.unreadable.count, privacy: .public) entry(ies) could not be read")
        }
        var latest: [String: DisconnectedConnection] = [:]
        for entry in stored.entries where (latest[entry.id]?.disconnectedAt ?? .distantPast) <= entry.disconnectedAt {
            latest[entry.id] = entry
        }
        var shown = Set<String>()
        return stored.entries.filter { latest[$0.id] == $0 && shown.insert($0.id).inserted }
    }

    /// Entries this build cannot read are written back as they were, except
    /// one of the same app: the app has one entry, this one.
    @discardableResult
    func record(_ entry: DisconnectedConnection) -> Bool {
        guard let entries = load() else { return false }
        return write(entries.filter { $0.id != entry.id } + [entry], forgetting: [entry.id])
    }

    func remove(appId: String) {
        guard let entries = load() else { return }
        write(entries.filter { $0.id != appId }, forgetting: [appId])
    }

    /// Writes `entries`, and back the entries this build cannot read, except
    /// those naming an app in `forgetting`.
    /// `false` when nothing could be written.
    @discardableResult
    private func write(_ entries: [DisconnectedConnection], forgetting: Set<String>) -> Bool {
        guard let storageKey, let stored = readRows() else { return false }
        do {
            let rows = try entries.map { try JSONSerialization.jsonObject(with: Self.encoder.encode($0)) }
                + stored.unreadable.filter { row in
                    guard let id = (row as? [String: Any])?["id"] as? String else { return true }
                    return !forgetting.contains(id)
                }
            guard !rows.isEmpty else {
                defaults.removeObject(forKey: storageKey)
                return true
            }
            defaults.set(try JSONSerialization.data(withJSONObject: rows), forKey: storageKey)
            return true
        } catch {
            Self.logger.error("DashConnect history could not be written: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The stored entries one by one; `nil` when the stored value is not a
    /// list, which is left in place.
    private func readRows() -> (entries: [DisconnectedConnection], unreadable: [Any])? {
        guard let storageKey, let data = defaults.data(forKey: storageKey) else { return ([], []) }
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            Self.logger.error("DashConnect history is not a JSON array; left in place")
            return nil
        }
        var entries: [DisconnectedConnection] = []
        var unreadable: [Any] = []
        for row in rows {
            if JSONSerialization.isValidJSONObject(row),
               let rowData = try? JSONSerialization.data(withJSONObject: row),
               let entry = try? Self.decoder.decode(DisconnectedConnection.self, from: rowData) {
                entries.append(entry)
            } else {
                unreadable.append(row)
            }
        }
        return (entries, unreadable)
    }

    /// Forgets every network's history of the wallet: it is deleted.
    static func clear(walletIdHex: String, defaults: UserDefaults = .standard) {
        let suffix = ".\(walletIdHex)"
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(storagePrefix + ".") && key.hasSuffix(suffix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static let storagePrefix = "dashconnect.history.v1"

    func pinned(toWalletIdHex walletIdHex: String) -> any DashConnectHistoryStore {
        UserDefaultsDashConnectHistoryStore(defaults: defaults, scope: scope.pinnedStore(toWalletIdHex: walletIdHex))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
