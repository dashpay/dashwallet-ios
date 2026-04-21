//
//  ReceiveViewModel.swift
//  DashWallet
//

import Combine
import Foundation
import UIKit

@MainActor
final class ReceiveViewModel: ObservableObject {

    @Published var network: ChainNetwork = .core
    @Published private(set) var coreAddress: String? = nil
    @Published private(set) var platformAddress: String? = nil

    private var cancellables = Set<AnyCancellable>()

    init() {
        reloadCoreAddress()

        PlatformAddressSyncCoordinator.shared.$derivedAddresses
            .receive(on: RunLoop.main)
            .sink { [weak self] addresses in
                self?.platformAddress = Self.pickNextPlatformAddress(from: addresses)
            }
            .store(in: &cancellables)

        platformAddress = Self.pickNextPlatformAddress(
            from: PlatformAddressSyncCoordinator.shared.derivedAddresses)

        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadCoreAddress() }
            .store(in: &cancellables)
    }

    var currentAddress: String? {
        switch network {
        case .core: return coreAddress
        case .platform: return platformAddress
        }
    }

    var platformIsReady: Bool {
        PlatformAddressSyncCoordinator.shared.isRunning
    }

    func reload() {
        reloadCoreAddress()
        platformAddress = Self.pickNextPlatformAddress(
            from: PlatformAddressSyncCoordinator.shared.derivedAddresses)
    }

    func copyCurrentAddressToPasteboard() {
        guard let address = currentAddress else { return }
        UIPasteboard.general.string = address
    }

    private func reloadCoreAddress() {
        let chain = DWEnvironment.sharedInstance().currentChain
        coreAddress = SwiftDashSDKReceiveAddressReader.receiveAddress(on: chain)
    }

    private static func pickNextPlatformAddress(
        from addresses: [DerivedPlatformAddress]
    ) -> String? {
        if let unused = addresses
            .filter({ !$0.isUsed })
            .min(by: { ($0.accountIndex, $0.addressIndex) < ($1.accountIndex, $1.addressIndex) }) {
            return unused.address
        }
        return addresses
            .min(by: { ($0.accountIndex, $0.addressIndex) < ($1.accountIndex, $1.addressIndex) })?
            .address
    }
}
