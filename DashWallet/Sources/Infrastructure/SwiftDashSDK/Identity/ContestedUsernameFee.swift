//
//  Created for the SwiftDashSDK migration.
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
import OSLog
import SwiftDashSDK

/// What a contested username costs on the network the app is connected to.
///
/// Platform protocol version 14 (4.2) halves the contest fund a contested
/// DPNS name prefunds, 0.2 → 0.1 DASH, so funding a new identity for one
/// drops from 0.25 to 0.15 DASH. Which pair applies depends on the protocol
/// version the network has activated, not on the build: a build ships before
/// or after a network upgrades, and stating 0.15 to a network that still
/// wants 0.25 gets the registration refused for insufficient balance.
///
/// The version comes from the SDK, which reports the highest one it holds
/// a proof for and, before any proof, its own floor for the network. A read
/// that could not reach the network is not an error there: it returns that
/// same number, and an SDK pinned to a version
/// (`SwiftDashSDKHost.platformVersion(for:)`) returns its pin. Below 14, or
/// before any runtime has started, the older, higher pair applies:
/// over-funding leaves the surplus as identity credits, under-funding fails
/// the registration.
///
/// The highest version seen is kept per network and only ever rises, so a
/// figure the user confirmed cannot grow by the time it is paid — not when
/// the next read falls back to the floor, and not after a relaunch.
///
/// One shared instance because there is one running network and every
/// consumer must state the same figure; the defaults store and the version
/// read are injected so tests run without an SDK.
@MainActor
final class ContestedUsernameFee: ObservableObject {

    struct Amounts: Equatable {
        /// The contest fund the contested domain document locks from the
        /// identity balance. Mirrors
        /// `contested_document_vote_resolution_fund_required_amount` in
        /// rs-platform-version (`vote_resolution_fund_fees`).
        let fundCredits: UInt64

        /// The fund in duffs.
        var fundDuffs: UInt64 { fundCredits / PlatformPaymentIdentityFundingPolicy.creditsPerDuff }
        /// What a new identity is funded with for a contested name from the
        /// Dash Wallet or Platform balance: the fund plus 0.05 DASH for the
        /// identity-create and document fees.
        var fundingDuffs: UInt64 { fundDuffs + 5_000_000 }

        /// Protocol versions 1–13: 0.2 DASH fund, 0.25 DASH to fund.
        static let legacy = Amounts(fundCredits: 20_000_000_000)
        /// Protocol version 14 and later: 0.1 DASH fund, 0.15 DASH to fund.
        static let reduced = Amounts(fundCredits: 10_000_000_000)

        /// First protocol version charging the reduced fund.
        static let reducedFromProtocolVersion: UInt32 = 14

        /// What a new identity is funded with for one name. The Dash Wallet
        /// and Platform balances pay 0.03 DASH for a standard name and
        /// `fundingDuffs` for a contested one. Shielded leaves the pool as a
        /// fixed exit denomination that does not follow the protocol version.
        @MainActor
        func newIdentityFundingDuffs(isContested: Bool, fromShielded: Bool) -> UInt64 {
            if fromShielded {
                return ShieldedIdentityFundingReadiness.requiredCredits(forContestedName: isContested)
                    / PlatformPaymentIdentityFundingPolicy.creditsPerDuff
            }
            return isContested ? fundingDuffs : UInt64(DWDP_MIN_BALANCE_TO_CREATE_USERNAME)
        }

        /// The most a username can cost, whichever source pays.
        @MainActor
        var maximumUsernameCostDuffs: UInt64 {
            max(newIdentityFundingDuffs(isContested: true, fromShielded: false),
                newIdentityFundingDuffs(isContested: true, fromShielded: true))
        }

        /// `nil` — version not known — resolves to the legacy pair.
        static func forProtocolVersion(_ version: UInt32?) -> Amounts {
            guard let version, version >= reducedFromProtocolVersion else { return .legacy }
            return .reduced
        }
    }

    static let shared = ContestedUsernameFee()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.contested-username-fee")

    /// The pair for the running network. Observed by every screen that
    /// states or checks the cost, so a version that arrives after a screen
    /// opened is not left stale.
    @Published private(set) var amounts: Amounts = .legacy

    private let defaults: UserDefaults
    /// The running network's scope and a blocking read of its protocol
    /// version; nil while no SDK runtime is up.
    private let source: @MainActor () -> (scope: String, read: @Sendable () throws -> UInt32)?
    private var inFlight: (id: Int, scope: String, task: Task<Void, Never>)?
    private var readCount = 0

    /// The SDK read blocks its thread on a proven network query with
    /// retries, so it stays off the cooperative pool.
    private nonisolated static let readQueue = DispatchQueue(
        label: "org.dashfoundation.dash.contested-username-fee",
        qos: .userInitiated)

    init(
        defaults: UserDefaults = .standard,
        source: @escaping @MainActor () -> (scope: String, read: @Sendable () throws -> UInt32)? = {
            guard let sdk = SwiftDashSDKHost.shared.sdk,
                  let network = SwiftDashSDKHost.shared.runningNetwork else { return nil }
            // Weak: a read must not keep a stopped runtime's SDK alive.
            return (network.persistenceScope, { [weak sdk] in
                guard let sdk else { throw CancellationError() }
                return try sdk.refreshProtocolVersion()
            })
        }
    ) {
        self.defaults = defaults
        self.source = source
        if let scope = source()?.scope {
            amounts = .forProtocolVersion(knownProtocolVersion(scope: scope))
        }
    }

    /// Reads the running network's protocol version and applies it. Joins a
    /// read already in flight for the same runtime. A read that throws, or
    /// returns less than what is known, keeps what is known. Does nothing
    /// while no runtime is up.
    func refresh() async {
        guard let (scope, read) = source() else { return }
        apply(scope: scope)
        // The reduced pair is the lowest there is and a version never goes
        // down: nothing a read could return would change the figure.
        guard amounts != .reduced else { return }
        if let inFlight, inFlight.scope == scope {
            await inFlight.task.value
            return
        }
        readCount += 1
        let id = readCount
        let task = Task { [weak self] in
            let version: UInt32? = await withCheckedContinuation { continuation in
                Self.readQueue.async { continuation.resume(returning: try? read()) }
            }
            guard let self else { return }
            if let version {
                self.record(version, scope: scope)
            } else {
                Self.logger.error("protocol version read failed for \(scope, privacy: .public)")
            }
            // A runtime restarted meanwhile owns its own read; leave it be.
            if self.inFlight?.id == id { self.inFlight = nil }
            // Another network may be running by now; publish only its figure.
            if let current = self.source()?.scope { self.apply(scope: current) }
        }
        inFlight = (id, scope, task)
        await task.value
    }

    /// The SDK runtime came up, possibly on another network: publish what is
    /// known for it at once and read its version.
    func runtimeDidStart() {
        if let scope = source()?.scope { apply(scope: scope) }
        Task { await refresh() }
    }

    /// The runtime is gone. A read still in flight belongs to its SDK, so the
    /// next runtime starts its own instead of joining it. The published
    /// figure stays until that runtime publishes: a restart on the same
    /// network must not make an open form's cost jump up and back.
    func runtimeDidStop() {
        inFlight = nil
    }

    // MARK: - Known version, per network

    private func key(scope: String) -> String {
        "ContestedUsernameFee.protocolVersion.\(scope)"
    }

    private func knownProtocolVersion(scope: String) -> UInt32? {
        let stored = defaults.integer(forKey: key(scope: scope))
        return stored > 0 ? UInt32(stored) : nil
    }

    /// A network's protocol version never goes down, so a lower read (the
    /// SDK's floor, before it has a proof) does not replace a higher known one.
    private func record(_ version: UInt32, scope: String) {
        guard version > (knownProtocolVersion(scope: scope) ?? 0) else { return }
        defaults.set(Int(version), forKey: key(scope: scope))
        Self.logger.info("SDK reports protocol \(version, privacy: .public) for \(scope, privacy: .public)")
        // DWLogger as well: os_log does not reach the exported diagnostics.
        DWLogger.log("CONTESTED-FEE protocol \(version) recorded for \(scope)")
    }

    private func apply(scope: String) {
        publish(.forProtocolVersion(knownProtocolVersion(scope: scope)))
    }

    private func publish(_ resolved: Amounts) {
        guard amounts != resolved else { return }
        amounts = resolved
        DWLogger.log("CONTESTED-FEE fund \(resolved.fundDuffs) duffs, funding \(resolved.fundingDuffs) duffs")
    }
}
