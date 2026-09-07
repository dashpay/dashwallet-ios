//
//  EvonodeStatusViewModel.swift
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
import SwiftDashSDK

// MARK: - Display model

/// One label/value line of the status report.
struct EvonodeStatusRow: Identifiable, Equatable {
    enum Style: Equatable {
        /// Short value, trailing-aligned.
        case value
        /// Long hex / URI — monospaced block, tap to copy.
        case copyable
    }

    let id: String
    let label: String
    let value: String
    let style: Style
}

/// One titled group of rows, in the node's own grouping (version, node,
/// chain, network, state sync, time).
struct EvonodeStatusSection: Identifiable, Equatable {
    let id: String
    let title: String
    let footer: String?
    let rows: [EvonodeStatusRow]
}

// MARK: - EvonodeStatusViewModel

/// Asks ONE evonode for its DAPI `getStatus` self-report and lays out every
/// field it returned for `EvonodeStatusScreen`.
///
/// Nothing is requested until `request()` runs — the screen is reached only
/// through an explicit "Request status" tap, and the request goes to that
/// node alone (`PlatformMasternode.platformDAPIAddress`), not through the
/// SDK's address list. The report is unproved by nature: it is the node
/// describing itself, so it is shown as diagnostics, never folded into
/// wallet state.
@MainActor
final class EvonodeStatusViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        /// `detail` is the underlying SDK / transport message, shown small
        /// under the headline — this is a diagnostics screen.
        case failed(title: String, detail: String?)
    }

    let masternode: PlatformMasternode
    /// `https://<host>:<platform HTTP port>` the request is sent to, or `nil`
    /// when the aggregation doesn't know the node's service address or
    /// platform port (then `request()` fails without touching the network).
    let address: String?

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var sections: [EvonodeStatusSection] = []
    @Published private(set) var receivedAt: Date?

    init(masternode: PlatformMasternode) {
        self.masternode = masternode
        address = masternode.platformDAPIAddress
    }

    var isLoading: Bool { phase == .loading }

    /// Send the request (or send it again). The FFI call is blocking — it
    /// runs off the main actor.
    func request() async {
        guard phase != .loading else { return }
        guard let address else {
            phase = .failed(
                title: NSLocalizedString("This evonode's DAPI address isn't known, so it can't be asked for its status.", comment: "Evonode status"),
                detail: nil)
            return
        }
        guard let sdk = SwiftDashSDKHost.shared.sdk else {
            phase = .failed(title: NSLocalizedString("Platform SDK not ready", comment: "Masternodes"), detail: nil)
            return
        }

        phase = .loading
        do {
            let status = try await Task.detached(priority: .userInitiated) {
                try sdk.getEvonodeStatus(address: address)
            }.value
            let now = Date()
            receivedAt = now
            sections = Self.sections(for: status, masternode: masternode, address: address, receivedAt: now)
            phase = .loaded
        } catch {
            phase = Self.failure(for: error)
        }
    }

    // MARK: Failure copy

    private static func failure(for error: Error) -> Phase {
        guard let sdkError = error as? SDKError else {
            return .failed(
                title: NSLocalizedString("Couldn't get the evonode's status.", comment: "Evonode status"),
                detail: error.localizedDescription)
        }
        switch sdkError {
        case .timeout(let detail):
            return .failed(
                title: NSLocalizedString("The evonode didn't answer in time.", comment: "Evonode status"),
                detail: detail)
        case .networkError(let detail):
            return .failed(
                title: NSLocalizedString("Couldn't reach the evonode.", comment: "Evonode status"),
                detail: detail)
        case .serializationError(let detail):
            return .failed(
                title: NSLocalizedString("The evonode's answer couldn't be read.", comment: "Evonode status"),
                detail: detail)
        case .invalidParameter(let detail), .invalidState(let detail), .protocolError(let detail),
             .cryptoError(let detail), .notFound(let detail), .notImplemented(let detail),
             .internalError(let detail), .unknown(let detail):
            return .failed(
                title: NSLocalizedString("Couldn't get the evonode's status.", comment: "Evonode status"),
                detail: detail)
        }
    }

    // MARK: Layout

    /// Every field of the report, grouped as the node groups them. Optional
    /// fields the node omitted read "Not reported" — never a zero that looks
    /// like data.
    static func sections(
        for status: EvonodeStatus,
        masternode: PlatformMasternode,
        address: String,
        receivedAt: Date
    ) -> [EvonodeStatusSection] {
        var sections: [EvonodeStatusSection] = []

        sections.append(EvonodeStatusSection(
            id: "request",
            title: NSLocalizedString("Request", comment: "Evonode status"),
            footer: NSLocalizedString("The node's own report, unverified — what it says about itself, not what the network has agreed on.", comment: "Evonode status"),
            rows: [
                EvonodeStatusRow(id: "address", label: NSLocalizedString("Asked", comment: "Evonode status: the DAPI address the request went to"), value: address, style: .copyable),
                EvonodeStatusRow(id: "received", label: NSLocalizedString("Received", comment: "Evonode status"), value: dateTime(receivedAt), style: .value),
            ]))

        // Software versions
        let software = status.version.software
        sections.append(EvonodeStatusSection(
            id: "software",
            title: NSLocalizedString("Software", comment: "Evonode status"),
            footer: nil,
            rows: [
                valueRow("dapi", NSLocalizedString("DAPI", comment: "Evonode status"), software?.dapi),
                valueRow("drive", NSLocalizedString("Drive", comment: "Evonode status"), software?.drive),
                valueRow("tenderdash", NSLocalizedString("Tenderdash", comment: "Evonode status"), software?.tenderdash),
            ]))

        // Protocol versions
        let protocolVersions = status.version.protocol
        sections.append(EvonodeStatusSection(
            id: "protocol",
            title: NSLocalizedString("Protocol versions", comment: "Evonode status"),
            footer: nil,
            rows: [
                valueRow("td-p2p", NSLocalizedString("Tenderdash P2P", comment: "Evonode status"), protocolVersions?.tenderdash.map { number($0.p2p) }),
                valueRow("td-block", NSLocalizedString("Tenderdash block", comment: "Evonode status"), protocolVersions?.tenderdash.map { number($0.block) }),
                valueRow("drive-current", NSLocalizedString("Drive current", comment: "Evonode status"), protocolVersions?.drive.map { number($0.current) }),
                valueRow("drive-latest", NSLocalizedString("Drive latest", comment: "Evonode status"), protocolVersions?.drive.map { number($0.latest) }),
                valueRow("drive-next", NSLocalizedString("Drive next epoch", comment: "Evonode status"), protocolVersions?.drive.map { number($0.nextEpoch) }),
            ]))

        // Node
        sections.append(EvonodeStatusSection(
            id: "node",
            title: NSLocalizedString("Node", comment: "Evonode status"),
            footer: nil,
            rows: [
                hexRow("node-id", NSLocalizedString("Node ID", comment: "Evonode status"), status.node.id),
                hexRow("protx", "proTxHash", status.node.proTxHash),
                EvonodeStatusRow(
                    id: "identity",
                    label: NSLocalizedString("Identity check", comment: "Evonode status"),
                    value: identityCheck(reported: status.node.proTxHash, masternode: masternode),
                    style: .value),
            ]))

        // Chain
        let chain = status.chain
        sections.append(EvonodeStatusSection(
            id: "chain",
            title: NSLocalizedString("Chain", comment: "Evonode status"),
            footer: nil,
            rows: [
                EvonodeStatusRow(id: "catching-up", label: NSLocalizedString("Catching up", comment: "Evonode status"), value: yesNo(chain.catchingUp), style: .value),
                EvonodeStatusRow(id: "latest-height", label: NSLocalizedString("Latest block height", comment: "Evonode status"), value: number(chain.latestBlockHeight), style: .value),
                EvonodeStatusRow(id: "earliest-height", label: NSLocalizedString("Earliest block height", comment: "Evonode status"), value: number(chain.earliestBlockHeight), style: .value),
                EvonodeStatusRow(id: "max-peer-height", label: NSLocalizedString("Max peer block height", comment: "Evonode status"), value: number(chain.maxPeerBlockHeight), style: .value),
                valueRow("core-locked", NSLocalizedString("Core chain-locked height", comment: "Evonode status"), chain.coreChainLockedHeight.map { number($0) }),
                hexRow("latest-block-hash", NSLocalizedString("Latest block hash", comment: "Evonode status"), chain.latestBlockHash),
                hexRow("latest-app-hash", NSLocalizedString("Latest app hash", comment: "Evonode status"), chain.latestAppHash),
                hexRow("earliest-block-hash", NSLocalizedString("Earliest block hash", comment: "Evonode status"), chain.earliestBlockHash),
                hexRow("earliest-app-hash", NSLocalizedString("Earliest app hash", comment: "Evonode status"), chain.earliestAppHash),
            ]))

        // Network
        let network = status.network
        sections.append(EvonodeStatusSection(
            id: "network",
            title: NSLocalizedString("Network", comment: "Evonode status"),
            footer: nil,
            rows: [
                valueRow("chain-id", NSLocalizedString("Chain ID", comment: "Evonode status"), network.chainId.isEmpty ? nil : network.chainId),
                EvonodeStatusRow(id: "peers", label: NSLocalizedString("Peers", comment: "Evonode status"), value: number(network.peersCount), style: .value),
                EvonodeStatusRow(id: "listening", label: NSLocalizedString("Listening", comment: "Evonode status"), value: yesNo(network.listening), style: .value),
            ]))

        // State sync
        let sync = status.stateSync
        sections.append(EvonodeStatusSection(
            id: "state-sync",
            title: NSLocalizedString("State sync", comment: "Evonode status"),
            footer: nil,
            rows: [
                EvonodeStatusRow(id: "synced-time", label: NSLocalizedString("Total synced time", comment: "Evonode status"), value: nanoseconds(sync.totalSyncedTime), style: .value),
                EvonodeStatusRow(id: "remaining-time", label: NSLocalizedString("Remaining time", comment: "Evonode status"), value: nanoseconds(sync.remainingTime), style: .value),
                EvonodeStatusRow(id: "snapshots", label: NSLocalizedString("Total snapshots", comment: "Evonode status"), value: number(sync.totalSnapshots), style: .value),
                EvonodeStatusRow(id: "chunk-avg", label: NSLocalizedString("Chunk process avg time", comment: "Evonode status"), value: nanoseconds(sync.chunkProcessAvgTime), style: .value),
                EvonodeStatusRow(id: "snapshot-height", label: NSLocalizedString("Snapshot height", comment: "Evonode status"), value: number(sync.snapshotHeight), style: .value),
                EvonodeStatusRow(id: "snapshot-chunks", label: NSLocalizedString("Snapshot chunks", comment: "Evonode status"), value: number(sync.snapshotChunksCount), style: .value),
                EvonodeStatusRow(id: "backfilled", label: NSLocalizedString("Backfilled blocks", comment: "Evonode status"), value: number(sync.backfilledBlocks), style: .value),
                EvonodeStatusRow(id: "backfill-total", label: NSLocalizedString("Backfill blocks total", comment: "Evonode status"), value: number(sync.backfillBlocksTotal), style: .value),
            ]))

        // Time — the SDK's `*Date` accessors resolve the per-field units
        // (and Drive's `0` = unknown) so these never show 1970.
        let time = status.time
        sections.append(EvonodeStatusSection(
            id: "time",
            title: NSLocalizedString("Time", comment: "Evonode status"),
            footer: nil,
            rows: [
                valueRow("local", NSLocalizedString("Node clock", comment: "Evonode status"), time.localDate.map(dateTime)),
                valueRow("block-time", NSLocalizedString("Latest block", comment: "Evonode status"), time.blockDate.map(dateTime)),
                valueRow("genesis", NSLocalizedString("Genesis", comment: "Evonode status"), time.genesisDate.map(dateTime)),
                valueRow("epoch", NSLocalizedString("Epoch", comment: "Evonode status"), time.epoch.map { number($0) }),
            ]))

        return sections
    }

    /// "Matches this evonode" when the node reports the proTxHash of the
    /// masternode being viewed — in either byte order, since the app stores
    /// wire order and explorers show it reversed — "differs" when it names
    /// another masternode (the IP now serves a different node), and "Not
    /// reported" for a full node / missing field.
    private static func identityCheck(reported: String?, masternode: PlatformMasternode) -> String {
        guard let reported, !reported.isEmpty else { return notReported }
        let lowered = reported.lowercased()
        let wireHex = masternode.proTxHash.map { String(format: "%02x", $0) }.joined()
        if lowered == masternode.proTxHashHex || lowered == wireHex {
            return NSLocalizedString("Matches this evonode", comment: "Evonode status")
        }
        return NSLocalizedString("Differs from this evonode", comment: "Evonode status")
    }

    // MARK: Formatting

    static let notReported = NSLocalizedString("Not reported", comment: "Evonode status: the node omitted this field")

    private static func valueRow(_ id: String, _ label: String, _ value: String?) -> EvonodeStatusRow {
        EvonodeStatusRow(id: id, label: label, value: value ?? notReported, style: .value)
    }

    /// Hex hashes/ids are copyable blocks; an empty / absent one is a plain
    /// "Not reported" line.
    private static func hexRow(_ id: String, _ label: String, _ hex: String?) -> EvonodeStatusRow {
        guard let hex, !hex.isEmpty else {
            return EvonodeStatusRow(id: id, label: label, value: notReported, style: .value)
        }
        return EvonodeStatusRow(id: id, label: label, value: hex, style: .copyable)
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static func number<N: BinaryInteger>(_ value: N) -> String {
        numberFormatter.string(from: NSNumber(value: Int64(clamping: value))) ?? "\(value)"
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? NSLocalizedString("Yes", comment: "") : NSLocalizedString("No", comment: "")
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 3
        return formatter
    }()

    /// Tenderdash state-sync timings are Go `time.Duration`s — integer
    /// nanoseconds on the wire.
    private static func nanoseconds(_ value: UInt64) -> String {
        guard value > 0 else { return number(0) }
        let seconds = TimeInterval(value) / 1_000_000_000
        if seconds < 1 {
            return String(format: NSLocalizedString("%.3f s", comment: "Evonode status: sub-second duration"), seconds)
        }
        return durationFormatter.string(from: seconds) ?? String(format: "%.0f s", seconds)
    }
}
