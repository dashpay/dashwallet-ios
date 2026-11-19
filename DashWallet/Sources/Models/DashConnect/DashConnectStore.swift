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

/// Deletes what the DashConnect stores keep for one wallet.
enum DashConnectStores {
    /// Ends the keys of the grant records that internal TestFlight builds
    /// wrote; nothing reads or writes them now.
    private static let legacyGrantsSuffix = ".app-connect-responses.v1"

    /// Held by `removeAll` and `removeAllWallets`, and by `excludingWipe`.
    private static let wipeLock = NSLock()

    /// Runs `body` while no wipe of the stores runs. A wipe does not take the
    /// wallet's operation gate, so a read-change-save of the intents runs
    /// inside this: a wipe then either comes first and the write finds
    /// nothing, or comes after and removes what it saved. Not reentrant.
    static func excludingWipe<T>(_ body: () -> T) -> T {
        wipeLock.lock()
        defer { wipeLock.unlock() }
        return body()
    }

    /// The suffixes a key under `UserDefaultsDashConnectStore.keyPrefix` can
    /// carry after the wallet segment: none (the row cache), the intents, the
    /// legacy grants.
    private static let scopedSuffixes = [
        "",
        UserDefaultsAppConnectIntentStore.keySuffix,
        legacyGrantsSuffix,
    ]

    /// Removes every key of the wallet, on every network scope. The wallet is
    /// the segment after the last dot of what follows the prefix: the wallet
    /// id hex holds no dot, while a devnet name may.
    static func removeAll(walletIdHex: String, in defaults: UserDefaults) {
        wipeLock.lock()
        defer { wipeLock.unlock() }
        let prefix = UserDefaultsDashConnectStore.keyPrefix
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let scoped = key.dropFirst(prefix.count)
            for suffix in scopedSuffixes {
                let body = scoped.dropLast(suffix.count)
                guard scoped.hasSuffix(suffix),
                      let dot = body.lastIndex(of: "."),
                      dot > body.startIndex,
                      body[body.index(after: dot)...] == walletIdHex
                else { continue }
                defaults.removeObject(forKey: key)
                break
            }
        }
    }

    /// Removes every DashConnect key, whatever wallet id or suffix it carries,
    /// orphans included: the full wipe leaves nothing of the feature behind.
    static func removeAllWallets(in defaults: UserDefaults) {
        wipeLock.lock()
        defer { wipeLock.unlock() }
        let prefix = UserDefaultsDashConnectStore.keyPrefix
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
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
    var storageKey: String? {
        guard let walletScope = walletIdHexProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !walletScope.isEmpty else { return nil }
        guard let networkScope else { return nil }
        return "\(Self.keyPrefix)\(networkScope).\(walletScope)"
    }

    /// Starts every key this store and the stores scoped from it write.
    static let keyPrefix = "dashconnect.connections.v1."

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

            var connection = DAppConnection(
                id: row.contractId,
                name: row.label,
                url: row.url,
                status: row.status,
                updatedAt: row.updatedAt,
                seenOn: Set(row.seenOn ?? [])
            )
            connection.responseMayRemain = row.responseMayRemain ?? false
            restored.append(connection)
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
                seenOn: $0.seenOn.isEmpty ? nil : $0.seenOn.sorted(),
                responseMayRemain: $0.responseMayRemain ? true : nil
            )
        }

        do {
            defaults.set(try encoder.encode(rows), forKey: storageKey)
            didSave(under: storageKey)
        } catch {
            Self.logger.error(
                "DashConnectStore: failed to encode connections on \(self.network.rawValue, privacy: .public): \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
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
        /// Absent in rows written before it was kept.
        let seenOn: [String]?
        /// Absent when false, and in rows written before it was kept.
        let responseMayRemain: Bool?
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
