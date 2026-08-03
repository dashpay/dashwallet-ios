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

protocol DashConnectStore {
    func load() -> [DAppConnection]
    func save(_ connections: [DAppConnection])
}

final class UserDefaultsDashConnectStore: DashConnectStore {
    private let defaults: UserDefaults
    private let network: DashConnectNetwork
    private let walletIdHexProvider: () -> String?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        network: DashConnectNetwork,
        walletIdHexProvider: @escaping () -> String? = {
            WalletEnvironment.activeWalletIdHex as String?
        }
    ) {
        self.defaults = defaults
        self.network = network
        self.walletIdHexProvider = walletIdHexProvider

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    var storageKey: String {
        let walletScope = walletIdHexProvider()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let walletSuffix = (walletScope?.isEmpty == false) ? walletScope! : "no-wallet"
        return "dashconnect.connections.v1.\(network.rawValue).\(walletSuffix)"
    }

    func load() -> [DAppConnection] {
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
                    updatedAt: row.updatedAt
                )
            )
        }

        return restored
    }

    func save(_ connections: [DAppConnection]) {
        guard !connections.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }

        let rows = connections.map {
            StoredConnection(
                contractId: $0.id,
                label: $0.name,
                url: $0.url,
                status: $0.status,
                updatedAt: $0.updatedAt
            )
        }

        do {
            defaults.set(try encoder.encode(rows), forKey: storageKey)
        } catch {
            NSLog("DashConnectStore: failed to encode connections for %@: %@", storageKey, error.localizedDescription)
        }
    }

    private func logDrop(_ reason: String) {
        NSLog("DashConnectStore: dropping stored row for %@: %@", storageKey, reason)
    }

    private struct StoredConnection: Codable {
        let contractId: String
        let label: String
        let url: String
        let status: ConnectionStatus
        let updatedAt: Date
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
