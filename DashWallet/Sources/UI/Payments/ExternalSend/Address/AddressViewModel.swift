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
import UIKit

/// The one place the Address screen reads the clipboard. Faked in tests.
protocol ClipboardReading {
    func readString() -> String?
}

/// Reads `UIPasteboard.general`. Only `AddressViewModel.showClipboard()` calls it, inside the tap, so the
/// system paste notice never appears before the user asks.
struct LiveClipboard: ClipboardReading {
    func readString() -> String? {
        UIPasteboard.general.string
    }
}

/// SCR-02 Address: enter, paste on tap or scan a destination. Everything invalid or unknown stops here;
/// a valid destination (plus the recipient, for an Identity ID) goes to `onResolved`.
@MainActor
final class AddressViewModel: ObservableObject {
    enum State: Equatable {
        case initial
        /// A destination was found on the clipboard after the Show clipboard tap.
        case clipboard(Destination)
        case clipboardNone
        case entered
        case invalid(DestinationParseError)
        case checking
        case notFound
        case checkFailed
    }

    @Published private(set) var state: State = .initial
    @Published private(set) var text = ""
    private var stateBeforeChecking: State = .initial
    /// The Identity link whose ID is in the field: Continue and Retry check it with the link's amount. Any edit of
    /// the field drops it.
    private var identityLink: Destination?

    /// The destination (and, for an Identity ID, the recipient found on Platform) the flow continues with.
    var onResolved: ((Destination, IdentityRecipient?) -> Void)?

    private let network: WalletEnvironment.NetworkKind
    private let identityLookup: IdentityLooking
    private let pasteboard: ClipboardReading

    init(network: WalletEnvironment.NetworkKind, identityLookup: IdentityLooking,
         pasteboard: ClipboardReading = LiveClipboard()) {
        self.network = network
        self.identityLookup = identityLookup
        self.pasteboard = pasteboard
    }

    var canContinue: Bool { state == .entered }
    var isFieldReadOnly: Bool { state == .checking }

    #if DEBUG
    /// Lets a SwiftUI preview show a state without driving the lookup or the clipboard.
    func setPreviewState(_ newState: State) {
        state = newState
    }
    #endif

    // MARK: - Field

    func setText(_ newText: String) {
        text = newText
        identityLink = nil
        state = newText.isEmpty ? .initial : .entered
    }

    func clear() {
        setText("")
    }

    // MARK: - Clipboard

    func showClipboard() {
        let found = pasteboard.readString().flatMap { DestinationParser.find(in: $0, network: network) }
        state = found.map { .clipboard($0) } ?? .clipboardNone
    }

    /// A payment-request link has no address to put in the field, so it goes on at once.
    func fillFromClipboard() {
        guard case .clipboard(let found) = state else { return }
        // A link's amount, label, message and request URL live outside its address text, so a link is handed
        // on whole rather than reduced to the address in the field.
        let isLink = found.type == .paymentRequest || found.amountDuffs != nil || found.label != nil
            || found.message != nil || found.paymentRequestURL != nil
        if isLink, found.type == .identityID {
            // An Identity is checked on Continue, as a typed one is.
            setText(found.text)
            identityLink = found
        } else if isLink {
            onResolved?(found, nil)
        } else {
            setText(found.text)
        }
    }

    // MARK: - Continue

    func continueTapped() async {
        guard canContinue else { return }
        await resolveField()
    }

    func retry() async {
        guard state == .checkFailed else { return }
        await resolveField()
    }

    /// The flow is fetching a payment request for what was entered or scanned.
    func beginChecking() {
        stateBeforeChecking = state
        state = .checking
    }

    /// The fetch is over: a filled field can continue again; an empty one (a scanned or clipboard link) returns to
    /// the state it was in, so Continue never goes on for an empty field.
    func endChecking() {
        guard state == .checking else { return }
        state = text.isEmpty ? stateBeforeChecking : .entered
    }

    /// For a scanned code, after the scanner closed. False when the code is not valid here; an Identity ID is
    /// accepted and checked on this screen.
    func handleScanned(_ scanned: String) async -> Bool {
        guard case .success(let destination) = DestinationParser.parse(scanned, network: network) else { return false }
        await handleScanned(destination)
        return true
    }

    /// For a destination a scan or a link already parsed. An Identity ID is put in the field and checked here, with
    /// the link's amount kept.
    func handleScanned(_ destination: Destination) async {
        if destination.type == .identityID {
            setText(destination.text)
            identityLink = destination
        }
        await proceed(with: destination)
    }

    private func resolveField() async {
        if let identityLink {
            await proceed(with: identityLink)
        } else {
            await resolve(text)
        }
    }

    private func resolve(_ input: String) async {
        switch DestinationParser.parse(input, network: network) {
        case .failure(let error):
            state = .invalid(error)
        case .success(let destination):
            await proceed(with: destination)
        }
    }

    private func proceed(with destination: Destination) async {
        guard destination.type == .identityID else {
            onResolved?(destination, nil)
            return
        }
        state = .checking
        switch await identityLookup.lookup(id: destination.text, network: network) {
        case .found(let recipient):
            state = .entered
            onResolved?(destination, recipient)
        case .notFound:
            state = .notFound
        case .couldNotCheck:
            state = .checkFailed
        }
    }
}
