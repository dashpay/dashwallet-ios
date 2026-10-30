//
//  ConnectionsViewModel.swift
//  DashWallet
//
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

struct ConnectionsScreenMessage: Identifiable, Equatable {
    enum Kind: String {
        case error
        case success
    }

    let kind: Kind
    let text: String

    var id: String {
        "\(kind.rawValue):\(text)"
    }

    var title: String {
        switch kind {
        case .error:
            return NSLocalizedString("Error", comment: "")
        case .success:
            return NSLocalizedString("Success", comment: "DashConnect")
        }
    }
}

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published private(set) var connections: [DAppConnection] = []
    @Published private(set) var featureUnavailable: Bool
    @Published var pendingRequest: ConnectionRequest?
    @Published var pendingTokenPurchase: DashConnectTokenPurchaseRequest?
    @Published var isApproving = false
    @Published var isApprovingPurchase = false
    @Published var isProcessingStateTransition = false
    /// A disconnect or a shared profile revoke or keep in progress. Its own flag, not
    /// `isProcessingStateTransition`: a `dash-st:` task clears that one when
    /// it finishes, which would lift the guard while a disconnect is still out.
    @Published private(set) var isDisconnecting = false
    /// The DashPay profile keys on the active identity that no connection
    /// accounts for and the user did not keep: `nil` when there are none or
    /// no identity is active, a `nil` `keyCount` when they could not be told.
    @Published private(set) var sharedProfileAccess: SharedProfileAccess?
    /// Each read of `sharedProfileAccess` takes the next number; only the
    /// latest one started is shown, so a slow older read cannot overwrite it.
    private var sharedProfileAccessGeneration = 0
    /// Whether the latest shown read found the active identity with no such
    /// key, as opposed to no readable wallet or identity.
    private var sharedProfileAccessFoundNone = false
    @Published var message: ConnectionsScreenMessage?
    /// Failure of the last approve attempt, rendered **inside** the approve sheet.
    /// A screen-level `.alert` cannot appear over a presented sheet, so routing this
    /// through `message` would leave the user with no feedback at all.
    @Published var approveError: String?
    /// Failure of the last token-purchase approve attempt, rendered inside
    /// the purchase sheet for the same reason as `approveError`.
    @Published var purchaseApproveError: String?

    private let dataSource: any DashConnectDataSource
    private var pendingLoginRequest: DashKeyRequest?
    /// Opens an App Connect request's return URL.
    private let openURL: @MainActor (URL) -> Void
    /// The status the pending App Connect request's callback reports if the
    /// user closes the sheet now: set when an approval failed.
    private var pendingFailureStatus: AppConnect.CallbackStatus?
    /// Whether the pending request came as a link opened on this phone. Only
    /// then is its callback opened: a QR code scanned off another screen is
    /// answered on that screen, and opening the callback here would start an
    /// unrelated session of the app in this phone's browser.
    private var pendingRequestArrivedByLink = false
    private var cancellables = Set<AnyCancellable>()

    /// Serializes inbound requests.
    ///
    /// A QR scan arrives one at a time, but a deep link does not: any installed
    /// app can open `dash-key:` / `dash-st:` whenever it likes, and each one used
    /// to start its own untracked task. `pendingLoginRequest` was published
    /// BEFORE the Platform metadata lookup that builds the sheet's contents, so
    /// a second request landing inside that await replaced it while the first
    /// went on to publish the sheet — the user then approved what B asked for
    /// while reading what A said, and the login credential was encrypted to B's
    /// ephemeral key. Every request now takes a generation, and only the newest
    /// one is allowed to publish anything.
    private var requestGeneration = 0

    /// Whether a request is mid-flight. A newer request may supersede one that
    /// is still resolving, but nothing may interrupt an approval or a key
    /// registration, which are already committing to the network.
    private var isResolvingRequest = false

    init(
        dataSource: (any DashConnectDataSource)? = nil,
        featureUnavailable: Bool? = nil,
        openURL: (@MainActor (URL) -> Void)? = nil
    ) {
        let computedFeatureUnavailable = featureUnavailable ?? !WalletEnvironment.isTestNetwork
        self.featureUnavailable = computedFeatureUnavailable
        self.dataSource = dataSource ?? Self.defaultDataSource(featureUnavailable: computedFeatureUnavailable)
        self.openURL = openURL ?? { UIApplication.shared.open($0) }

        self.dataSource.connections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.connections = $0.sorted(by: { $0.updatedAt > $1.updatedAt })
            }
            .store(in: &cancellables)
        // The rows change when an app is approved, confirmed or removed,
        // which is when the shared profile keys can change too.
        // The screen reads them when it appears; the current value the
        // publisher replays is skipped.
        self.dataSource.connections
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSharedProfileAccess() }
            .store(in: &cancellables)
    }

    /// Reads the shared profile keys again from the wallet's store.
    func refreshSharedProfileAccess() {
        guard !featureUnavailable else { return }
        Task { [weak self] in await self?.readSharedProfileAccess() }
    }

    /// Reads the shared profile keys and shows them, unless a later read
    /// started meanwhile. Returns what this read found.
    @discardableResult
    private func readSharedProfileAccess() async -> SharedProfileAccess? {
        sharedProfileAccessGeneration += 1
        let generation = sharedProfileAccessGeneration
        let read = await dataSource.sharedProfileAccess()
        let access = read?.keyCount == 0 ? nil : read
        if generation == sharedProfileAccessGeneration {
            sharedProfileAccess = access
            sharedProfileAccessFoundNone = read?.keyCount == 0
        }
        return access
    }

    func onQRScanned(_ content: String) {
        receive(content, byLink: false)
    }

    private func receive(_ content: String, byLink: Bool) {
        guard !featureUnavailable else { return }

        // A request the user is already looking at owns the screen until they
        // answer it. Both sheets count: `pendingRequest` presents the connection
        // approval (and stays set while an approval is in flight), and
        // `pendingTokenPurchase` presents a purchase waiting to be authorized.
        // Refusing the newcomer beats replacing a request mid-read — and beats
        // what replacing used to cost, since resolving the newcomer starts by
        // clearing the sheet, so an unparseable link could dismiss a legitimate
        // approval on its way to failing.
        //
        // The refusal has to appear where the user is looking: the sheet
        // covers the screen, and a screen-level `.alert` cannot show over it.
        guard pendingRequest == nil, pendingTokenPurchase == nil else {
            let refusal = NSLocalizedString("Another DashConnect request arrived. Finish this one first, then try again.",
                                            comment: "DashConnect: a second request arrived while one was on screen")
            // Onto the sheet that is actually up: the purchase sheet reads
            // `purchaseApproveError` alone, so a refusal parked in
            // `approveError` while a purchase is on screen is invisible — the
            // request would look silently dropped.
            if pendingTokenPurchase != nil {
                purchaseApproveError = refusal
            } else {
                approveError = refusal
            }
            return
        }

        guard !isProcessingStateTransition, !isDisconnecting else {
            message = ConnectionsScreenMessage(
                kind: .error,
                text: NSLocalizedString("Finish the current DashConnect request first, then try again.",
                                        comment: "DashConnect: a second request arrived during key registration")
            )
            return
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        isResolvingRequest = true

        Task {
            defer { if generation == requestGeneration { isResolvingRequest = false } }
            do {
                // Nothing to clear: the guard above refuses a request while one
                // is on screen, and bumping the generation stops any request
                // still resolving from publishing one.
                switch try await dataSource.parseQR(content) {
                case let .login(request):
                    // Resolve first, publish second, and publish the pair
                    // together. Between these two lines a newer request may
                    // have arrived; if it has, this one is stale and must
                    // publish nothing — the sheet and the key it authorizes
                    // have to describe the same request.
                    let connectionRequest = await dataSource.makeConnectionRequest(from: request)
                    guard generation == requestGeneration else { return }
                    pendingLoginRequest = request
                    pendingRequestArrivedByLink = byLink
                    pendingFailureStatus = nil
                    pendingRequest = connectionRequest
                case let .stateTransition(request):
                    guard generation == requestGeneration else { return }
                    isProcessingStateTransition = true
                    defer { isProcessingStateTransition = false }

                    switch try await dataSource.handleStateTransition(request) {
                    case .keyRegistrationCompleted:
                        message = ConnectionsScreenMessage(
                            kind: .success,
                            text: NSLocalizedString("DashConnect key registration completed.", comment: "DashConnect")
                        )
                    case let .tokenPurchaseApprovalRequired(purchase):
                        pendingTokenPurchase = purchase
                    }
                }
            } catch {
                guard generation == requestGeneration else { return }
                message = ConnectionsScreenMessage(
                    kind: .error,
                    text: String(
                        format: NSLocalizedString("Could not complete the DashConnect request: %@", comment: "DashConnect"),
                        error.localizedDescription
                    )
                )
            }
        }
    }

    /// A `dash-key:` / `dash-st:` link opened by an app running on this phone.
    /// It carries exactly what the QR code encodes, so it takes the same path,
    /// except that only a link's callback is opened.
    func onURIReceived(_ uri: String) {
        receive(uri, byLink: true)
    }

    func approvePendingRequest() {
        // `isResolvingRequest` guards the window where a newer request has been
        // accepted but has not published yet: approving during it would
        // authorize the request on screen moments before it is replaced.
        // An unresolved login has nothing to approve; the sheet offers
        // `retryPendingRequest` for it instead.
        guard let consent = pendingRequest, consent.login.isApprovable,
              let pendingLoginRequest, !isApproving, !isResolvingRequest else { return }

        isApproving = true
        approveError = nil

        Task {
            defer { isApproving = false }

            do {
                _ = try await dataSource.approveLogin(pendingLoginRequest, consent: consent)
                openCallback(of: pendingLoginRequest, status: .ok)
                self.pendingRequest = nil
                self.pendingLoginRequest = nil
                self.approveError = nil
            } catch DashConnectPlatformError.approvalOutOfDate {
                // Another identity, wallet or network became active, or the
                // network now answers with the other login: what the sheet
                // showed is not what would run. Nothing was signed. The sheet is rebuilt from
                // the same request as it stands now, for a new decision.
                // An earlier failure was on the sheet this one replaces.
                self.pendingFailureStatus = nil
                self.pendingRequest = await dataSource.makeConnectionRequest(from: pendingLoginRequest)
                self.approveError = DashConnectPlatformError.approvalOutOfDate.localizedDescription
            } catch DashConnectPlatformError.loginUnresolved {
                // The wallet could not check which login this network gets.
                // Nothing was signed. The sheet is rebuilt: when it still
                // cannot tell, it says so itself and offers "Try again"
                // instead of Approve; when it can again, the note says why
                // the approval did not go through.
                let rebuilt = await dataSource.makeConnectionRequest(from: pendingLoginRequest)
                self.pendingRequest = rebuilt
                self.approveError = rebuilt.login == .unresolved
                    ? nil : DashConnectPlatformError.loginUnresolved.localizedDescription
            } catch let refusal as AppConnect.Refusal {
                // A refusal fails the same way on every try: the sheet shows
                // it as the request's answer, and offers no Approve.
                self.pendingFailureStatus = refusal.status
                self.pendingRequest?.login = .refused(refusal)
                self.approveError = nil
            } catch {
                // Keep the sheet up so the user can retry without rescanning the QR.
                // A cancelled PIN prompt is the user declining, not a failure,
                // whatever an earlier attempt ended in.
                self.pendingFailureStatus = error as? DashConnectPlatformError == .authorizationCancelled
                    ? nil
                    : .failed
                self.approveError = String(
                    format: NSLocalizedString("Could not complete the DashConnect request: %@", comment: "DashConnect"),
                    error.localizedDescription
                )
            }
        }
    }

    /// Builds the pending request again, for a sheet that could not tell
    /// which login it would run. Approves nothing.
    func retryPendingRequest() {
        guard pendingRequest != nil, let pendingLoginRequest, !isApproving, !isResolvingRequest else { return }

        isApproving = true
        approveError = nil

        Task {
            defer { isApproving = false }
            self.pendingFailureStatus = nil
            self.pendingRequest = await dataSource.makeConnectionRequest(from: pendingLoginRequest)
        }
    }

    func denyPendingRequest() {
        guard !isApproving else { return }
        // A refused request never showed where it would return, so its
        // callback is not opened.
        if let pendingLoginRequest, pendingRequest?.login.isApprovable == true {
            openCallback(of: pendingLoginRequest, status: pendingFailureStatus ?? .declined)
        }
        pendingRequest = nil
        pendingLoginRequest = nil
        pendingFailureStatus = nil
        approveError = nil
    }

    /// Returns to the app that sent an App Connect request, with how it
    /// ended (`ac=<status>`). Only the callback the sheet showed ("returns
    /// to <host>") is opened, and only once the user has answered it. A
    /// known app's request that returns elsewhere is refused before the
    /// sheet (`AppConnect.callbackRefusal`); for an app the wallet does not
    /// know, the user's answer to a sheet naming the host, with its
    /// warning, stands in for the profile's "ask".
    /// The app treats it as a nudge to look for the response, never as
    /// proof of anything.
    private func openCallback(of request: DashKeyRequest, status: AppConnect.CallbackStatus) {
        guard pendingRequestArrivedByLink,
              let callback = request.appConnect?.callback,
              let url = AppConnect.callbackURL(callback, status: status) else { return }
        openURL(url)
    }

    func approvePendingTokenPurchase() {
        guard let purchase = pendingTokenPurchase, !isApprovingPurchase else { return }

        isApprovingPurchase = true
        purchaseApproveError = nil

        Task {
            defer { isApprovingPurchase = false }

            do {
                try await dataSource.approveTokenPurchase(purchase)
                self.pendingTokenPurchase = nil
                self.purchaseApproveError = nil
                message = ConnectionsScreenMessage(
                    kind: .success,
                    text: NSLocalizedString("Token purchase completed.", comment: "DashConnect")
                )
            } catch DashConnectTokenPurchaseFailure.outcomeUnknown(let underlying) {
                // The transition was signed and submitted, and only the wait
                // for its outcome failed — Platform may well have accepted it.
                // Approving again would build a second purchase on the next
                // nonce and could buy the tokens twice, so the sheet closes
                // rather than offering a retry, and the user is told what to
                // check before starting over.
                self.pendingTokenPurchase = nil
                self.purchaseApproveError = nil
                message = ConnectionsScreenMessage(
                    kind: .error,
                    text: String(
                        format: NSLocalizedString(
                            "The purchase was submitted but its result is unknown: %@. Check this identity's tokens and credit balance before buying again — approving a second time would pay twice.",
                            comment: "DashConnect token purchase"),
                        underlying.localizedDescription
                    )
                )
            } catch {
                // Refused before anything was signed or sent (a cancelled
                // authentication, a wrong identity, "the identity has no
                // CRITICAL key"): nothing was charged, so keep the sheet up
                // and let the user retry without rescanning the QR.
                self.purchaseApproveError = String(
                    format: NSLocalizedString("Could not complete the DashConnect request: %@", comment: "DashConnect"),
                    error.localizedDescription
                )
            }
        }
    }

    func denyPendingTokenPurchase() {
        guard !isApprovingPurchase else { return }
        pendingTokenPurchase = nil
        purchaseApproveError = nil
    }

    func disconnect(_ connection: DAppConnection) {
        // Disconnecting a one-QR connection signs an identity update, which
        // takes seconds. It must not overlap anything else that signs one or
        // touches the same records: a second tap, an approval on screen or in
        // flight, a request still resolving, a `dash-st:` in progress.
        guard canSignIdentityUpdate else { return }
        isDisconnecting = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isDisconnecting = false }
            do {
                try await self.dataSource.disconnect(id: connection.id, scope: connection.scope)
            } catch {
                self.message = ConnectionsScreenMessage(
                    kind: .error,
                    text: String(
                        format: NSLocalizedString("Could not disconnect: %@", comment: "DashConnect"),
                        error.localizedDescription))
                return
            }
            let access = await self.readSharedProfileAccess()
            // Only a one-QR login gives an app a DashPay profile key, so only
            // its disconnect can leave one behind.
            guard connection.loginKind == .oneQR, let access else { return }
            if let keyCount = access.keyCount {
                self.message = ConnectionsScreenMessage(
                    kind: .success,
                    text: String(
                        format: NSLocalizedString(
                            "Disconnected. Keys not linked to any connection can still update your DashPay profile: %d. They may belong to this app or another one. You can revoke them under Shared profile access.",
                            comment: "DashConnect"),
                        keyCount))
            } else {
                self.message = ConnectionsScreenMessage(
                    kind: .success,
                    text: NSLocalizedString(
                        "Disconnected. This wallet could not check whether keys not linked to any connection can still update your DashPay profile.",
                        comment: "DashConnect"))
            }
        }
    }

    /// Whether the screen shows the shared profile keys.
    var showsSharedProfileAccess: Bool { !featureUnavailable && sharedProfileAccess != nil }

    /// Whether they can be revoked or kept from here: only for an identity
    /// that was read, with a count that was.
    var canActOnSharedProfileAccess: Bool {
        sharedProfileAccess?.identityId != nil && sharedProfileAccess?.keyCount != nil
    }

    /// Whether nothing else that signs an identity update or touches the same
    /// records is going on: a disconnect or revoke, an approval on screen or
    /// in flight, a request still resolving, a `dash-st:` in progress.
    private var canSignIdentityUpdate: Bool {
        !isDisconnecting && !isProcessingStateTransition && !isApproving && !isApprovingPurchase
            && !isResolvingRequest && pendingRequest == nil && pendingTokenPurchase == nil
    }

    /// Disables every DashPay profile key no connection accounts for and the
    /// user did not keep, for every app that holds one. Same guards as `disconnect`: it signs an
    /// identity update.
    func revokeSharedProfileAccess() {
        guard canSignIdentityUpdate else {
            // The user confirmed a destructive action; say why nothing ran.
            message = Self.busyMessage
            return
        }
        guard let access = sharedProfileAccess else {
            // A read finished while the confirmation was up. Only one that
            // read the identity and found none says so.
            message = sharedProfileAccessFoundNone
                ? ConnectionsScreenMessage(
                    kind: .success,
                    text: NSLocalizedString("No DashPay profile key needed revoking.", comment: "DashConnect"))
                : Self.sharedProfileAccessUncheckedMessage
            return
        }
        guard canActOnSharedProfileAccess else {
            // A read finished while the confirmation was up and could not
            // read the identity or the count: unknown, not none.
            message = Self.sharedProfileAccessUncheckedMessage
            return
        }
        isDisconnecting = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isDisconnecting = false }
            do {
                let disabled = try await self.dataSource.revokeSharedProfileAccess(access)
                self.message = ConnectionsScreenMessage(
                    kind: .success,
                    text: disabled > 0
                        ? String(
                            format: NSLocalizedString("DashPay profile keys revoked: %d.", comment: "DashConnect"),
                            disabled)
                        : NSLocalizedString("No DashPay profile key needed revoking.", comment: "DashConnect"))
            } catch {
                self.message = ConnectionsScreenMessage(
                    kind: .error,
                    text: String(
                        format: NSLocalizedString("Could not revoke shared profile access: %@", comment: "DashConnect"),
                        error.localizedDescription))
            }
            await self.readSharedProfileAccess()
        }
    }

    /// Stops counting the shared profile keys shown, on this device, after
    /// the PIN prompt: the user recognizes them. A key that is not among them shows the row
    /// again. Nothing changes on Platform.
    func keepSharedProfileAccess(_ shown: SharedProfileAccess) {
        guard canSignIdentityUpdate else {
            message = Self.busyMessage
            return
        }
        // Only the keys the user was shown: a read that finished while the
        // confirmation was up may count others, or none.
        guard let access = sharedProfileAccess else {
            if !sharedProfileAccessFoundNone { message = Self.sharedProfileAccessUncheckedMessage }
            return
        }
        guard canActOnSharedProfileAccess else {
            message = Self.sharedProfileAccessUncheckedMessage
            return
        }
        guard access == shown else {
            message = ConnectionsScreenMessage(
                kind: .error,
                text: NSLocalizedString("The keys changed. Check them and try again.", comment: "DashConnect"))
            return
        }
        // Shares the revoke's busy flag: a revoke confirmed meanwhile would
        // otherwise run on the access this keep is taking off the count.
        isDisconnecting = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isDisconnecting = false }
            do {
                try await self.dataSource.keepSharedProfileAccess(access)
            } catch {
                self.message = ConnectionsScreenMessage(
                    kind: .error,
                    text: String(
                        format: NSLocalizedString("Could not keep these keys: %@", comment: "DashConnect"),
                        error.localizedDescription))
            }
            await self.readSharedProfileAccess()
        }
    }

    private static var busyMessage: ConnectionsScreenMessage {
        ConnectionsScreenMessage(
            kind: .error,
            text: NSLocalizedString(
                "Another DashConnect request is in progress. Try again when it finishes.", comment: "DashConnect"))
    }

    private static var sharedProfileAccessUncheckedMessage: ConnectionsScreenMessage {
        ConnectionsScreenMessage(
            kind: .error,
            text: NSLocalizedString(
                "DashPay profile access could not be checked. Open Connections again and retry.",
                comment: "DashConnect"))
    }

    func removeConnection(_ connection: DAppConnection) {
        Task {
            await dataSource.remove(id: connection.id, scope: connection.scope)
        }
    }

    private static func defaultDataSource(featureUnavailable: Bool) -> any DashConnectDataSource {
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if isPreview || featureUnavailable {
            return MockDashConnectDataSource()
        }

        assert(
            WalletEnvironment.isTestNetwork,
            "DashConnect real data source must only run on testnet or devnet."
        )
        return PlatformDashConnectDataSource()
    }
}
