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

    let mode: QRScannerMode
    @Published private(set) var status: Status = .searching
    @Published var torchOn = false

    var onResult: ((QRScanResult) -> Void)?
    var onCancel: (() -> Void)?

    private let inputBuilder = DWPaymentInputBuilder()
    private var paused = false
    private var finished = false
    private var resumeTask: Task<Void, Never>?
    /// Keeps the in-flight coordinator alive until its completion fires.
    private var bip70Coordinator: BIP70InteractiveCoordinator?

    /// Read at every decision, not once: the lock can engage while the
    /// scanner is up (the app backgrounds), and a scanner opened from a
    /// screen reachable before unlock (lock screen → Scan to Pay → Send →
    /// Scan QR) is as locked as the lock screen's own.
    private let isWalletLocked: @MainActor () -> Bool

    /// `isWalletLocked` is for tests; the app reads the real lock state.
    init(mode: QRScannerMode, isWalletLocked: (@MainActor () -> Bool)? = nil) {
        self.mode = mode
        self.isWalletLocked = isWalletLocked ?? { QRScanResultRouter.isWalletLocked() }
    }

    func cancel() {
        // A BIP70 fetch still in flight must not deliver after Cancel.
        finished = true
        bip70Coordinator = nil
        resumeTask?.cancel()
        onCancel?()
    }

    // MARK: Detection

    func didDetectCodes(_ values: [String]) {
        guard !paused, !finished, let value = preferredValue(in: values) else { return }
        paused = true
        process(value)
    }

    /// With several codes in frame, the payment scanner prefers a valid
    /// Dash intent over whatever happens to be first (legacy
    /// `preferredMetadataObjectInObjects:` behavior).
    private func preferredValue(in values: [String]) -> String? {
        guard case .payment = mode else { return values.first }
        let preferred = values.first {
            ParsedPaymentURI.parse(paymentString: $0.trimmingCharacters(in: .whitespacesAndNewlines))
                .isValidDashPaymentIntent
        }
        return preferred ?? values.first
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
                finish(.dashPayUser(link))
            } else {
                offerRedirect(for: payload, fallbackMessage: notAUserQRMessage)
            }

        case .invitation:
            let payload = QRPayload.classify(value)
            if case .invitation(let url) = payload {
                finish(.invitation(url))
            } else {
                offerRedirect(for: payload, fallbackMessage: notAnInvitationQRMessage)
            }
        #endif

        case .addressInput(let expectsDashAddress):
            switch QRPayload.classify(value) {
            case .payment(let parsed):
                if expectsDashAddress, parsed.isAddressValidForCurrentNetwork, let address = parsed.address {
                    // The field wants a bare Dash address; unwrap it from
                    // the payment URI instead of pasting the whole URI.
                    finish(.text(address))
                } else if expectsDashAddress, parsed.rURL == nil, parsed.address != nil {
                    showInvalid(message: invalidQRMessage(for: parsed))
                } else if parsed.isAddressPayableForCurrentNetwork, parsed.address != nil {
                    offerPaymentRedirect(parsed, fallbackMessage: nil)
                } else {
                    // Not payable here (a plain https URL, a Platform
                    // address): the field validates its own input.
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
            } else if parsed.rURL != nil {
                // Not a valid Dash intent, but a BIP73 http(s) request URL
                // scanned whole → fetch it.
                fetchBIP70(parsed: parsed, fallBackToEmbeddedAddress: false)
            } else {
                showInvalid(message: invalidQRMessage(for: parsed))
            }

        #if DASHPAY
        case .dashPayUser(let link):
            finishLeavingFlow(.dashPayUser(link))
        case .invitation(let url):
            finishLeavingFlow(.invitation(url))
        #endif

        case .text(let value):
            showInvalid(message: invalidQRMessage(for: ParsedPaymentURI.parse(paymentString: value)))
        }
    }

    private func fetchBIP70(parsed: ParsedPaymentURI, fallBackToEmbeddedAddress: Bool) {
        guard let requestURL = parsed.rURL else { return }
        status = .connecting

        let coordinator = BIP70InteractiveCoordinator()
        bip70Coordinator = coordinator
        coordinator.fetchAndVerify(
            requestURL: requestURL,
            scheme: parsed.scheme ?? "dash",
            callbackScheme: parsed.callbackScheme) { [weak self] box, error in
                guard let self, !self.finished else { return }
                self.bip70Coordinator = nil

                if let box {
                    self.finish(.payment(self.inputBuilder.paymentInput(withBIP70Confirmation: box, source: .scanQR)))
                    return
                }

                if fallBackToEmbeddedAddress {
                    // Fetch failed → drop the request URL and fall back to
                    // the embedded address, if any. Any payable form: a
                    // Platform or Shielded one goes on to the Send screen.
                    let cleared = parsed.byClearingRequestURL()
                    if cleared.isAddressPayableForCurrentNetwork, cleared.address != nil {
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

    /// Payment redirects are only offered for address-carrying intents —
    /// the router opens the Send screen prefilled, which a BIP70-only
    /// payload can't do. Those fall through to the invalid state.
    private func offerPaymentRedirect(_ parsed: ParsedPaymentURI, fallbackMessage: String?) {
        guard parsed.isAddressPayableForCurrentNetwork, parsed.address != nil else {
            showInvalid(message: fallbackMessage ?? invalidQRMessage(for: parsed))
            return
        }
        offer(.payment(parsed),
              message: NSLocalizedString("This QR code is a Dash payment request.", comment: "QR scanner"),
              actionTitle: NSLocalizedString("Open Send", comment: "QR scanner"))
    }

    #if DASHPAY
    private func offerDashPayUserRedirect(_ link: DashPayUserLink) {
        offer(.dashPayUser(link),
              message: NSLocalizedString("This QR code is a DashPay user.", comment: "QR scanner"),
              actionTitle: NSLocalizedString("View User", comment: "QR scanner"))
    }

    private func offerInvitationRedirect(_ url: URL) {
        offer(.invitation(url),
              message: NSLocalizedString("This QR code is a DashPay invitation.", comment: "QR scanner"),
              actionTitle: NSLocalizedString("Claim Invitation", comment: "QR scanner"))
    }
    #endif

    /// Nothing is offered while the wallet is locked: accepting would take
    /// the user out of this flow into one the lock is meant to hide.
    private func offer(_ payload: QRPayload, message: String, actionTitle: String) {
        guard !isWalletLocked() else {
            showInvalid(message: nil)
            return
        }
        status = .offer(payload: payload, message: message, actionTitle: actionTitle)
    }

    func acceptOffer() {
        guard case .offer(let payload, _, _) = status else { return }
        // The lock may have engaged while the offer was on screen.
        guard !isWalletLocked() else {
            showInvalid(message: nil)
            return
        }
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
        resumeSearch()
    }

    // MARK: State transitions

    #if DASHPAY
    /// A payload that belongs to another flow, accepted straight from the
    /// payment scanner: only while the wallet is unlocked.
    private func finishLeavingFlow(_ result: QRScanResult) {
        if isWalletLocked() {
            showInvalid(message: nil)
        } else {
            finish(result)
        }
    }
    #endif

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
        if parsed.hasExplicitScheme, parsed.scheme == "dash", let address = parsed.address, address.count > 1 {
            return "\(NSLocalizedString("Not a valid Dash address", comment: "")):\n\(address)"
        }
        return NSLocalizedString("Not a Dash QR code", comment: "")
    }

    private var notAUserQRMessage: String {
        NSLocalizedString("This isn't a DashPay user QR code.", comment: "DashPay Contacts: scanned QR is a payment/invitation/foreign code")
    }

    private var notAnInvitationQRMessage: String {
        NSLocalizedString("This isn't an invitation QR code.", comment: "DashPay Invitations")
    }
}
