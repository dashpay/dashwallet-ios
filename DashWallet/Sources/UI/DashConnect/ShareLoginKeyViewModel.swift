//
//  ShareLoginKeyViewModel.swift
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

import Combine
import Foundation
import OSLog

/// Drives the "Share Login Key with Browser" screen: owns the Bluetooth
/// peripheral, turns the browser's request into something the user can
/// confirm, and hands the confirmed request to the data source, which
/// registers the bounded key and builds the encrypted response.
@MainActor
final class ShareLoginKeyViewModel: ObservableObject {
    enum Phase: Equatable {
        case configuring
        case advertising
        case awaitingConfirmation(PendingRequest)
        case registering
        case delivered(keyId: UInt32)
        case failed(String)
    }

    /// What the confirmation step shows. `appLabel` comes from the request
    /// and is unauthenticated; the pairing code is what the user verifies.
    struct PendingRequest: Equatable {
        let appLabel: String
        let contractId: String
        let pairingCode: String
    }

    /// How long the browser's key stays valid.
    enum Lifetime: CaseIterable, Identifiable {
        case oneHour
        case oneDay
        case oneWeek
        case oneMonth

        var id: Self { self }

        var seconds: TimeInterval {
            switch self {
            case .oneHour: return 3_600
            case .oneDay: return 86_400
            case .oneWeek: return 7 * 86_400
            case .oneMonth: return 30 * 86_400
            }
        }

        var title: String {
            switch self {
            case .oneHour: return NSLocalizedString("1 hour", comment: "DashConnect: login key lifetime")
            case .oneDay: return NSLocalizedString("24 hours", comment: "DashConnect: login key lifetime")
            case .oneWeek: return NSLocalizedString("7 days", comment: "DashConnect: login key lifetime")
            case .oneMonth: return NSLocalizedString("30 days", comment: "DashConnect: login key lifetime")
            }
        }
    }

    /// How many credits the browser's key may spend in total.
    enum Budget: CaseIterable, Identifiable {
        case milliDash
        case centiDash
        case deciDash
        case oneDash

        var id: Self { self }

        var credits: UInt64 {
            switch self {
            case .milliDash: return PlatformCreditsFormatter.creditsPerDash / 1_000
            case .centiDash: return PlatformCreditsFormatter.creditsPerDash / 100
            case .deciDash: return PlatformCreditsFormatter.creditsPerDash / 10
            case .oneDash: return PlatformCreditsFormatter.creditsPerDash
            }
        }

        /// `dashString` renders the same values, but with the decimal
        /// separator of the current locale — the literals above were always
        /// `.`, which is wrong wherever the separator is `,`.
        var title: String {
            PlatformCreditsFormatter.dashString(credits)
        }
    }

    @Published private(set) var phase: Phase = .configuring
    @Published var lifetime: Lifetime = .oneDay
    @Published var budget: Budget = .centiDash
    /// Set once the browser has had `deliveryAcknowledgementTimeout` to pick
    /// the response up. It unblocks the screen for a browser that never
    /// acknowledges, so the user is never stuck on a screen it cannot leave.
    @Published private(set) var deliveryWaitTimedOut = false

    let peripheral: BrowserLoginPeripheral

    /// How long the screen waits for the browser to say it has the response
    /// before it lets the user leave anyway.
    static let deliveryAcknowledgementTimeout: TimeInterval = 30

    private let dataSource: any DashConnectDataSource
    private let supportedNetwork: DashConnectNetwork
    private var request: DashKeyRequest?
    private var deliveryWaitTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "dashconnect.share-login-key")

    init(
        dataSource: any DashConnectDataSource,
        supportedNetwork: DashConnectNetwork = PlatformDashConnectDataSource.currentEnvironmentNetwork(),
        peripheral: BrowserLoginPeripheral? = nil
    ) {
        self.dataSource = dataSource
        self.supportedNetwork = supportedNetwork
        self.peripheral = peripheral ?? BrowserLoginPeripheral(
            localName: NSLocalizedString("Dash Wallet", comment: "DashConnect: Bluetooth device name")
        )
        self.peripheral.onRequest = { [weak self] bytes in
            self?.handle(requestBytes: bytes)
        }
    }

    var limits: BrowserLoginKeyLimits {
        BrowserLoginKeyLimits(totalBudget: budget.credits, lifetime: lifetime.seconds)
    }

    var isConfiguring: Bool {
        if case .configuring = phase { return true }
        return false
    }

    /// Whether the browser still has to read the response the peripheral is
    /// serving.
    var isAwaitingDeliveryAcknowledgement: Bool {
        if case .delivered = phase { return !peripheral.responseWasAcknowledged }
        return false
    }

    /// Leaving the screen calls `stop()`, which wipes the response and takes
    /// the service down. Between the confirmation and the browser's
    /// acknowledgement that would strand a key that is already registered on
    /// the identity, with nothing on the wallet side able to use or revoke
    /// it — so those two phases hold the screen.
    var blocksDismissal: Bool {
        switch phase {
        case .registering:
            return true
        case .delivered:
            return isAwaitingDeliveryAcknowledgement && !deliveryWaitTimedOut
        case .configuring, .advertising, .awaitingConfirmation, .failed:
            return false
        }
    }

    func startAdvertising() {
        request = nil
        cancelDeliveryWait()
        phase = .advertising
        peripheral.start()
    }

    /// Tear the radio down. Called when the screen goes away, and after a
    /// decline so the next browser starts from a clean service.
    func stop() {
        cancelDeliveryWait()
        peripheral.stop()
    }

    func decline() {
        peripheral.setStatus(.rejected)
        request = nil
        cancelDeliveryWait()
        phase = .configuring
        peripheral.stop()
    }

    func reset() {
        request = nil
        cancelDeliveryWait()
        phase = .configuring
        peripheral.stop()
    }

    func confirm() {
        guard case .awaitingConfirmation = phase, let request else { return }
        phase = .registering
        peripheral.setStatus(.registering)

        Task {
            do {
                let response = try await dataSource.shareLoginKey(request, limits: limits)
                let bytes = try response.serialized()
                peripheral.deliver(response: bytes)
                phase = .delivered(keyId: response.keyId)
                startDeliveryWait()
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func handle(requestBytes: Data) {
        guard case .advertising = phase else { return }
        do {
            let parsed = try BrowserLoginBleProtocol.parseRequest(requestBytes)
            guard parsed.network == supportedNetwork else {
                fail(String(
                    format: NSLocalizedString("The browser asked for %@, but this wallet is on %@.", comment: "DashConnect: Bluetooth request for another network"),
                    Self.displayName(for: parsed.network),
                    Self.displayName(for: supportedNetwork)
                ))
                return
            }
            let branding = DashConnectFallbackAppMetadata.resolve(
                contractId: parsed.contractId.toBase58String(),
                unauthenticatedLabel: parsed.label
            )
            // Over the bytes as written, not over the parsed request: the
            // browser derives the same digits from what it sent, so anything
            // a relay rewrites on the way — the contract id and the label
            // this screen is about to show included — changes the code here.
            let pairingCode = try BrowserLoginBleProtocol.pairingCode(
                nonce: peripheral.pairingNonce,
                requestBytes: requestBytes
            )
            request = parsed
            phase = .awaitingConfirmation(PendingRequest(
                appLabel: branding.name,
                contractId: DashConnectIdentifierFormatting.truncateMiddle(parsed.contractId.toBase58String()),
                pairingCode: pairingCode
            ))
            // Only now, with the request accepted and the code on screen, may
            // the nonce go out.
            peripheral.revealPairingNonce()
            peripheral.setStatus(.awaitingConfirmation)
        } catch {
            // The request characteristic is unauthenticated and writable, so
            // these bytes may not be from the browser at all. Reject the write
            // and keep advertising: routing it into `fail()` would let any
            // central in range end the legitimate session with one malformed
            // byte and force a manual reset.
            Self.logger.warning(
                "🔗 DASHCONNECT :: discarding an unparseable BLE request — \(error.localizedDescription, privacy: .public)")
            peripheral.setStatus(.idle)
        }
    }

    private func fail(_ message: String) {
        peripheral.setStatus(.failed)
        request = nil
        cancelDeliveryWait()
        phase = .failed(message)
    }

    private func startDeliveryWait() {
        deliveryWaitTask?.cancel()
        deliveryWaitTimedOut = false
        deliveryWaitTask = Task { [timeout = Self.deliveryAcknowledgementTimeout] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            deliveryWaitTimedOut = true
        }
    }

    private func cancelDeliveryWait() {
        deliveryWaitTask?.cancel()
        deliveryWaitTask = nil
        deliveryWaitTimedOut = false
    }

    private static func displayName(for network: DashConnectNetwork) -> String {
        switch network {
        case .mainnet: return NSLocalizedString("Mainnet", comment: "Network name")
        case .testnet: return NSLocalizedString("Testnet", comment: "Network name")
        case .devnet: return NSLocalizedString("Devnet", comment: "Network name")
        }
    }
}
