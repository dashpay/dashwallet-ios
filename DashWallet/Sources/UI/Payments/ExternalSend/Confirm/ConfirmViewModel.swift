//
//  Created by Roman Chornyi
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
import SwiftDashSDK

/// SCR-06 Confirm and SCR-08 Sending: prepares the exact send (which authenticates), shows From, To, the fee (exact or
/// an estimate, by route), the total and every warning for the pair, and sends on the Confirm tap. Nothing is broadcast
/// before it.
@MainActor
final class ConfirmViewModel: ObservableObject {
    enum State: Equatable {
        case preparing
        case ready
        case sending
    }

    /// Why the sheet closes back onto Send, which keeps everything the holder entered.
    enum BackToSend: Equatable {
        case cancelled
        /// Authentication was cancelled or failed: nothing was prepared.
        case authenticationNotCompleted
        /// The binding fee no longer fits the balance: Send recomputes Max.
        case balanceNotEnough
        /// The binding fee or the balance could not be read: Send shows that the fee could not be calculated, with
        /// Try again.
        case feeFailed
        /// A restored wallet's first sync started running: Send shows its sync note and keeps Continue off.
        case initialRestoreSync
    }

    /// One line of the warning card.
    struct Warning: Identifiable, Equatable {
        enum Style: Equatable {
            case info
            /// A delay: the withdrawal or the processing time.
            case delay
            /// The amount and the destination become public.
            case publicExposure
            /// The send can go on, with a cost the holder should know.
            case caution
        }

        let id: Int
        let style: Style
        let title: String
        let subtitle: String?

        var text: String { subtitle.map { title + "\n" + $0 } ?? title }
    }

    @Published private(set) var state: State = .preparing
    @Published private(set) var warningItems: [Warning] = []
    /// The To row shows the whole recipient instead of the short one.
    @Published private(set) var isRecipientExpanded = false
    /// The binding fee in DASH (an identity's credits converted); nil until prepared.
    @Published private var feeDuffs: UInt64?

    /// Called when the sheet closes onto Send.
    var onBackToSend: ((BackToSend) -> Void)?
    /// Called once with the outcome of the send; routing it is the flow's.
    var onOutcome: ((SendOutcome) -> Void)?

    private let request: SendAmountRequest
    private let recipient: IdentityRecipient?
    private let executor: ExternalSendExecuting
    private let balances: ExternalSendBalanceReading
    private let converter: SendAmountConverting
    private var prepared: PreparedExternalSend?
    private var hasStarted = false
    private var isClosed = false

    init(request: SendAmountRequest, recipient: IdentityRecipient?, executor: ExternalSendExecuting,
         balances: ExternalSendBalanceReading = LiveExternalSendBalances(),
         converter: SendAmountConverting = LiveSendAmountConverter()) {
        self.request = request
        self.recipient = request.destination.type == .identityID ? recipient : nil
        self.executor = executor
        self.balances = balances
        self.converter = converter
    }

    // MARK: - What the sheet shows

    var amountText: String { request.amount.formattedDashAmount }
    var amountDuffs: Int64 { Int64(clamping: request.amount) }
    var amountFiatText: String? { converter.fiatText(forDuffs: request.amount) }
    var fromText: String {
        request.route.source == .shielded
            ? NSLocalizedString("Shielded balance", comment: "External send")
            : SendAmountViewModel.title(of: request.route.source)
    }

    /// A send from Shielded to anything but Shielded shows its warnings inside the card, under Total; every other
    /// route shows them below the card.
    var showsWarningsInCard: Bool {
        request.route.source == .shielded && request.route != .shieldedToShielded
    }

    /// The address, short, or whole once expanded (`toggleRecipient`); an Identity ID shows its username (or "Your
    /// identity"), a link its label and a payment request its merchant before it.
    var toText: String {
        named(isRecipientExpanded
            ? SendAmountViewModel.fullAddress(of: request.destination)
            : SendAmountViewModel.shortAddress(of: request.destination))
    }

    /// What VoiceOver reads for the To row: the whole recipient, expanded or not.
    var toAccessibilityValue: String { named(SendAmountViewModel.fullAddress(of: request.destination)) }

    /// Whether the fee shown is the one the send pays; otherwise fee and total are an estimate marked "~".
    var isFeeExact: Bool { request.route.isFeeExact }

    /// The fee in DASH, "~ " before an estimate; nil while preparing.
    var feeText: String? {
        feeDuffs.map { estimateMark + $0.formattedDashAmount }
    }

    var totalText: String? {
        feeDuffs.map { estimateMark + (request.amount + $0).formattedDashAmount }
    }

    /// What VoiceOver reads for the fee and the total: "about" in place of "~".
    var feeAccessibilityValue: String { spoken(feeDuffs, feeRowText) }
    var totalAccessibilityValue: String { spoken(feeDuffs.map { request.amount + $0 }, totalRowText) }

    var feeRowText: String { feeText ?? Self.calculating }
    var totalRowText: String { totalText ?? Self.calculating }

    var warnings: [String] { warningItems.map(\.text) }

    var isConfirmEnabled: Bool { state == .ready }
    var isCancelVisible: Bool { state != .sending }
    var isDismissLocked: Bool { state == .sending }

    // MARK: - Actions

    /// Authenticates and prepares the send, before the sheet is shown; runs once. It stays `.preparing` when the
    /// holder was sent back to Send.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await prepare()
    }

    func toggleRecipient() {
        isRecipientExpanded.toggle()
    }

    func confirm() async {
        guard state == .ready, let prepared else { return }
        state = .sending
        self.prepared = nil
        let outcome = await executor.send(prepared)
        onOutcome?(outcome)
    }

    /// Discards the prepared send and returns to Send; does nothing while sending.
    func cancel() {
        guard state != .sending else { return }
        isClosed = true
        if let prepared {
            executor.discard(prepared)
            self.prepared = nil
        }
        onBackToSend?(.cancelled)
    }

    #if DEBUG
    /// Lets a SwiftUI preview show a state without the executor and the balance readers.
    func setPreview(state: State, feeDuffs: UInt64?, warnings: [Warning] = []) {
        self.state = state
        self.feeDuffs = feeDuffs
        warningItems = warnings
    }
    #endif

    // MARK: - Internals

    private static let calculating = NSLocalizedString("Calculating…", comment: "External send")

    private var isIdentitySource: Bool { request.route.source == .identity }

    private func named(_ address: String) -> String {
        guard let name = recipient.flatMap(SendAmountViewModel.recipientName(for:))
            ?? SendAmountViewModel.label(of: request.destination) else { return address }
        return name + " · " + address
    }

    private var estimateMark: String { isFeeExact ? "" : "~ " }

    private func spoken(_ duffs: UInt64?, _ shown: String) -> String {
        guard !isFeeExact, let duffs else { return shown }
        return String(format: NSLocalizedString("about %@", comment: "External send"), duffs.formattedDashAmount)
    }

    private func prepare() async {
        let amount = isIdentitySource
            ? request.amount * PlatformPaymentIdentityFundingPolicy.creditsPerDuff : request.amount
        do {
            let result = try await executor.prepare(
                route: request.route, destination: request.destination, amount: amount, isMax: request.isMax,
                sweepCredits: request.sweepCredits)
            guard !isClosed else {
                executor.discard(result)
                return
            }
            prepared = result
            feeDuffs = isIdentitySource ? AmountRules.dashValue(of: result.fee) : result.fee
            warningItems = await makeWarnings(fee: result.fee)
            state = .ready
        } catch let error as ExternalSendError {
            handle(error)
        } catch {
            handle(.feeUnavailable)
        }
    }

    private func handle(_ error: ExternalSendError) {
        guard !isClosed else { return }
        switch error {
        case .authenticationCancelled, .authenticationFailed:
            onBackToSend?(.authenticationNotCompleted)
        case .balanceNotEnough:
            onBackToSend?(.balanceNotEnough)
        case .feeUnavailable, .balanceUnavailable:
            onBackToSend?(.feeFailed)
        case .initialRestoreSync:
            onBackToSend?(.initialRestoreSync)
        }
    }

    /// Who pays the Platform side of a Core asset lock: the top-up takes it out of what the identity receives; the
    /// address funding holds a reserve in the fee and returns what it does not use.
    private static func platformFeeNote(for route: SendRoute) -> String? {
        switch route {
        case .coreToIdentity:
            return NSLocalizedString("The Platform fee is taken from the amount the identity receives.",
                                     comment: "External send")
        case .coreToPlatform:
            return NSLocalizedString(
                "The network fee includes a Platform fee reserve. What is not used returns to your Platform balance.",
                comment: "External send")
        default:
            return nil
        }
    }

    /// The pair's warnings, then the DashPay reserve, then who pays the Platform fee, then the top-up note of the
    /// Current identity.
    private func makeWarnings(fee: UInt64) async -> [Warning] {
        let source = request.route.source
        var items = SendPairPolicy.warnings(source: source, destination: request.destination, isMax: request.isMax)
            .map { Self.content(of: $0, destination: request.destination.type) }
        if source == .identity, let credits = await balances.spendableBalance(of: .identity),
           AmountRules.check(amount: request.amount * PlatformPaymentIdentityFundingPolicy.creditsPerDuff,
                             source: .identity, balance: credits, fee: fee) == .okWithReserveWarning {
            items.append(Self.line(.caution, SendAmountViewModel.reserveWarningText))
        }
        if let note = SendAmountViewModel.note(of: request.destination) {
            items.append(Self.line(.info, note))
        }
        if let platformFeeNote = Self.platformFeeNote(for: request.route) {
            items.append(Self.line(.info, platformFeeNote))
        }
        if let recipient, let notice = SendAmountViewModel.recipientNotice(for: recipient) {
            items.append(Self.line(.info, notice))
        }
        return items.enumerated().map { Warning(id: $0, style: $1.style, title: $1.title, subtitle: $1.subtitle) }
    }

    private static func content(of warning: ConfirmWarning, destination: Destination.Kind) -> Warning {
        switch warning {
        case .shieldedMadePublic where destination == .coreAddress:
            return line(.publicExposure, NSLocalizedString(
                "When sending from Shielded balance to Core the amount and destination becomes public",
                comment: "External send"))
        case .shieldedMadePublic:
            // swiftlint:disable line_length
            return line(.publicExposure, NSLocalizedString(
                "Sending from Shielded to an address that is not Shielded makes the amount and the destination public.", comment: "External send"))
            // swiftlint:enable line_length
        case .shieldedNotInstant:
            return line(.info, NSLocalizedString(
                "When sending from Shielded balance, the transaction is not instant and takes some time",
                comment: "External send"))
        case .wrongAddressReminder:
            return line(.info, SendWarningText.doubleCheckTitle, SendWarningText.doubleCheckBody)
        case .processingTime:
            return line(.delay, SendWarningText.processingTimeTitle, SendWarningText.platformWithdrawalBody)
        case .fullPlatformWithdrawal:
            return line(.info, SendWarningText.fullPlatformWithdrawalBody)
        case .emptyingCoreBalance:
            return line(.info, SendWarningText.coreDrainTitle, SendWarningText.coreDrainBody)
        }
    }

    /// A warning line whose id `makeWarnings` sets once the list is complete.
    private static func line(_ style: Warning.Style, _ title: String, _ subtitle: String? = nil) -> Warning {
        Warning(id: 0, style: style, title: title, subtitle: subtitle)
    }
}
