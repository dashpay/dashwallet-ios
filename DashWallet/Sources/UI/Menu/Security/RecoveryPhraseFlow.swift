//
//  RecoveryPhraseFlow.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import DashUIKit
import Foundation
import OSLog
import SwiftDashSDK
import SwiftUI
import UIKit

enum RecoveryPhraseWalletNetwork: Int, CaseIterable, Hashable {
    case mainnet
    case testnet
    case devnet

    init?(sdkNetwork: Network) {
        switch sdkNetwork {
        case .mainnet: self = .mainnet
        case .testnet: self = .testnet
        case .devnet: self = .devnet
        case .regtest: return nil
        }
    }

    init?(environmentKind: WalletEnvironment.NetworkKind) {
        switch environmentKind {
        case .mainnet: self = .mainnet
        case .testnet: self = .testnet
        case .devnet: self = .devnet
        }
    }

    var environmentKind: WalletEnvironment.NetworkKind {
        switch self {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .devnet
        }
    }

    var displayName: String {
        switch self {
        case .mainnet: return NSLocalizedString("Mainnet", comment: "Wallet network")
        case .testnet: return NSLocalizedString("Testnet", comment: "Wallet network")
        case .devnet: return NSLocalizedString("Devnet", comment: "Wallet network")
        }
    }
}

struct RecoveryPhraseWalletDescriptor: Identifiable, Equatable {
    /// Mainnet-derived wallet id. It is stable when the same seed later gains
    /// or loses a mirrored testnet Keychain entry.
    let id: Data
    /// Exact Keychain key used for the final read. The reveal path never
    /// substitutes the active, first, or sole wallet id.
    let sourceWalletId: Data
    let displayName: String
    let networks: [RecoveryPhraseWalletNetwork]
    let isActive: Bool

    var shortIdentifier: String {
        id.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    var networkText: String {
        networks.map(\.displayName).joined(separator: ", ")
    }

    var detailsText: String {
        "\(networkText) • \(shortIdentifier)…"
    }

    var contextLabel: String {
        "\(displayName) • \(networkText)"
    }
}

enum RecoveryPhraseRoute: Equatable {
    case direct(RecoveryPhraseWalletDescriptor)
    case choose([RecoveryPhraseWalletDescriptor])
    case unavailable
}

struct RecoveryPhraseInventoryEntry: Equatable {
    let walletId: Data
    let canonicalWalletId: Data
    let normalizedMnemonic: String
    let network: RecoveryPhraseWalletNetwork
}

enum RecoveryPhraseInventoryError: Error {
    case noRecoveryPhrase
    case noReadableRecoveryPhrase
    case invalidMnemonic
    case unsupportedWalletNetwork
    case walletChanged
}

enum RecoveryPhraseInventory {
    struct ReadableEntries {
        let entries: [RecoveryPhraseInventoryEntry]
        let skippedWalletIds: [Data]
    }

    struct MnemonicMaterial {
        let mnemonic: String
        let canonicalWalletId: Data
        let network: RecoveryPhraseWalletNetwork
    }

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "recovery-phrase-inventory")

    @MainActor
    static func load() throws -> [RecoveryPhraseWalletDescriptor] {
        let walletIds = try WalletStorage().listWalletIdsWithMnemonic()
        let result = try collectReadableEntries(walletIds: walletIds) { walletId in
            let mnemonic = try SwiftDashSDKHost.strictlyPersistedMnemonic(for: walletId)
            return try classify((walletId: walletId, mnemonic: mnemonic))
        }
        if !result.skippedWalletIds.isEmpty {
            let labels = result.skippedWalletIds.map {
                $0.prefix(4).map { String(format: "%02x", $0) }.joined()
            }.joined(separator: ",")
            logger.error(
                "Skipping \(result.skippedWalletIds.count, privacy: .public) unreadable recovery-phrase entry/entries ids=\(labels, privacy: .public)")
        }

        let entries = result.entries
        let displayNames = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.walletId, WalletsViewModel.displayName(for: $0.walletId))
        })
        let activeWalletIds: [RecoveryPhraseWalletNetwork: Data] = Dictionary(
            uniqueKeysWithValues: RecoveryPhraseWalletNetwork.allCases.compactMap { network in
                WalletEnvironment.activeWalletId(for: network.environmentKind).map { (network, $0) }
            })

        return try makeDescriptors(
            entries: entries,
            currentNetwork: RecoveryPhraseWalletNetwork(environmentKind: WalletEnvironment.networkKind),
            activeWalletIds: activeWalletIds,
            displayNames: displayNames)
    }

    /// Best-effort collection for the non-destructive recovery-phrase list.
    /// Enumeration itself remains strict, while an unreadable or malformed
    /// neighboring entry cannot hide every otherwise valid recovery phrase.
    static func collectReadableEntries(
        walletIds: [Data],
        loadEntry: (Data) throws -> RecoveryPhraseInventoryEntry
    ) throws -> ReadableEntries {
        var entries: [RecoveryPhraseInventoryEntry] = []
        var skippedWalletIds: [Data] = []
        for walletId in walletIds {
            do {
                entries.append(try loadEntry(walletId))
            } catch {
                skippedWalletIds.append(walletId)
            }
        }

        guard walletIds.isEmpty || !entries.isEmpty else {
            throw RecoveryPhraseInventoryError.noReadableRecoveryPhrase
        }
        return ReadableEntries(
            entries: entries,
            skippedWalletIds: skippedWalletIds)
    }

    static func route(for descriptors: [RecoveryPhraseWalletDescriptor]) -> RecoveryPhraseRoute {
        switch descriptors.count {
        case 0: return .unavailable
        case 1: return .direct(descriptors[0])
        default: return .choose(descriptors)
        }
    }

    static func mnemonic(for walletId: Data) throws -> MnemonicMaterial {
        let mnemonic = try SwiftDashSDKHost.strictlyPersistedMnemonic(for: walletId)
        let entry = try classify((walletId: walletId, mnemonic: mnemonic))
        return MnemonicMaterial(
            mnemonic: entry.normalizedMnemonic,
            canonicalWalletId: entry.canonicalWalletId,
            network: entry.network)
    }

    static func makeDescriptors(
        entries: [RecoveryPhraseInventoryEntry],
        currentNetwork: RecoveryPhraseWalletNetwork?,
        activeWalletIds: [RecoveryPhraseWalletNetwork: Data],
        displayNames: [Data: String]
    ) throws -> [RecoveryPhraseWalletDescriptor] {
        guard !entries.isEmpty else { return [] }

        let groups = Dictionary(grouping: entries, by: \.canonicalWalletId)
        let descriptors = try groups.map { canonicalWalletId, group -> RecoveryPhraseWalletDescriptor in
            guard let firstMnemonic = group.first?.normalizedMnemonic,
                  group.allSatisfy({ $0.normalizedMnemonic == firstMnemonic }) else {
                throw RecoveryPhraseInventoryError.walletChanged
            }

            let sortedEntries = group.sorted { lhs, rhs in
                if lhs.network != rhs.network {
                    return lhs.network.rawValue < rhs.network.rawValue
                }
                return lhs.walletId.lexicographicallyPrecedes(rhs.walletId)
            }
            let source = currentNetwork.flatMap { current in
                sortedEntries.first(where: { $0.network == current })
            } ?? sortedEntries[0]
            let displayName = displayNames[source.walletId]
                ?? sortedEntries.compactMap { displayNames[$0.walletId] }.first
                ?? WalletsViewModel.fallbackName(for: source.walletId)
            let networks = Array(Set(group.map(\.network))).sorted { $0.rawValue < $1.rawValue }
            let isActive = currentNetwork.map { current in
                guard let activeWalletId = activeWalletIds[current] else { return false }
                return group.contains {
                    $0.network == current && $0.walletId == activeWalletId
                }
            } ?? false

            return RecoveryPhraseWalletDescriptor(
                id: canonicalWalletId,
                sourceWalletId: source.walletId,
                displayName: displayName,
                networks: networks,
                isActive: isActive)
        }

        return descriptors.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.id.lexicographicallyPrecedes(rhs.id)
        }
    }

    private static func classify(
        _ entry: (walletId: Data, mnemonic: String)
    ) throws -> RecoveryPhraseInventoryEntry {
        let mnemonic = Mnemonic.normalizePhrase(entry.mnemonic)
        guard Mnemonic.validate(mnemonic) else {
            throw RecoveryPhraseInventoryError.invalidMnemonic
        }
        let resolution = try SwiftDashSDKStoredWalletNetworkResolver.resolve(
            walletId: entry.walletId,
            mnemonic: mnemonic)
        guard let network = RecoveryPhraseWalletNetwork(sdkNetwork: resolution.network) else {
            throw RecoveryPhraseInventoryError.unsupportedWalletNetwork
        }
        return RecoveryPhraseInventoryEntry(
            walletId: entry.walletId,
            canonicalWalletId: resolution.canonicalMainnetWalletId,
            normalizedMnemonic: mnemonic,
            network: network)
    }
}

struct RecoveryPhrasePresentation {
    let mnemonic: String
    let contextLabel: String?
}

@MainActor
final class RecoveryPhraseFlowViewModel: ObservableObject {
    enum Destination {
        case picker([RecoveryPhraseWalletDescriptor])
        case phrase(RecoveryPhrasePresentation)
    }

    struct NavigationEvent: Identifiable {
        let id = UUID()
        let destination: Destination
    }

    struct AlertState: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum RetryRequest {
        case global
        case wallet(walletId: Data, displayName: String)
        #if DEBUG
        case copy(walletId: Data)
        #endif
    }

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "recovery-phrase-flow")

    @Published private(set) var navigationEvent: NavigationEvent?
    @Published private(set) var alertState: AlertState?
    @Published private(set) var pickerAlertState: AlertState?
    @Published private(set) var isBusy = false

    private var retryRequest: RetryRequest?
    private var pickerRetryDescriptor: RecoveryPhraseWalletDescriptor?

    func beginGlobal() {
        authenticate(for: .global) { [weak self] in
            self?.loadGlobalRoute()
        }
    }

    func beginWallet(walletId: Data, displayName: String) {
        let request = RetryRequest.wallet(walletId: walletId, displayName: displayName)
        authenticate(for: request) { [weak self] in
            self?.loadWallet(walletId: walletId, displayName: displayName)
        }
    }

    #if DEBUG
    func copyWalletMnemonic(walletId: Data) {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let material = try RecoveryPhraseInventory.mnemonic(for: walletId)
            UIPasteboard.general.string = material.mnemonic
        } catch {
            showReadError(error, retry: .copy(walletId: walletId))
        }
    }
    #endif

    func select(_ descriptor: RecoveryPhraseWalletDescriptor) {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let material = try RecoveryPhraseInventory.mnemonic(for: descriptor.sourceWalletId)
            guard material.canonicalWalletId == descriptor.id else {
                throw RecoveryPhraseInventoryError.walletChanged
            }
            emit(.phrase(RecoveryPhrasePresentation(
                mnemonic: material.mnemonic,
                contextLabel: descriptor.contextLabel)))
        } catch {
            Self.logger.error("Selected recovery phrase read failed: \(String(describing: error), privacy: .public)")
            pickerRetryDescriptor = descriptor
            pickerAlertState = Self.readErrorAlert(for: error)
        }
    }

    func consumeNavigationEvent(id: UUID) {
        guard navigationEvent?.id == id else { return }
        navigationEvent = nil
    }

    func dismissAlert() {
        alertState = nil
        retryRequest = nil
    }

    func dismissPickerAlert() {
        pickerAlertState = nil
        pickerRetryDescriptor = nil
    }

    func retryPickerSelection() {
        let descriptor = pickerRetryDescriptor
        pickerAlertState = nil
        pickerRetryDescriptor = nil
        if let descriptor {
            select(descriptor)
        }
    }

    func retry() {
        let request = retryRequest
        alertState = nil
        retryRequest = nil
        switch request {
        case .global:
            beginGlobal()
        case .wallet(let walletId, let displayName):
            beginWallet(walletId: walletId, displayName: displayName)
        #if DEBUG
        case .copy(let walletId):
            copyWalletMnemonic(walletId: walletId)
        #endif
        case .none:
            break
        }
    }

    private func authenticate(for request: RetryRequest, action: @escaping () -> Void) {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            let outcome = await AuthenticationGate.authenticate(biometric: false)
            isBusy = false
            switch outcome {
            case .ok:
                action()
            case .cancelled:
                break
            case .failed, .timedOut:
                retryRequest = request
                alertState = AlertState(
                    title: NSLocalizedString("Authentication failed", comment: ""),
                    message: NSLocalizedString("Please try again", comment: ""))
            }
        }
    }

    private func loadGlobalRoute() {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            switch RecoveryPhraseInventory.route(for: try RecoveryPhraseInventory.load()) {
            case .direct(let descriptor):
                let material = try RecoveryPhraseInventory.mnemonic(for: descriptor.sourceWalletId)
                guard material.canonicalWalletId == descriptor.id else {
                    throw RecoveryPhraseInventoryError.walletChanged
                }
                emit(.phrase(RecoveryPhrasePresentation(
                    mnemonic: material.mnemonic,
                    contextLabel: nil)))
            case .choose(let descriptors):
                emit(.picker(descriptors))
            case .unavailable:
                throw RecoveryPhraseInventoryError.noRecoveryPhrase
            }
        } catch {
            showReadError(error, retry: .global)
        }
    }

    private func loadWallet(walletId: Data, displayName: String) {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let material = try RecoveryPhraseInventory.mnemonic(for: walletId)
            let context = "\(displayName) • \(material.network.displayName)"
            emit(.phrase(RecoveryPhrasePresentation(
                mnemonic: material.mnemonic,
                contextLabel: context)))
        } catch {
            showReadError(
                error,
                retry: .wallet(walletId: walletId, displayName: displayName))
        }
    }

    private func emit(_ destination: Destination) {
        navigationEvent = NavigationEvent(destination: destination)
    }

    private func showReadError(_ error: Error, retry: RetryRequest) {
        Self.logger.error("Recovery phrase read failed: \(String(describing: error), privacy: .public)")
        retryRequest = retry
        alertState = Self.readErrorAlert(for: error)
    }

    private static func readErrorAlert(for error: Error) -> AlertState {
        if case RecoveryPhraseInventoryError.noRecoveryPhrase = error {
            return AlertState(
                title: NSLocalizedString("No Recovery Phrase Found", comment: "Recovery phrase"),
                message: NSLocalizedString(
                    "No recovery phrase is stored on this device.",
                    comment: "Recovery phrase"))
        } else {
            return AlertState(
                title: NSLocalizedString("Couldn’t Read Recovery Phrases", comment: "Recovery phrase"),
                message: NSLocalizedString(
                    "The recovery phrases stored on this device could not be read. Please try again.",
                    comment: "Recovery phrase"))
        }
    }
}

@MainActor
final class RecoveryPhrasePickerViewModel: ObservableObject {
    let options: [RecoveryPhraseWalletDescriptor]

    private let onSelect: (RecoveryPhraseWalletDescriptor) -> Void
    private let onCancel: () -> Void

    init(
        options: [RecoveryPhraseWalletDescriptor],
        onSelect: @escaping (RecoveryPhraseWalletDescriptor) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.options = options
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    func select(_ descriptor: RecoveryPhraseWalletDescriptor) {
        onSelect(descriptor)
    }

    func cancel() {
        onCancel()
    }
}

struct RecoveryPhrasePickerScreen: View {
    @ObservedObject private var flowModel: RecoveryPhraseFlowViewModel
    @StateObject private var viewModel: RecoveryPhrasePickerViewModel

    init(
        options: [RecoveryPhraseWalletDescriptor],
        flowModel: RecoveryPhraseFlowViewModel,
        onCancel: @escaping () -> Void
    ) {
        self.flowModel = flowModel
        _viewModel = StateObject(wrappedValue: RecoveryPhrasePickerViewModel(
            options: options,
            onSelect: { [weak flowModel] descriptor in
                flowModel?.select(descriptor)
            },
            onCancel: { [weak flowModel] in
                flowModel?.dismissPickerAlert()
                onCancel()
            }))
    }

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                NavBarBack { viewModel.cancel() }

                Text(NSLocalizedString("Choose Wallet", comment: "Recovery phrase"))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.dash.primaryText)
                    .padding(.horizontal, 20)
                    .padding(.top, 30)

                Text(NSLocalizedString(
                    "Select the wallet whose recovery phrase you want to view.",
                    comment: "Recovery phrase"))
                    .font(.subheadline)
                    .foregroundColor(.dash.secondaryText)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.options) { option in
                            Button {
                                viewModel.select(option)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.displayName)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.dash.primaryText)
                                            .lineLimit(1)
                                        Text(option.detailsText)
                                            .font(.system(size: 13))
                                            .foregroundColor(.dash.secondaryText)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    if option.isActive {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.dash.blue)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.dash.secondaryText)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .frame(minHeight: 60)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if option.id != viewModel.options.last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color.dash.secondaryBackground)
                    .cornerRadius(12)
                    .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
                    .padding(.horizontal, 20)
                }

                Spacer(minLength: 0)
            }
        }
        .navigationBarHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.cancel()
        }
        .alert(
            flowModel.pickerAlertState?.title ?? "",
            isPresented: Binding(
                get: { flowModel.pickerAlertState != nil },
                set: { if !$0 { flowModel.dismissPickerAlert() } })
        ) {
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                flowModel.dismissPickerAlert()
            }
            Button(NSLocalizedString("Retry", comment: "")) {
                flowModel.retryPickerSelection()
            }
        } message: {
            Text(flowModel.pickerAlertState?.message ?? "")
        }
    }
}

@MainActor
enum RecoveryPhraseNavigation {
    static func pickerController(
        options: [RecoveryPhraseWalletDescriptor],
        flowModel: RecoveryPhraseFlowViewModel,
        onCancel: @escaping () -> Void
    ) -> UIViewController {
        let controller = UIHostingController(rootView: RecoveryPhrasePickerScreen(
            options: options,
            flowModel: flowModel,
            onCancel: onCancel))
        controller.hidesBottomBarWhenPushed = true
        return controller
    }

    static func showPhrase(
        _ presentation: RecoveryPhrasePresentation,
        in navigationController: UINavigationController,
        delegate: DWSecureWalletDelegate?
    ) {
        let model = DWPreviewSeedPhraseModel(existingSeedPhrase: presentation.mnemonic)
        let controller = DWPreviewSeedPhraseViewController(model: model)
        controller.delegate = delegate
        controller.navigationItem.prompt = presentation.contextLabel
        controller.hidesBottomBarWhenPushed = true

        var controllers = navigationController.viewControllers
        if controllers.last is UIHostingController<RecoveryPhrasePickerScreen> {
            controllers[controllers.count - 1] = controller
            navigationController.setViewControllers(controllers, animated: true)
        } else {
            navigationController.pushViewController(controller, animated: true)
        }
    }
}
