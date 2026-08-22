//
//  EvonodeEpochBlocksService.swift
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
import OSLog
import SwiftDashSDK

// MARK: - EvonodeEpochBlocks

/// How many Platform blocks this wallet's evonodes have proposed in the
/// current epoch, per node and in total.
struct EvonodeEpochBlocks: Equatable {
    /// The epoch the tallies are for (the current epoch at fetch time). `nil`
    /// only for the empty "no evonodes" result.
    let epochIndex: UInt32?
    /// When the current epoch started, when known.
    let epochStart: Date?
    /// Blocks proposed this epoch keyed by the evonode's proTxHash (stored
    /// WIRE order, as `PlatformMasternode.proTxHash`). Every owned evonode
    /// is present; nodes that haven't proposed yet are `0`.
    let blocksByProTxHash: [Data: UInt64]
    let fetchedAt: Date

    var totalBlocks: UInt64 {
        blocksByProTxHash.values.reduce(0, +)
    }

    var evonodeCount: Int { blocksByProTxHash.count }
}

// MARK: - EvonodeEpochBlocksProviding

/// Seam for the home screen / masternode list: fetch the current-epoch
/// proposal tallies for a set of owned evonodes.
protocol EvonodeEpochBlocksProviding: AnyObject {
    func fetch(ownedProTxHashes: Set<Data>) async throws -> EvonodeEpochBlocks
}

// MARK: - EvonodeEpochBlocksService

/// Fetches current-epoch block-proposal tallies for the wallet's evonodes
/// WITHOUT revealing which evonodes the wallet owns.
///
/// Privacy rule (owner-mandated): the wallet never sends its own proTxHashes
/// to DAPI for this. Instead of `getEvonodesProposedEpochBlocksByIds` (whose
/// request would list exactly our nodes), this pages through the whole
/// epoch's proposer tallies with `getEvonodesProposedEpochBlocksByRange` —
/// a request that carries no node ids at all, identical for every wallet —
/// and joins the result against the owned set on the device. A DAPI node
/// therefore learns only that some client read the epoch's tallies, which is
/// the same thing a block explorer does.
///
/// Cost: one proved query per page of proposers (Drive serves up to 100
/// entries per page), so a handful of round-trips per refresh; the home
/// screen refreshes at most every few minutes.
final class EvonodeEpochBlocksService: EvonodeEpochBlocksProviding {
    enum ServiceError: LocalizedError {
        case sdkUnavailable
        case malformedEntry
        /// The proposer list was still paging at `maxPages` — the scan is
        /// incomplete, so no tally is returned (callers keep their last value).
        case pageLimitReached
        /// The current epoch could not be resolved, so no tally can be asked
        /// for: the proof verifier requires an explicit epoch index.
        case currentEpochUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .sdkUnavailable: return "Platform SDK not ready"
            case .malformedEntry: return "Unexpected proposer tally format"
            case .pageLimitReached: return "Proposer list too long to scan"
            case let .currentEpochUnavailable(reason): return "Current epoch unavailable: \(reason)"
            }
        }
    }

    /// Drive's page size for the range query (the SDK bridge does not pass a
    /// limit; Platform serves up to 100 proposers per response). A full page
    /// means there may be more — keep paging; a short page ends the scan.
    private static let pageSize = 100
    /// Runaway guard on paging (5000 evonodes ≫ any Dash network).
    private static let maxPages = 50

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.evonode-epoch-blocks")

    init() {}

    func fetch(ownedProTxHashes: Set<Data>) async throws -> EvonodeEpochBlocks {
        // Nothing to tally ⇒ nothing to ask the network: a wallet without
        // evonodes must issue no query at all.
        guard !ownedProTxHashes.isEmpty else {
            return EvonodeEpochBlocks(epochIndex: nil, epochStart: nil, blocksByProTxHash: [:], fetchedAt: Date())
        }
        guard let sdk = await SwiftDashSDKHost.shared.sdk else {
            throw ServiceError.sdkUnavailable
        }
        // Match in either byte order: `PlatformMasternode.proTxHash` is stored
        // wire order and the bridge hex-encodes the proposer hash's raw bytes,
        // which should be the same orientation — but a hash never equals its
        // own reversal, so accepting both can't mis-attribute a tally and
        // guards against an orientation drift in either source.
        var lookup: [Data: Data] = [:]
        for hash in ownedProTxHashes {
            lookup[hash] = hash
            lookup[Data(hash.reversed())] = hash
        }
        let owned = ownedProTxHashes

        // The SDK query bridges block the calling thread (isolated Tokio
        // runtime per call) — keep them off the main actor.
        return try await Task.detached(priority: .utility) { () -> EvonodeEpochBlocks in
            // The current epoch comes first, and is REQUIRED: proved proposer
            // queries must name an explicit epoch (the proof verifier rejects
            // "current"), and the bridge maps epoch 0 to "unspecified".
            let (epochIndex, epochStart) = try await Self.currentEpoch(sdk)
            guard epochIndex > 0 else {
                throw ServiceError.currentEpochUnavailable("epoch 0 cannot be queried through the range bridge")
            }

            var tallies: [Data: UInt64] = Dictionary(uniqueKeysWithValues: owned.map { ($0, 0) })
            var startAfter: String?
            var pages = 0
            var scanned = 0
            while true {
                let page = try await sdk.getEvonodesProposedEpochBlocksByRange(
                    epoch: epochIndex,
                    limit: UInt32(Self.pageSize),
                    startAfter: startAfter,
                    orderAscending: true)
                pages += 1
                scanned += page.count
                for entry in page {
                    let (hash, count) = try Self.parseTally(entry)
                    if let mine = lookup[hash] {
                        tallies[mine] = count
                    }
                }
                // A short page is the end of the list. A full page means there
                // may be more — and a scan that is still paging at the guard
                // is incomplete, so it must not be reported as a tally.
                guard page.count >= Self.pageSize,
                      let last = page.last?["pro_tx_hash"] as? String else {
                    break
                }
                guard pages < Self.maxPages else {
                    throw ServiceError.pageLimitReached
                }
                startAfter = last
            }

            Self.logger.info(
                "🏛️ EVONODE-BLOCKS :: scanned \(scanned) proposers over \(pages) page(s); \(owned.count) owned evonode(s), epoch \(epochIndex, privacy: .public)")
            return EvonodeEpochBlocks(
                epochIndex: epochIndex,
                epochStart: epochStart,
                blocksByProTxHash: tallies,
                fetchedAt: Date())
        }.value
    }

    /// The current (newest started) epoch — `SDK.getCurrentEpoch()` (the
    /// proved two-query probe behind `dash_sdk_system_get_current_epoch`).
    private static func currentEpoch(_ sdk: SDK) async throws -> (index: UInt32, start: Date?) {
        let epoch: [String: Any]
        do {
            epoch = try await sdk.getCurrentEpoch()
        } catch {
            throw ServiceError.currentEpochUnavailable(String(describing: error))
        }
        guard let index = epoch["index"] as? NSNumber else {
            throw ServiceError.currentEpochUnavailable("no index in the epoch record")
        }
        var start: Date?
        if let startMs = epoch["first_block_time"] as? NSNumber, startMs.doubleValue > 0 {
            start = Date(timeIntervalSince1970: startMs.doubleValue / 1000)
        }
        return (index.uint32Value, start)
    }
}

// MARK: - Tally parsing

private extension EvonodeEpochBlocksService {
    /// One `{"pro_tx_hash": hex, "count": n}` bridge entry → (hash, count).
    static func parseTally(_ entry: [String: Any]) throws -> (Data, UInt64) {
        guard let hex = entry["pro_tx_hash"] as? String,
              let hash = Data(hexString: hex) else {
            throw ServiceError.malformedEntry
        }
        if let number = entry["count"] as? NSNumber {
            return (hash, number.uint64Value)
        }
        if let text = entry["count"] as? String, let parsed = UInt64(text) {
            return (hash, parsed)
        }
        throw ServiceError.malformedEntry
    }
}

// MARK: - Data(hexString:)

private extension Data {
    /// Strict hex decoding (even length, hex digits only); `nil` otherwise.
    init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let hi = Self.nibble(chars[index]), let lo = Self.nibble(chars[index + 1]) else {
                return nil
            }
            bytes.append(hi << 4 | lo)
            index += 2
        }
        self.init(bytes)
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}
