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

        var title: String {
            switch self {
            case .milliDash: return "0.001 DASH"
            case .centiDash: return "0.01 DASH"
            case .deciDash: return "0.1 DASH"
            case .oneDash: return "1 DASH"
            }
        }
    }

    @Published private(set) var phase: Phase = .configuring
    @Published var lifetime: Lifetime = .oneDay
    @Published var budget: Budget = .centiDash

    let peripheral: BrowserLoginPeripheral

    private let dataSource: any DashConnectDataSource
    private let supportedNetwork: DashConnectNetwork
    private var request: DashKeyRequest?

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

    func startAdvertising() {
        request = nil
        phase = .advertising
        peripheral.start()
    }

    /// Tear the radio down. Called when the screen goes away, and after a
    /// decline so the next browser starts from a clean service.
    func stop() {
        peripheral.stop()
    }

    func decline() {
        peripheral.setStatus(.rejected)
        request = nil
        phase = .configuring
        peripheral.stop()
    }

    func reset() {
        request = nil
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
            request = parsed
            phase = .awaitingConfirmation(PendingRequest(
                appLabel: branding.name,
                contractId: DashConnectIdentifierFormatting.truncateMiddle(parsed.contractId.toBase58String()),
                pairingCode: try BrowserLoginBleProtocol.pairingCode(for: parsed.appEphemeralPubKey)
            ))
            peripheral.setStatus(.awaitingConfirmation)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        peripheral.setStatus(.failed)
        request = nil
        phase = .failed(message)
    }

    private static func displayName(for network: DashConnectNetwork) -> String {
        switch network {
        case .mainnet: return NSLocalizedString("Mainnet", comment: "Network name")
        case .testnet: return NSLocalizedString("Testnet", comment: "Network name")
        case .devnet: return NSLocalizedString("Devnet", comment: "Network name")
        }
    }
}
