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
    /// A Core asset-lock send is still waiting for the network's proof of its lock: the sheet explains the wait and
    /// offers Close, which hands the flow `inFlight` while the send finishes.
    @Published private(set) var isWaitingForNetwork = false
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
    /// Close was tapped while the send went on: its outcome no longer reaches the flow.
    private var isReleasedWhileSending = false

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
            ? String(localized: "Shielded balance", comment: "External send")
            : SendAmountViewModel.title(of: request.route.source)
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
        prepared.onSlowNetwork = { [weak self] in self?.isWaitingForNetwork = true }
        let outcome = await executor.send(prepared)
        guard !isReleasedWhileSending else { return }
        if case .notSent(.balanceChanged) = outcome {
            // Nothing was sent: Send plans Max again against the balance as it is now.
            onBackToSend?(.balanceNotEnough)
            return
        }
        onOutcome?(outcome)
    }

    /// Leaves a send that waits for the network: the flow shows it as in progress (it finishes on its own, ADR-0040)
    /// and the send's own result, when it comes, is only logged.
    func closeWhileWaitingForNetwork() {
        guard state == .sending, isWaitingForNetwork, !isReleasedWhileSending else { return }
        isReleasedWhileSending = true
        onOutcome?(.inFlight)
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
    func setPreview(state: State, feeDuffs: UInt64?, warnings: [Warning] = [], waitingForNetwork: Bool = false) {
        self.state = state
        isWaitingForNetwork = waitingForNetwork
        self.feeDuffs = feeDuffs
        warningItems = warnings
    }
    #endif

    // MARK: - Internals

    private static let calculating = String(localized: "Calculating…", comment: "External send")

    private var isIdentitySource: Bool { request.route.source == .identity }

    private func named(_ address: String) -> String {
        guard let name = recipient.flatMap(SendAmountViewModel.recipientName(for:))
            ?? SendAmountViewModel.label(of: request.destination) else { return address }
        return name + " · " + address
    }

    private var estimateMark: String { isFeeExact ? "" : "~ " }

    private func spoken(_ duffs: UInt64?, _ shown: String) -> String {
        guard !isFeeExact, let duffs else { return shown }
        return String(localized: "about \(duffs.formattedDashAmount)", comment: "External send")
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
            let reserveCheck = await identityReserveCheck(fee: result.fee)
            guard !isClosed else { return }
            if request.isMax, isIdentitySource, reserveCheck != .ok {
                // An Identity Max keeps the DashPay reserve: when the balance read after preparing shows it would
                // not, nothing is sent and Send plans Max again; a balance that cannot be read is not offered either,
                // as dispatch would refuse it. A typed amount is only warned.
                executor.discard(result)
                prepared = nil
                onBackToSend?(reserveCheck == nil ? .feeFailed : .balanceNotEnough)
                return
            }
            warningItems = makeWarnings(reserveCheck: reserveCheck)
            guard !isClosed else { return }
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

    /// A Core asset lock to an identity locks Platform's minimum top-up fee on top of the amount, and Platform charges
    /// less, so the identity receives the rest.
    private static func platformFeeNote(for route: SendRoute) -> String? {
        switch route {
        case .coreToIdentity:
            return String(localized: "Any unused part of the Platform fee goes to the identity.",
                                     comment: "External send")
        default:
            return nil
        }
    }

    /// The pair's warnings, then the DashPay reserve, then the link's or request's note and the addresses a request
    /// pays, then where the unused Platform fee goes, then the top-up note of the Current identity.
    private func makeWarnings(reserveCheck: AmountCheck?) -> [Warning] {
        let source = request.route.source
        var items = SendPairPolicy.warnings(source: source, destination: request.destination, isMax: request.isMax)
            .map { Self.content(of: $0, destination: request.destination.type) }
        if reserveCheck == .okWithReserveWarning {
            items.append(Self.line(.caution, SendAmountViewModel.reserveWarningText))
        }
        if let note = SendAmountViewModel.note(of: request.destination) {
            items.append(Self.line(.info, note))
        }
        if let recipients = request.destination.verifiedRequest?.recipientsNotice {
            items.append(Self.line(.info, recipients))
        }
        if let platformFeeNote = Self.platformFeeNote(for: request.route) {
            items.append(Self.line(.info, platformFeeNote))
        }
        if let recipient, let notice = SendAmountViewModel.recipientNotice(for: recipient) {
            items.append(Self.line(.info, notice))
        }
        return items.enumerated().map { Warning(id: $0, style: $1.style, title: $1.title, subtitle: $1.subtitle) }
    }

    /// The amount against the Identity balance as it is now, with the DashPay reserve; nil for another source or when
    /// the balance cannot be read.
    private func identityReserveCheck(fee: UInt64) async -> AmountCheck? {
        guard isIdentitySource, let credits = await balances.spendableBalance(of: .identity) else { return nil }
        return AmountRules.check(amount: request.amount * PlatformPaymentIdentityFundingPolicy.creditsPerDuff,
                                 source: .identity, balance: credits, fee: fee)
    }

    private static func content(of warning: ConfirmWarning, destination: Destination.Kind) -> Warning {
        switch warning {
        case .shieldedMadePublic where destination == .coreAddress:
            return line(.publicExposure, String(
                localized: "When sending from Shielded balance to Core the amount and destination becomes public",
                comment: "External send"))
        case .shieldedMadePublic:
            // swiftlint:disable line_length
            return line(.publicExposure, String(
                localized: "Sending from Shielded to an address that is not Shielded makes the amount and the destination public.", comment: "External send"))
            // swiftlint:enable line_length
        case .shieldedNotInstant:
            return line(.info, String(
                localized: "When sending from Shielded balance, the transaction is not instant and takes some time",
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
