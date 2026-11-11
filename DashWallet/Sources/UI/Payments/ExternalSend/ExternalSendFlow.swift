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

/// The coordinator behind every external-send entry point: which screen opens first, how the screens hand over
/// to one another and where each outcome leads. A host draws `step` and the ViewModels and reports `onFinish`.
@MainActor
final class ExternalSendFlow: ObservableObject {
    enum Step: Equatable {
        case address
        case send
        case selectSource
        case confirm
        case sendFailed(SendFailedContent)
        case sent(SendSuccessView)
    }

    enum Finish: Equatable {
        case closed
        /// Back from Address to the Send menu it was opened from (SCR-01).
        case backToMenu
        /// The in-progress info Toast over Home.
        case toast(title: String, message: String)
        /// A payment request that could not be fetched and has no address of its own to fall back to.
        case requestFailed(title: String, message: String)
        case success(SendSuccessView, txidWire: Data?, callbackURL: URL?)
    }

    @Published private(set) var step: Step?
    @Published private(set) var addressViewModel: AddressViewModel?
    @Published private(set) var sendViewModel: SendAmountViewModel?
    @Published private(set) var confirmViewModel: ConfirmViewModel?
    @Published private(set) var selectSourceViewModel: SelectSourceViewModel?

    var onFinish: ((Finish) -> Void)?

    private let network: WalletEnvironment.NetworkKind
    private let identityLookup: IdentityLooking
    private let recorder: PreparedSendRecorder
    private let balances: ExternalSendBalanceReading
    private let feeEstimator: SendFeeEstimating
    private let maxPlanner: SendMaxPlanning
    private let converter: SendAmountConverting
    private let currentIdentity: CurrentIdentityReading
    private let paymentRequests: PaymentRequestFetching
    private let clipboard: ClipboardReading
    private let router = SendOutcomeRouter()
    private var pinned: SendSource?
    /// A scan or link is being resolved; another one meanwhile starts nothing.
    private var isHandlingScan = false
    /// A Retry is fetching the payment request again; another Retry meanwhile starts nothing.
    private var isRefetchingRequest = false
    private var destination: Destination?
    private var recipient: IdentityRecipient?

    init(
        network: WalletEnvironment.NetworkKind = WalletEnvironment.networkKind,
        identityLookup: IdentityLooking = IdentityLookupService(
            platform: SwiftDashSDKIdentityPlatformReader(), currentIdentity: WalletCurrentIdentityProvider()),
        executor: ExternalSendExecuting? = nil,
        balances: ExternalSendBalanceReading = LiveExternalSendBalances(),
        feeEstimator: SendFeeEstimating = ExternalSendFeeEstimator(),
        maxPlanner: SendMaxPlanning = LiveSendMaxPlanner(),
        converter: SendAmountConverting = LiveSendAmountConverter(),
        currentIdentity: CurrentIdentityReading = WalletCurrentIdentityReader(),
        paymentRequests: PaymentRequestFetching? = nil,
        clipboard: ClipboardReading = LiveClipboard()
    ) {
        self.network = network
        self.identityLookup = identityLookup
        recorder = PreparedSendRecorder(executor ?? ExternalSendExecutor())
        self.balances = balances
        self.feeEstimator = feeEstimator
        self.maxPlanner = maxPlanner
        self.converter = converter
        self.currentIdentity = currentIdentity
        self.paymentRequests = paymentRequests ?? LivePaymentRequestFetcher()
        self.clipboard = clipboard
    }

    // MARK: - Entry points

    /// Opens the Address screen.
    func start() {
        let address = AddressViewModel(network: network, identityLookup: identityLookup, pasteboard: clipboard)
        address.onResolved = { [weak self] destination, recipient in self?.resolved(destination, recipient) }
        addressViewModel = address
        step = .address
    }

    /// Opens the Address screen with a balance pinned as the source.
    func start(pinned source: SendSource) {
        pinned = source
        start()
    }

    /// Opens Send for a destination that is already known. An Identity ID is checked on Address first.
    func start(destination: Destination, recipient: IdentityRecipient? = nil,
               prefetched: PaymentRequestDetails? = nil) async {
        if addressViewModel == nil { start() }
        if destination.type == .identityID, recipient == nil {
            await addressViewModel?.handleScanned(destination)
        } else {
            await open(destination, recipient, prefetched: prefetched)
        }
    }

    /// For a scanned code or a dash: link; `openedByApp` when another app opened the link. False when the text is not
    /// valid here and nothing opened.
    func start(scanned text: String, openedByApp: Bool = false) async -> Bool {
        await handleScanned(text, openedByApp: openedByApp)
    }

    /// The one acceptance for the Send menu's scanner, the address field's scanner and dash: links: a
    /// `dashwallet://pay=` link is read as the deep-link router reads it, and a payment-request URL scanned whole
    /// (BIP73) is a merchant request. `prefetched` is the request the scanner already fetched, used instead of a
    /// second fetch. False when the text is not valid here and nothing opened; a scan while another one is still
    /// being resolved starts nothing.
    func handleScanned(_ text: String, prefetched: PaymentRequestDetails? = nil,
                       openedByApp: Bool = false) async -> Bool {
        guard !isHandlingScan else { return true }
        isHandlingScan = true
        defer { isHandlingScan = false }
        guard let destination = scannedDestination(text, openedByApp: openedByApp) else { return false }
        await start(destination: destination, prefetched: prefetched)
        return true
    }

    /// What a scanned code or a dash: link pays, without opening anything; nil when it is not valid here. The host
    /// checks it before it is presented, `handleScanned` before it starts.
    func scannedDestination(_ text: String, openedByApp: Bool = false) -> Destination? {
        let paymentString = ParsedPaymentURI.paymentString(for: text)
        if case .success(let parsed) = DestinationParser.parse(paymentString, network: network,
                                                               openedByApp: openedByApp) {
            return parsed
        }
        let trimmed = paymentString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let requestURL = DestinationParser.paymentRequestURL(url) else {
            return nil
        }
        return Destination(type: .paymentRequest, text: "", paymentRequestURL: requestURL)
    }

    // MARK: - Navigation

    func backFromAddress() {
        finish(.backToMenu)
    }

    func backFromSend() {
        sendViewModel = nil
        confirmViewModel = nil
        step = .address
    }

    func showSelectSource() async {
        guard let sendViewModel, let destination else { return }
        let select = SelectSourceViewModel(
            destination: destination, selected: sendViewModel.source, currentIdentity: currentIdentity)
        select.onPick = { [weak self] source in
            guard let self else { return }
            step = .send
            Task { await sendViewModel.pickSource(source) }
        }
        // Shown at once in its loading state; this is the one load.
        selectSourceViewModel = select
        step = .selectSource
        await select.load()
    }

    func closeSelectSource() {
        step = .send
    }

    /// Back to Send for another attempt. A payment request is fetched again first: the one just attempted keeps its
    /// single-use claim once its broadcast was tried, so it cannot be built a second time.
    func retryFromSendFailed() {
        confirmViewModel = nil
        guard let destination, destination.verifiedRequest != nil, let url = destination.paymentRequestURL else {
            step = .send
            return
        }
        guard !isRefetchingRequest else { return }
        isRefetchingRequest = true
        Task { await refetchRequest(url: url, callbackScheme: destination.callbackScheme) }
    }

    func closeFromSendFailed() {
        finish(.closed)
    }

    func close() {
        finish(.closed)
    }

    // MARK: - Internals

    private func resolved(_ destination: Destination, _ recipient: IdentityRecipient?) {
        if Self.needsFetch(destination) {
            Task { await open(destination, recipient) }
        } else {
            openSend(destination, recipient)
        }
    }

    private static func needsFetch(_ destination: Destination) -> Bool {
        destination.type == .paymentRequest || destination.paymentRequestURL != nil
    }

    private func open(_ destination: Destination, _ recipient: IdentityRecipient?,
                      prefetched: PaymentRequestDetails? = nil) async {
        guard Self.needsFetch(destination), let url = destination.paymentRequestURL else {
            openSend(destination, recipient)
            return
        }
        addressViewModel?.beginChecking()
        defer { addressViewModel?.endChecking() }
        do {
            openSend(try await requestDestination(
                url: url, callbackScheme: destination.callbackScheme, prefetched: prefetched), nil)
        } catch {
            guard destination.type == .coreAddress else {
                finishRequestFailed(error)
                return
            }
            // The request URL is dropped and the link's own address is paid, as the current Send does.
            openSend(Destination(
                type: .coreAddress, text: destination.text, isScriptForm: destination.isScriptForm,
                amountDuffs: destination.amountDuffs, label: destination.label, message: destination.message,
                callbackScheme: destination.callbackScheme), nil)
        }
    }

    /// Fetches and verifies the payment request at `url`, or takes `prefetched`, and returns the destination that pays
    /// it.
    private func requestDestination(
        url: URL, callbackScheme: String?, prefetched: PaymentRequestDetails? = nil
    ) async throws -> Destination {
        let details: PaymentRequestDetails
        if let prefetched {
            details = prefetched
        } else {
            details = try await paymentRequests.fetch(url: url, callbackScheme: callbackScheme)
        }
        return Destination(
            type: .coreAddress, text: details.address, amountDuffs: details.amountDuffs,
            label: details.merchantName, message: details.memo, paymentRequestURL: url,
            callbackScheme: callbackScheme, isVerifiedMerchant: details.isSecure,
            verifiedRequest: details.confirmation)
    }

    /// Opens Send for the payment request fetched again, from the source the failed attempt used.
    private func refetchRequest(url: URL, callbackScheme: String?) async {
        defer { isRefetchingRequest = false }
        let source = sendViewModel?.source
        do {
            let fetched = try await requestDestination(url: url, callbackScheme: callbackScheme)
            openSend(fetched, nil, pinnedSource: source)
        } catch {
            finishRequestFailed(error)
        }
    }

    private func finishRequestFailed(_ error: Error) {
        finish(.requestFailed(
            title: NSLocalizedString("Couldn't make payment", comment: "External send"),
            message: error.localizedDescription))
    }

    private func openSend(_ destination: Destination, _ recipient: IdentityRecipient?,
                          pinnedSource: SendSource? = nil) {
        self.destination = destination
        self.recipient = recipient
        let send = SendAmountViewModel(
            destination: destination, pinnedSource: pinnedSource ?? pinned, recipient: recipient, balances: balances,
            feeEstimator: feeEstimator, maxPlanner: maxPlanner, converter: converter, currentIdentity: currentIdentity)
        send.onContinue = { [weak self] request in await self?.openConfirm(request) }
        sendViewModel = send
        step = .send
    }

    /// Authenticates and prepares the send while Send stays on screen, and opens Confirm only once that is over, so
    /// the authentication prompt is never presented while the Confirm sheet animates in. Any prepare that did not
    /// succeed keeps the holder on Send: a fee that could not be read shows there with Send's Try again, so no retry
    /// authenticates over an open sheet.
    private func openConfirm(_ request: SendAmountRequest) async {
        guard let sendViewModel else { return }
        let confirm = ConfirmViewModel(
            request: request, recipient: recipient, executor: recorder, balances: balances, converter: converter)
        confirm.onBackToSend = { [weak self] reason in
            guard let self else { return }
            confirmViewModel = nil
            step = .send
            switch reason {
            case .balanceNotEnough: Task { await sendViewModel.confirmReportedNotEnough() }
            case .feeFailed: sendViewModel.confirmReportedFeeFailure()
            case .cancelled, .authenticationNotCompleted: break
            }
        }
        confirm.onOutcome = { [weak self] outcome in self?.route(outcome, request: request) }
        await confirm.start()
        guard confirm.state == .ready, step == .send, self.sendViewModel === sendViewModel else { return }
        confirmViewModel = confirm
        step = .confirm
    }

    private func route(_ outcome: SendOutcome, request: SendAmountRequest) {
        confirmViewModel = nil
        switch router.destination(for: outcome, request: request) {
        case .success(let shown):
            let txidWire = recorder.lastPrepared?.txidWire
            // A Core send without a txid has no transaction screen to open, so the Sent Toast shows instead.
            let view: SendSuccessView = shown == .transactionDetails && txidWire == nil ? .sentToast : shown
            step = .sent(view)
            finish(.success(view, txidWire: txidWire, callbackURL: recorder.lastPrepared?.callbackURL))
        case let .infoToast(title, message):
            finish(.toast(title: title, message: message))
        case .sendFailed(let content):
            step = .sendFailed(content)
        }
    }

    private func finish(_ result: Finish) {
        onFinish?(result)
    }
}

/// The executor the Confirm sheet uses, keeping the latest prepared send so the flow can read its transaction id
/// and the merchant's callback URL once the send is over.
@MainActor
private final class PreparedSendRecorder: ExternalSendExecuting {
    private let base: ExternalSendExecuting
    private(set) var lastPrepared: PreparedExternalSend?

    init(_ base: ExternalSendExecuting) {
        self.base = base
    }

    func prepare(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool, sweepCredits: UInt64?
    ) async throws -> PreparedExternalSend {
        let prepared = try await base.prepare(
            route: route, destination: destination, amount: amount, isMax: isMax, sweepCredits: sweepCredits)
        lastPrepared = prepared
        return prepared
    }

    func send(_ prepared: PreparedExternalSend) async -> SendOutcome {
        await base.send(prepared)
    }

    func discard(_ prepared: PreparedExternalSend) {
        base.discard(prepared)
    }
}
