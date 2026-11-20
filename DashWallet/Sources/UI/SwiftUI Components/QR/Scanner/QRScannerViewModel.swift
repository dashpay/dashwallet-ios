//
//  QRScannerViewModel.swift
//  DashWallet
//
//  The one QR-scanning state machine. Modes differ only in what payload
//  they primarily expect and what happens to payloads that belong to
//  another flow (route away, offer to route, or reject).
//

import Foundation
import UIKit

// MARK: - QRScannerMode

enum QRScannerMode {
    /// Send-flow scanner (home shortcut, send screens, lock screen).
    /// Validates Dash payment intents live, fetches BIP70/73 requests
    /// inline, and takes contact/invitation QR codes straight to their
    /// flows instead of rejecting them — unless the wallet is locked.
    case payment
    #if DASHPAY
    /// Add-contact scanner: expects `dashpay://user` links; other
    /// recognizable payloads get a one-tap redirect offer.
    case dashPayUser
    /// Invitation scanner (Join DashPay): expects invitation links; other
    /// recognizable payloads get a one-tap redirect offer.
    case invitation
    #endif
    /// Form-field scanner (swap deposit/refund address, evonode payout).
    /// Captures a string; when `expectsDashAddress` a scanned `dash:` URI
    /// is unwrapped to its bare address. Never auto-navigates — a redirect
    /// is only ever offered, since the user is mid-form.
    case addressInput(expectsDashAddress: Bool)
    /// Secret-bearing field (masternode and voting private keys): the
    /// scanned string comes back exactly as read. It is never classified,
    /// offered to another flow, or logged — a private key must not leave
    /// the field it was scanned for.
    case rawText
}

// MARK: - QRScannerViewModel

@MainActor
final class QRScannerViewModel: ObservableObject {
    enum Status {
        case searching
        /// BIP70/73 fetch in flight.
        case connecting
        /// Terminal: a result was accepted and is being delivered.
        case valid
        case invalid(title: String, message: String?)
        /// The payload belongs to another flow; the user may accept the
        /// redirect or keep scanning.
        case offer(payload: QRPayload, message: String, actionTitle: String)
    }

    /// Mirrors the legacy scanner's resume delay after showing an error.
    private static let resumeDelay: Duration = .seconds(2.5)
    /// How long a declined code is passed over while it is likely still in frame.
    private static let declineCooldown: Duration = .seconds(2.5)

    let mode: QRScannerMode
    @Published private(set) var status: Status = .searching
    @Published var torchOn = false

    var onResult: ((QRScanResult) -> Void)?
    var onCancel: (() -> Void)?

    private let inputBuilder = DWPaymentInputBuilder()
    private var paused = false
    private var finished = false
    private var resumeTask: Task<Void, Never>?
    private var currentValue: String?
    private var declined: (value: String, until: ContinuousClock.Instant)?
    /// Keeps the in-flight coordinator alive until its completion fires.
    private var bip70Coordinator: BIP70InteractiveCoordinator?

    /// Read at every decision, not once: the lock can engage while the
    /// scanner is up (the app backgrounds), and a scanner opened from a
    /// screen reachable before unlock (lock screen → Scan to Pay → Send →
    /// Scan QR) is as locked as the lock screen's own.
    private let isWalletLocked: @MainActor () -> Bool
    /// Whether the wallet has the DashPay identity Add Contact sends from.
    private let hasDashPayIdentity: @MainActor () -> Bool
    /// The voucher's structure, read before an invitation is handed over:
    /// storing it takes the wallet's one pending-invitation slot.
    private let checkInvitation: @MainActor (URL) -> QRScanResultRouter.InvitationCheck

    /// The closures are for tests; the app reads the real wallet state.
    init(mode: QRScannerMode,
         isWalletLocked: (@MainActor () -> Bool)? = nil,
         hasDashPayIdentity: (@MainActor () -> Bool)? = nil,
         checkInvitation: (@MainActor (URL) -> QRScanResultRouter.InvitationCheck)? = nil) {
        self.mode = mode
        self.isWalletLocked = isWalletLocked ?? { QRScanResultRouter.isWalletLocked() }
        self.hasDashPayIdentity = hasDashPayIdentity ?? { QRScanResultRouter.hasDashPayIdentity() }
        self.checkInvitation = checkInvitation ?? { QRScanResultRouter.checkInvitation($0) }
    }

    func cancel() {
        // A BIP70 fetch still in flight must not deliver after Cancel.
        finished = true
        bip70Coordinator?.cancelFetch()
        bip70Coordinator = nil
        resumeTask?.cancel()
        onCancel?()
    }

    // MARK: Detection

    func didDetectCodes(_ values: [String]) {
        guard !paused, !finished else { return }
        if let declined, ContinuousClock.now >= declined.until { self.declined = nil }
        let candidates = values.filter { $0 != declined?.value }
        guard let value = preferredValue(in: candidates) else { return }
        paused = true
        currentValue = value
        process(value)
    }

    /// With several codes in frame, the payment scanner prefers a valid
    /// Dash intent anywhere in it (legacy `preferredMetadataObjectInObjects:`
    /// behavior), then a whole request URL, then whatever is first.
    private func preferredValue(in values: [String]) -> String? {
        guard case .payment = mode else { return values.first }
        let payloads = values.map { QRPayload.classify($0) }
        func firstPayment(where matches: (ParsedPaymentURI) -> Bool) -> String? {
            zip(values, payloads).first {
                if case .payment(let parsed) = $0.1 { return matches(parsed) }
                return false
            }?.0
        }
        return firstPayment(where: Self.isUsableDashIntent)
            ?? firstPayment { $0.isWholeRequestURL }
            ?? values.first
    }

    /// A Dash intent the scanner can act on: a request the transport would fetch, or an
    /// address payable on its own.
    private static func isUsableDashIntent(_ parsed: ParsedPaymentURI) -> Bool {
        guard parsed.isValidDashPaymentIntent else { return false }
        if let request = parsed.rURL, PaymentProtocolTransport.isSecure(request) { return true }
        return parsed.isAddressPayableForCurrentNetwork && !parsed.hasInvalidAmount && !parsed.requiresRequest
    }

    private func process(_ value: String) {
        switch mode {
        case .rawText:
            finish(.text(value))

        case .payment:
            processForPayment(QRPayload.classify(value))

        #if DASHPAY
        case .dashPayUser:
            let payload = QRPayload.classify(value)
            if case .dashPayUser(let link) = payload {
                finishDashPayUser(link)
            } else {
                offerRedirect(for: payload, fallbackMessage: notAUserQRMessage)
            }

        case .invitation:
            let payload = QRPayload.classify(value)
            if case .invitation(let url) = payload {
                if !refusesWhileLocked(), !refusesInvitation(url) {
                    finish(.invitation(url))
                }
            } else {
                offerRedirect(for: payload, fallbackMessage: notAnInvitationQRMessage)
            }
        #endif

        case .addressInput(let expectsDashAddress):
            switch QRPayload.classify(value) {
            case .payment(let parsed):
                if parsed.isValidDashPaymentIntent, parsed.rURL != nil {
                    // A merchant request is the merchant's to fill in, not
                    // a field's: offered, never unwrapped.
                    offerPaymentRedirect(parsed, fallbackMessage: nil)
                } else if expectsDashAddress, parsed.isValidDashPaymentIntent,
                          parsed.isAddressValidForCurrentNetwork, let address = parsed.address {
                    // The field wants a bare Dash address; unwrap it from
                    // the payment URI instead of pasting the whole URI.
                    finish(.text(address))
                } else if expectsDashAddress, parsed.rURL == nil, parsed.address != nil,
                          !parsed.isValidDashPaymentIntent {
                    showInvalid(message: invalidQRMessage(for: parsed))
                } else if Self.isOfferablePayment(parsed) {
                    offerPaymentRedirect(parsed, fallbackMessage: nil)
                } else {
                    // Not payable here (a plain https URL): the field
                    // validates its own input.
                    finish(.text(value.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            #if DASHPAY
            case .dashPayUser(let link):
                offerDashPayUserRedirect(link)
            case .invitation(let url):
                offerInvitationRedirect(url)
            #endif
            case .text(let value):
                finish(.text(value))
            }
        }
    }

    // MARK: Payment mode (port of DWQRScanModel)

    private func processForPayment(_ payload: QRPayload) {
        switch payload {
        case .payment(let parsed):
            if parsed.isValidDashPaymentIntent {
                if parsed.rURL != nil {
                    // Start fetching the payment protocol request right away.
                    fetchBIP70(parsed: parsed, fallBackToEmbeddedAddress: true)
                } else {
                    finish(.payment(inputBuilder.paymentInput(withParsedURI: parsed, source: .scanQR)))
                }
            } else if parsed.isWholeRequestURL {
                // A BIP73 http(s) request URL scanned whole → fetch it. A
                // foreign scheme's `r=` is that currency's request, not Dash's.
                fetchBIP70(parsed: parsed, fallBackToEmbeddedAddress: false)
            } else {
                showInvalid(message: invalidQRMessage(for: parsed))
            }

        #if DASHPAY
        case .dashPayUser(let link):
            finishDashPayUser(link)
        case .invitation(let url):
            // Claiming fills the wallet's one pending-invitation slot: only
            // on the user's say-so.
            offerInvitationRedirect(url)
        #endif

        case .text(let value):
            showInvalid(message: invalidQRMessage(for: ParsedPaymentURI.parse(paymentString: value)))
        }
    }

    /// A merchant request whose fetch failed, with its request URL dropped,
    /// when the embedded address and amount are ones the wallet can pay. Any
    /// payable form: a Platform or Shielded address goes on to the Send screen.
    nonisolated static func fallback(afterFailedRequest parsed: ParsedPaymentURI) -> ParsedPaymentURI? {
        guard !parsed.requiresRequest else { return nil }
        let cleared = parsed.byClearingRequestURL()
        guard cleared.isValidDashPaymentIntent, cleared.address != nil else { return nil }
        return cleared
    }

    private func fetchBIP70(parsed: ParsedPaymentURI, fallBackToEmbeddedAddress: Bool) {
        guard let requestURL = parsed.rURL else { return }
        status = .connecting

        let coordinator = BIP70InteractiveCoordinator()
        bip70Coordinator = coordinator
        // No callback scheme: a scan is not an app asking, so none is called back.
        coordinator.fetchAndVerify(
            requestURL: requestURL,
            scheme: parsed.scheme ?? "dash",
            callbackScheme: nil) { [weak self] box, error in
                guard let self, !self.finished else { return }
                self.bip70Coordinator = nil

                if let box {
                    self.finish(.payment(self.inputBuilder.paymentInput(withBIP70Confirmation: box, source: .scanQR)))
                    return
                }

                if fallBackToEmbeddedAddress {
                    if let cleared = Self.fallback(afterFailedRequest: parsed) {
                        self.finish(.payment(self.inputBuilder.paymentInput(withParsedURI: cleared, source: .scanQR)))
                    } else {
                        self.showInvalid(
                            title: NSLocalizedString("Invalid Payment Request", comment: ""),
                            message: error?.localizedDescription)
                    }
                } else {
                    self.showInvalid(message: self.invalidQRMessage(for: parsed))
                }
            }
    }

    // MARK: Offers

    /// Hands a payload that belongs to another flow over to that flow as a
    /// one-tap offer. Payloads with nowhere to go — plain text, and the
    /// BIP70-only payment intents the Send screen cannot prefill — end in
    /// the invalid state carrying `fallbackMessage`.
    private func offerRedirect(for payload: QRPayload, fallbackMessage: String?) {
        switch payload {
        case .payment(let parsed):
            offerPaymentRedirect(parsed, fallbackMessage: fallbackMessage)
        #if DASHPAY
        case .dashPayUser(let link):
            offerDashPayUserRedirect(link)
        case .invitation(let url):
            offerInvitationRedirect(url)
        #endif
        case .text:
            showInvalid(message: fallbackMessage)
        }
    }

    /// A payable address or an explicit Dash merchant request; accepting the
    /// offer fetches a request before the router opens Send. A bare request
    /// URL is not offered.
    nonisolated static func isOfferablePayment(_ parsed: ParsedPaymentURI) -> Bool {
        parsed.isValidDashPaymentIntent && (parsed.address != nil || parsed.rURL != nil)
    }

    private func offerPaymentRedirect(_ parsed: ParsedPaymentURI, fallbackMessage: String?) {
        guard Self.isOfferablePayment(parsed) else {
            showInvalid(message: fallbackMessage ?? invalidQRMessage(for: parsed))
            return
        }
        offer(.payment(parsed),
              message: NSLocalizedString("This QR code is a Dash payment request.", comment: "QR scanner"),
              actionTitle: NSLocalizedString("Open Send", comment: "QR scanner"))
    }

    #if DASHPAY
    /// A contact flow is only reachable unlocked and with an identity to
    /// send the contact request from.
    private func finishDashPayUser(_ link: DashPayUserLink) {
        guard !refusesWhileLocked() else { return }
        guard hasDashPayIdentity() else {
            showInvalid(message: noIdentityMessage)
            return
        }
        finish(.dashPayUser(link))
    }

    private func offerDashPayUserRedirect(_ link: DashPayUserLink) {
        guard !refusesWhileLocked() else { return }
        guard hasDashPayIdentity() else {
            showInvalid(message: noIdentityMessage)
            return
        }
        offer(.dashPayUser(link),
              message: NSLocalizedString("This QR code is a DashPay user.", comment: "QR scanner"),
              actionTitle: NSLocalizedString("View User", comment: "QR scanner"))
    }

    private func offerInvitationRedirect(_ url: URL) {
        guard !refusesWhileLocked(), !refusesInvitation(url) else { return }
        offer(.invitation(url),
              message: NSLocalizedString("This QR code is a DashPay invitation.", comment: "QR scanner"),
              actionTitle: NSLocalizedString("Claim Invitation", comment: "QR scanner"))
    }
    #endif

    /// Nothing is offered while the wallet is locked: accepting would take
    /// the user out of this flow into one the lock is meant to hide.
    private func offer(_ payload: QRPayload, message: String, actionTitle: String) {
        guard !refusesWhileLocked() else { return }
        status = .offer(payload: payload, message: message, actionTitle: actionTitle)
    }

    /// Checked before any other flow's eligibility is read, so a locked
    /// scanner gives the same answer whatever the wallet holds.
    private func refusesWhileLocked() -> Bool {
        guard isWalletLocked() else { return false }
        showInvalid(message: nil)
        return true
    }

    func acceptOffer() {
        guard case .offer(let payload, _, _) = status else { return }
        // The lock may have engaged while the offer was on screen.
        guard !refusesWhileLocked() else { return }
        switch payload {
        case .payment:
            // Use the same BIP70 fetch/verification and address fallback as
            // the payment scanner before handing the result to the router.
            processForPayment(payload)
        #if DASHPAY
        case .dashPayUser(let link):
            finish(.dashPayUser(link))
        case .invitation(let url):
            finish(.invitation(url))
        #endif
        case .text:
            resumeSearch()
        }
    }

    func declineOffer() {
        guard case .offer = status else { return }
        if let currentValue {
            declined = (currentValue, ContinuousClock.now + Self.declineCooldown)
        }
        resumeSearch()
    }

    // MARK: State transitions

    private func finish(_ result: QRScanResult) {
        finished = true
        resumeTask?.cancel()
        status = .valid
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onResult?(result)
    }

    private func showInvalid(title: String = NSLocalizedString("Invalid QR Code", comment: ""),
                             message: String?) {
        status = .invalid(title: title, message: message)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.resumeDelay)
            guard !Task.isCancelled else { return }
            self?.resumeSearch()
        }
    }

    private func resumeSearch() {
        guard !finished else { return }
        status = .searching
        paused = false
    }

    // MARK: Messages

    /// Mirrors the legacy invalid-QR message: an explicit
    /// `dash:<something>` that failed validation reads as a malformed
    /// address; anything else (bare, garbage, foreign scheme) is
    /// "not a Dash QR code".
    private func invalidQRMessage(for parsed: ParsedPaymentURI) -> String {
        if parsed.scheme == "dash", parsed.hasInvalidAmount {
            return NSLocalizedString("Invalid payment amount", comment: "")
        }
        if parsed.scheme == "dash", parsed.requiresRequest, parsed.rURL == nil {
            return NSLocalizedString("Invalid Payment Request", comment: "")
        }
        if parsed.hasExplicitScheme, parsed.scheme == "dash", let address = parsed.address, address.count > 1 {
            return "\(NSLocalizedString("Not a valid Dash address", comment: "")):\n\(address)"
        }
        return NSLocalizedString("Not a Dash QR code", comment: "")
    }

    private var notAUserQRMessage: String {
        NSLocalizedString("This isn't a DashPay user QR code.", comment: "DashPay Contacts: scanned QR is a payment/invitation/foreign code")
    }

    /// Only a voucher the wallet has read as well formed is handed over; one
    /// it cannot read yet is left for a retry, with nothing stored.
    private func refusesInvitation(_ url: URL) -> Bool {
        switch checkInvitation(url) {
        case .valid:
            return false
        case .malformed:
            showInvalid(title: NSLocalizedString("Invalid Invitation", comment: ""),
                        message: NSLocalizedString("This invitation link is not valid.", comment: ""))
        case .unavailable:
            showInvalid(title: NSLocalizedString("Wallet is not ready", comment: "DashPay"), message: nil)
        }
        return true
    }

    private var noIdentityMessage: String {
        NSLocalizedString("No DashPay identity is registered", comment: "DashPay")
    }

    private var notAnInvitationQRMessage: String {
        NSLocalizedString("This isn't an invitation QR code.", comment: "DashPay Invitations")
    }
}
