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
/// to one another and where each outcome leads. A host draws `step` and the ViewModels and acts on `onFinish` and
/// `onRequestFailed`. The flow is the one owner of its lifetime: a `Finish` ends it once, and a host forwards every
/// dismissal to `close()`.
@MainActor
final class ExternalSendFlow: ObservableObject {
    enum Step: Equatable {
        case address
        case send
        case selectSource
        case confirm
        case sendFailed(SendFailedContent)
        /// The money is held in an asset lock; `lockHeldViewModel` draws it.
        case lockHeld
        case sent(SendSuccessView)
    }

    /// How the flow ended. Each one is terminal: Address closes, the flow's open work is cancelled and nothing is
    /// reported after it.
    enum Finish: Equatable {
        case closed
        /// Back from Address to the Send menu it was opened from (SCR-01).
        case backToMenu
        /// The in-progress info Toast over Home.
        case toast(title: String, message: String)
        case success(SendSuccessView, txidWire: Data?, callbackURL: URL?)
    }

    /// A payment request that could not be fetched and has no address of its own to fall back to. Recoverable: the
    /// flow stays open on Address for a correction.
    struct RequestFailure: Equatable {
        let title: String
        let message: String
    }

    @Published private(set) var step: Step?
    @Published private(set) var addressViewModel: AddressViewModel?
    @Published private(set) var sendViewModel: SendAmountViewModel?
    @Published private(set) var confirmViewModel: ConfirmViewModel?
    @Published private(set) var selectSourceViewModel: SelectSourceViewModel?
    @Published private(set) var lockHeldViewModel: SendLockHeldViewModel?

    var onFinish: ((Finish) -> Void)?
    var onRequestFailed: ((RequestFailure) -> Void)?

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
    private let initialRestoreSync: AnyPublisher<Bool, Never>
    private let initialRestoreSyncNow: () -> Bool
    private let lockResumer: HeldAssetLockResuming
    private let proverWarmUp: ShieldedProverWarmUp
    private let router = SendOutcomeRouter()
    private var pinned: SendSource?
    /// A scan or link is being opened, from `open(_:)` until it reached a screen the holder can act on or the flow
    /// ended; another one meanwhile starts nothing.
    private(set) var isOpening = false
    /// The id of the last `open(_:)`: an open releases `isOpening` only while it is still the last one.
    private var openID = 0
    /// A `Finish` was reported: nothing opens or reports after it.
    private var isEnded = false
    /// A Retry is fetching the payment request again; another Retry meanwhile starts nothing.
    @Published private(set) var isRefetchingRequest = false
    /// Why Retry's fetch of the payment request failed, shown on the Send-failed sheet that is on screen then; a new
    /// Retry clears it.
    @Published private(set) var retryFailure: RequestFailure?
    /// The Retry's fetch, cancelled when the flow closes so a closed flow does not open Send.
    private var refetchTask: Task<Void, Never>?
    /// The open of a scanned, linked or resolved destination (its Identity check or its payment-request fetch),
    /// cancelled when another one starts or the flow ends so it does not open Send on a flow that is gone.
    private var openTask: Task<Void, Never>?
    private var destination: Destination?
    private var recipient: IdentityRecipient?
    /// The Confirm whose send is being prepared while Send is on screen. Leaving Send or another Continue abandons it.
    private var preparing: ConfirmViewModel?

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
        clipboard: ClipboardReading = LiveClipboard(),
        initialRestoreSync: AnyPublisher<Bool, Never> = WalletSendService.coreSpendBlockedByInitialRestoreSync,
        initialRestoreSyncNow: @escaping () -> Bool = { WalletSendService.isCoreSpendBlockedByInitialRestoreSync },
        lockResumer: HeldAssetLockResuming? = nil,
        proverWarmUp: ShieldedProverWarmUp? = nil
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
        self.initialRestoreSync = initialRestoreSync
        self.initialRestoreSyncNow = initialRestoreSyncNow
        self.lockResumer = lockResumer ?? LiveHeldAssetLockResumer()
        self.proverWarmUp = proverWarmUp ?? .shared
    }

    // MARK: - Entry points

    /// Opens the Address screen, and starts building the Shielded prover's key when Shielded holds money.
    func start() {
        guard !isEnded else { return }
        let address = AddressViewModel(network: network, identityLookup: identityLookup, pasteboard: clipboard)
        address.onResolved = { [weak self] destination, recipient in self?.resolved(destination, recipient) }
        addressViewModel = address
        step = .address
        proverWarmUp.startIfNeeded()
    }

    /// Opens the Address screen with a balance pinned as the source.
    func start(pinned source: SendSource) {
        pinned = source
        start()
    }

    /// Opens Send for a destination that is already known. An Identity ID is checked on Address first.
    func start(destination: Destination, recipient: IdentityRecipient? = nil,
               prefetched: PaymentRequestDetails? = nil) async {
        guard !isEnded else { return }
        if addressViewModel == nil { start() }
        // Tracked like a typed entry, so ending the flow cancels the check or the fetch and a late answer opens
        // nothing.
        openTask?.cancel()
        let task = Task<Void, Never> {
            if destination.type == .identityID, recipient == nil {
                await addressViewModel?.handleScanned(destination)
            } else {
                // Address shows what opened Send, so Back returns to it.
                addressViewModel?.show(destination)
                await open(destination, recipient, prefetched: prefetched)
            }
        }
        openTask = task
        await task.value
    }

    /// The one entry for the Send menu's scanner, the address field's scanner and dash: links, with the scan or link
    /// read once into `input`. Address shows at once and `isOpening` holds from this call until the input reached a
    /// screen the holder can act on, a request failed, or the flow ended; an earlier open that ends later does not
    /// release it. A request the scanner already fetched is used instead of a second fetch. Returns the task opening
    /// it; nil when another scan is being opened or the flow ended, and nothing starts.
    @discardableResult
    func open(_ input: ScanInput) -> Task<Void, Never>? {
        guard !isOpening, !isEnded else { return nil }
        if addressViewModel == nil { start() }
        isOpening = true
        openID += 1
        let id = openID
        return Task {
            await start(destination: input.destination, prefetched: input.prefetched)
            if id == openID { isOpening = false }
        }
    }

    // MARK: - Navigation

    func backFromAddress() {
        finish(.backToMenu)
    }

    func backFromSend() {
        guard !isEnded else { return }
        abandonPreparation()
        sendViewModel = nil
        confirmViewModel = nil
        step = .address
    }

    func showSelectSource() async {
        guard !isEnded, let sendViewModel, let destination else { return }
        abandonPreparation()
        let select = SelectSourceViewModel(
            destination: destination, selected: sendViewModel.source, currentIdentity: currentIdentity)
        select.onPick = { [weak self] source in
            guard let self, !isEnded else { return }
            step = .send
            Task { await sendViewModel.pickSource(source) }
        }
        // Shown at once in its loading state; this is the one load.
        selectSourceViewModel = select
        step = .selectSource
        await select.load()
    }

    func closeSelectSource() {
        guard !isEnded else { return }
        step = .send
    }

    /// Back to Send for another attempt. A payment request is fetched again first: the one just attempted keeps its
    /// single-use claim once its broadcast was tried, so it cannot be built a second time.
    func retryFromSendFailed() {
        guard !isEnded else { return }
        confirmViewModel = nil
        guard let destination, destination.verifiedRequest != nil, let url = destination.paymentRequestURL else {
            step = .send
            return
        }
        guard !isRefetchingRequest else { return }
        retryFailure = nil
        isRefetchingRequest = true
        refetchTask = Task {
            await refetchRequest(url: url, callbackScheme: destination.callbackScheme,
                                 isCallbackRequired: destination.isCallbackRequired)
        }
    }

    /// Leaves the held lock for the transaction details' Rebroadcast. Allowed while Finish runs, because the resume can
    /// wait for the lock's proof without a deadline: the resume is not cancelled and goes on, and the result it
    /// reports after the flow ended is dropped (`finish` runs once).
    func closeFromLockHeld() {
        if lockHeldViewModel?.isFinishing == true {
            DWLogger.log("External send: left the held-lock sheet while Finish runs")
        }
        finish(.closed)
    }

    func closeFromSendFailed() {
        finish(.closed)
    }

    /// The holder's Close, and every dismissal of the host. A flow that already ended reports nothing.
    func close() {
        finish(.closed)
    }

    // MARK: - Internals

    private func resolved(_ destination: Destination, _ recipient: IdentityRecipient?) {
        guard !isEnded else { return }
        if Self.needsFetch(destination) {
            openTask?.cancel()
            openTask = Task { await open(destination, recipient) }
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
            let fetched = try await requestDestination(
                url: url, callbackScheme: destination.callbackScheme,
                isCallbackRequired: destination.isCallbackRequired, prefetched: prefetched)
            guard !Task.isCancelled else { return }
            openSend(fetched, nil)
        } catch {
            guard !Task.isCancelled else { return }
            // A required request (`req-r`) is never replaced by the link's own address.
            guard destination.type == .coreAddress, !destination.isPaymentRequestRequired else {
                finishRequestFailed(error)
                return
            }
            // An optional request URL is dropped and the link's own address is paid, as the current Send does.
            openSend(destination.droppingPaymentRequest(), nil)
        }
    }

    /// Fetches and verifies the payment request at `url`, or takes `prefetched`, and returns the destination that pays
    /// it.
    private func requestDestination(
        url: URL, callbackScheme: String?, isCallbackRequired: Bool = false, prefetched: PaymentRequestDetails? = nil
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
            callbackScheme: callbackScheme, isCallbackRequired: isCallbackRequired, isVerifiedMerchant: details.isSecure,
            verifiedRequest: details.confirmation)
    }

    /// Opens Send for the payment request fetched again, from the source the failed attempt used.
    /// Opens Send for the payment request fetched again, from the source the failed attempt used. A fetch the flow
    /// cancelled opens nothing and reports nothing.
    private func refetchRequest(url: URL, callbackScheme: String?, isCallbackRequired: Bool) async {
        let source = sendViewModel?.source
        do {
            let fetched = try await requestDestination(
                url: url, callbackScheme: callbackScheme, isCallbackRequired: isCallbackRequired)
            guard !Task.isCancelled else { return }
            endRefetch()
            openSend(fetched, nil, pinnedSource: source)
        } catch {
            guard !Task.isCancelled else { return }
            endRefetch()
            retryFailure = Self.requestFailure(error)
        }
    }

    private func endRefetch() {
        refetchTask = nil
        isRefetchingRequest = false
    }

    private func cancelRefetch() {
        refetchTask?.cancel()
        endRefetch()
    }

    /// Recoverable: the flow stays open on Address, so the open is over but nothing is closed.
    private func finishRequestFailed(_ error: Error) {
        isOpening = false
        onRequestFailed?(Self.requestFailure(error))
    }

    private static func requestFailure(_ error: Error) -> RequestFailure {
        RequestFailure(title: String(localized: "Couldn't make payment", comment: "External send"),
                       message: error.localizedDescription)
    }

    private func openSend(_ destination: Destination, _ recipient: IdentityRecipient?,
                          pinnedSource: SendSource? = nil) {
        guard !isEnded else { return }
        abandonPreparation()
        self.destination = destination
        self.recipient = recipient
        let send = SendAmountViewModel(
            destination: destination, pinnedSource: pinnedSource ?? pinned, recipient: recipient, balances: balances,
            feeEstimator: feeEstimator, maxPlanner: maxPlanner, converter: converter, currentIdentity: currentIdentity,
            initialRestoreSync: initialRestoreSync, initialRestoreSyncNow: initialRestoreSyncNow)
        send.onContinue = { [weak self] request in await self?.openConfirm(request) }
        sendViewModel = send
        step = .send
    }

    /// Authenticates and prepares the send while Send stays on screen, and opens Confirm only once that is over, so
    /// the authentication prompt is never presented while the Confirm sheet animates in. Any prepare that did not
    /// succeed keeps the holder on Send: a fee that could not be read shows there with Send's Try again, so no retry
    /// authenticates over an open sheet. Only the latest preparation can open Confirm: one the flow has left is
    /// cancelled, which discards its send.
    private func openConfirm(_ request: SendAmountRequest) async {
        guard !isEnded, let sendViewModel else { return }
        let confirm = ConfirmViewModel(
            request: request, recipient: recipient, executor: recorder, balances: balances, converter: converter)
        confirm.onBackToSend = { [weak self] reason in
            guard let self, !isEnded else { return }
            confirmViewModel = nil
            step = .send
            switch reason {
            case .balanceNotEnough: Task { await sendViewModel.confirmReportedNotEnough() }
            case .feeFailed: sendViewModel.confirmReportedFeeFailure()
            case .initialRestoreSync: sendViewModel.confirmReportedRestoreSync()
            case .cancelled, .authenticationNotCompleted: break
            }
        }
        confirm.onOutcome = { [weak self] outcome in self?.route(outcome, request: request) }
        abandonPreparation()
        preparing = confirm
        await confirm.start()
        let isCurrent = preparing === confirm && step == .send && self.sendViewModel === sendViewModel
        if preparing === confirm { preparing = nil }
        guard isCurrent else { return abandon(confirm) }
        guard confirm.state == .ready else { return }
        confirmViewModel = confirm
        step = .confirm
    }

    private func abandonPreparation() {
        guard let confirm = preparing else { return }
        preparing = nil
        abandon(confirm)
    }

    /// Cancels a Confirm the flow has left without letting it report back: its send is discarded, at once when it is
    /// prepared or as soon as the preparation returns, and a preparation that fails shows nothing.
    private func abandon(_ confirm: ConfirmViewModel) {
        confirm.onBackToSend = nil
        confirm.onOutcome = nil
        confirm.cancel()
    }

    /// An outcome that arrives after the flow ended (the host was dismissed while the send ran) moves no step.
    private func route(_ outcome: SendOutcome, request: SendAmountRequest) {
        guard !isEnded else { return }
        confirmViewModel = nil
        switch router.destination(for: outcome, request: request) {
        case .success(let shown):
            let txidWire = recorder.lastSent?.txidWire
            // A Core send without a txid has no transaction screen to open, so the Sent Toast shows instead.
            let view: SendSuccessView = shown == .transactionDetails && txidWire == nil ? .sentToast : shown
            step = .sent(view)
            finish(.success(view, txidWire: txidWire, callbackURL: recorder.lastSent?.callbackURL))
        case let .infoToast(title, message):
            finish(.toast(title: title, message: message))
        case .sendFailed(let content):
            step = .sendFailed(content)
        case .lockHeld(let lock):
            let viewModel = SendLockHeldViewModel(lock: lock, resumer: lockResumer)
            viewModel.onFinished = { [weak self] result in self?.finishedLockHeld(result) }
            lockHeldViewModel = viewModel
            step = .lockHeld
        }
    }

    private func finishedLockHeld(_ result: SendLockHeldViewModel.Result) {
        guard !isEnded else { return }
        switch result {
        case .completed:
            step = .sent(.sentToast)
            finish(.success(.sentToast, txidWire: nil, callbackURL: nil))
        case .info(let message):
            finish(.toast(title: "", message: message))
        }
    }

    /// Ends the flow once: releases the opening, cancels the open, the Retry's fetch and a preparation still running,
    /// closes Address and reports `result`. Later calls do nothing.
    private func finish(_ result: Finish) {
        guard !isEnded else { return }
        isEnded = true
        isOpening = false
        openTask?.cancel()
        cancelRefetch()
        abandonPreparation()
        addressViewModel?.close()
        onFinish?(result)
    }
}

/// The executor the Confirm sheet uses, keeping the send it last ran so the flow can read its transaction id and the
/// merchant's callback URL once the send is over. A preparation that finishes later never takes its place.
@MainActor
private final class PreparedSendRecorder: ExternalSendExecuting {
    private let base: ExternalSendExecuting
    private(set) var lastSent: PreparedExternalSend?

    init(_ base: ExternalSendExecuting) {
        self.base = base
    }

    func prepare(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool, sweepCredits: UInt64?
    ) async throws -> PreparedExternalSend {
        try await base.prepare(
            route: route, destination: destination, amount: amount, isMax: isMax, sweepCredits: sweepCredits)
    }

    func send(_ prepared: PreparedExternalSend) async -> SendOutcome {
        lastSent = prepared
        return await base.send(prepared)
    }

    func discard(_ prepared: PreparedExternalSend) {
        base.discard(prepared)
    }
}
