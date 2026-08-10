//
//  PaymentsLandingViewModel.swift
//  DashWallet
//

import Combine
import Foundation
import SwiftDashSDK
import SwiftUI
import DashUIKit
import UIKit

enum PaymentsLandingTab: String, CaseIterable, Identifiable {
    case receive
    case internalTransfer
    case send

    var id: String { rawValue }

    var title: String {
        switch self {
        case .receive: return NSLocalizedString("Receive", comment: "")
        case .internalTransfer: return NSLocalizedString("Internal transfer", comment: "")
        case .send: return NSLocalizedString("Send", comment: "")
        }
    }

    /// Asset name and the size the glyph is drawn at — the three differ, and
    /// one shared size would distort them.
    var icon: (name: String, width: CGFloat, height: CGFloat) {
        switch self {
        case .receive: return ("payments-option-arrow-down", 8.881, 14)
        case .internalTransfer: return ("payments-option-transfer", 15.297, 16)
        case .send: return ("payments-option-arrow-up", 7.771, 14)
        }
    }

    /// Fill of the pill while this tab is the active one.
    var accent: Color {
        switch self {
        case .receive: return Color.dash.green
        case .internalTransfer: return Color.dash.lightBlue
        case .send: return Color.dash.blue
        }
    }
}

@MainActor
final class PaymentsLandingViewModel: ObservableObject {

    @Published var activeTab: PaymentsLandingTab
    @Published var network: ChainNetwork = .core
    /// Which hero tabs this presentation offers. The full landing shows all
    /// three; the balance-row receive sheet narrows to Receive + Internal.
    let visibleTabs: [PaymentsLandingTab]
    @Published private(set) var coreAddress: String? = nil
    @Published private(set) var platformAddress: String? = nil
    @Published private(set) var shieldedAddress: String? = nil

    private var cancellables = Set<AnyCancellable>()

    init(activeTab: PaymentsLandingTab,
         network: ChainNetwork = .core,
         visibleTabs: [PaymentsLandingTab] = PaymentsLandingTab.allCases) {
        self.activeTab = activeTab
        self.network = network
        self.visibleTabs = visibleTabs

        reloadCoreAddress()
        reloadShieldedAddress()

        PlatformAddressSyncCoordinator.shared.$derivedAddresses
            .receive(on: RunLoop.main)
            .sink { [weak self] addresses in
                self?.platformAddress = addresses.nextReceiveAddress?.address
                // The shielded sub-wallet is bound by the same coordinator's
                // startup, so a derived-addresses tick is also the retry
                // signal for a shielded address that wasn't ready at init.
                self?.reloadShieldedAddress()
            }
            .store(in: &cancellables)

        platformAddress = PlatformAddressSyncCoordinator.shared
            .derivedAddresses.nextReceiveAddress?.address

        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadCoreAddress() }
            .store(in: &cancellables)
    }

    var currentAddress: String? {
        switch network {
        case .core: return coreAddress
        case .platform: return platformAddress
        case .shielded: return shieldedAddress
        }
    }

    var platformIsReady: Bool {
        PlatformAddressSyncCoordinator.shared.isRunning
    }

    func copyCurrentAddressToPasteboard() {
        guard let address = currentAddress else { return }
        UIPasteboard.general.string = address
    }

    private func reloadCoreAddress() {
        coreAddress = SwiftDashSDKReceiveAddressReader.receiveAddress()
    }

    /// Resolves the wallet's default Orchard payment address and encodes it
    /// for display. `shieldedDefaultAddress` returns nil until the shielded
    /// sub-wallet is bound (PlatformAddressSyncCoordinator does that at
    /// startup), so this is retried from the derived-addresses sink until it
    /// resolves; the address is deterministic, so no reset on later ticks.
    private func reloadShieldedAddress() {
        guard shieldedAddress == nil,
              let manager = SwiftDashSDKHost.shared.manager,
              let wallet = SwiftDashSDKHost.shared.wallet,
              let network = SwiftDashSDKHost.shared.runningNetwork,
              let raw = ((try? manager.shieldedDefaultAddress(walletId: wallet.walletId)) ?? nil)
        else { return }
        // DIP-0018 display form: HRP `dash`/`tdash`, payload = 0x10 type
        // byte + the 43 raw Orchard address bytes (see the SDK doc on
        // `shieldedDefaultAddress`).
        shieldedAddress = Bech32m.encode(
            hrp: Bech32m.platformHrp(mainnet: network == .mainnet),
            data: Data([0x10]) + raw)
    }

}
