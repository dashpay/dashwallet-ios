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
        /// The binding fee or the balance could not be read: Confirm is blocked and Try again prepares anew.
        case feeFailed
        case sending
    }

    /// Why the sheet closes back onto Send, which keeps everything the holder entered.
    enum BackToSend: Equatable {
        case cancelled
        /// Authentication was cancelled or failed: nothing was prepared.
        case authenticationNotCompleted
        /// The binding fee no longer fits the balance: Send recomputes Max.
        case balanceNotEnough
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
    @Published private var blockReason: BlockReason?
    /// The binding fee in DASH (an identity's credits converted); nil until prepared.
    @Published private var feeDuffs: UInt64?

    /// Called when the sheet closes onto Send.
    var onBackToSend: ((BackToSend) -> Void)?
    /// Called once with the outcome of the send; routing it is the flow's.
    var onOutcome: ((SendOutcome) -> Void)?

    private enum BlockReason {
        case fee
        case balance
    }

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
    var fromText: String { SendAmountViewModel.title(of: request.route.source) }

    /// The address, short; an Identity ID shows its username (or "Your identity"), a link its label and a payment
    /// request its merchant before it.
    var toText: String {
        let short = SendAmountViewModel.shortAddress(of: request.destination)
        guard let name = recipient.flatMap(SendAmountViewModel.recipientName(for:))
            ?? SendAmountViewModel.label(of: request.destination) else { return short }
        return name + " · " + short
    }

    /// Whether the fee shown is the one the send pays; otherwise fee and total are an estimate marked "~".
    var isFeeExact: Bool { request.route.isFeeExact }

    /// The fee in DASH, "~ " before an estimate; "—" when it could not be calculated; nil while preparing.
    var feeText: String? {
        if state == .feeFailed { return Self.unknown }
        return feeDuffs.map { estimateMark + $0.formattedDashAmount }
    }

    var totalText: String? {
        if state == .feeFailed { return Self.unknown }
        return feeDuffs.map { estimateMark + (request.amount + $0).formattedDashAmount }
    }

    /// The line under the fee when it is an estimate; nil while there is no fee to qualify.
    var feeEstimateNote: String? {
        guard !isFeeExact, feeDuffs != nil, state != .feeFailed else { return nil }
        return NSLocalizedString("Estimated. The network sets the final fee.", comment: "External send")
    }

    /// What VoiceOver reads for the fee and the total: "about" in place of "~".
    var feeAccessibilityValue: String { spoken(feeDuffs, feeRowText) }
    var totalAccessibilityValue: String { spoken(feeDuffs.map { request.amount + $0 }, totalRowText) }

    var feeRowText: String { feeText ?? Self.calculating }
    var totalRowText: String { totalText ?? Self.calculating }

    var warnings: [String] { warningItems.map(\.text) }

    var blockedMessage: String? {
        switch blockReason {
        case .fee?:
            return SendAmountViewModel.feeFailureText
        case .balance?:
            return NSLocalizedString("Couldn't read your balance. Check your connection and try again.",
                                     comment: "External send")
        case nil:
            return nil
        }
    }

    var isConfirmEnabled: Bool { state == .ready }
    var isCancelVisible: Bool { state != .sending }
    var isDismissLocked: Bool { state == .sending }

    // MARK: - Actions

    /// Authenticates and prepares the send; runs once however often the sheet appears.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await prepare()
    }

    /// Prepares again, which authenticates again.
    func tryAgain() async {
        guard state == .feeFailed else { return }
        await prepare()
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
    func setPreview(state: State, feeDuffs: UInt64?, warnings: [Warning] = [], blocked: Bool = false,
                    balanceUnreadable: Bool = false) {
        self.state = state
        self.feeDuffs = feeDuffs
        warningItems = warnings
        blockReason = blocked ? (balanceUnreadable ? .balance : .fee) : nil
    }
    #endif

    // MARK: - Internals

    private static let unknown = "—"
    private static let calculating = NSLocalizedString("Calculating…", comment: "External send")

    private var isIdentitySource: Bool { request.route.source == .identity }

    private var estimateMark: String { isFeeExact ? "" : "~ " }

    private func spoken(_ duffs: UInt64?, _ shown: String) -> String {
        guard !isFeeExact, state != .feeFailed, let duffs else { return shown }
        return String(format: NSLocalizedString("about %@", comment: "External send"), duffs.formattedDashAmount)
    }

    private func prepare() async {
        state = .preparing
        blockReason = nil
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
            block(.fee)
        }
    }

    private func handle(_ error: ExternalSendError) {
        guard !isClosed else { return }
        switch error {
        case .authenticationCancelled, .authenticationFailed:
            onBackToSend?(.authenticationNotCompleted)
        case .balanceNotEnough:
            onBackToSend?(.balanceNotEnough)
        case .feeUnavailable:
            block(.fee)
        case .balanceUnavailable:
            block(.balance)
        }
    }

    private func block(_ reason: BlockReason) {
        feeDuffs = nil
        blockReason = reason
        state = .feeFailed
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

    /// The pair's warnings, then the DashPay reserve, then who pays the Platform fee, then what the money does at an
    /// Identity ID.
    private func makeWarnings(fee: UInt64) async -> [Warning] {
        let source = request.route.source
        var items = SendPairPolicy.warnings(source: source, destination: request.destination, isMax: request.isMax)
            .map { Self.content(of: $0, source: source) }
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
        if let recipient {
            items.append(Self.line(.info, SendAmountViewModel.recipientNotice(for: recipient)))
        }
        return items.enumerated().map { Warning(id: $0, style: $1.style, title: $1.title, subtitle: $1.subtitle) }
    }

    private static func content(of warning: ConfirmWarning, source: SendSource) -> Warning {
        switch warning {
        case .withdrawalDelay:
            return line(.delay, NSLocalizedString(
                "This is a withdrawal. It arrives on Core after a delay.", comment: "External send"))
        case .shieldedMadePublic:
            // swiftlint:disable line_length
            return line(.publicExposure, NSLocalizedString(
                "Sending from Shielded to an address that is not Shielded makes the amount and the destination public.", comment: "External send"))
            // swiftlint:enable line_length
        case .wrongAddressReminder:
            return line(.info, SendWarningText.doubleCheckTitle, SendWarningText.doubleCheckBody)
        case .processingTime:
            return line(.delay, SendWarningText.processingTimeTitle, source == .shielded
                ? SendWarningText.shieldedWithdrawalBody : SendWarningText.platformWithdrawalBody)
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
