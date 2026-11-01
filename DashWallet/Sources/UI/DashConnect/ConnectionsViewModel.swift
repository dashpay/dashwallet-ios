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

/// A connection as its sheet shows it: a row of the page.
struct ConnectionSheetItem: Identifiable, Equatable {
    enum Status: Equatable {
        case active
        /// A v2 approval whose update's outcome is not known yet.
        case confirming
        /// A two-QR login waiting for the app's second code.
        case waitingForSecondScan

        /// A connection in this status can be disconnected: its keys may
        /// still be on. A two-QR row waiting for its second code only goes
        /// back to that state.
        var offersDisconnect: Bool { self == .active || self == .confirming }
    }

    let id: String
    let name: String
    let url: String
    let status: Status
    /// The page's row, which a disconnect acts on.
    let connection: DAppConnection?
}

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published private(set) var connections: [DAppConnection] = []
    /// What the last action from the connection sheet ended in, shown on
    /// the sheet: an alert of the page cannot appear over it.
    @Published var connectionSheetMessage: ConnectionsScreenMessage?
    /// The connection whose sheet is up.
    @Published var shownConnection: ConnectionSheetItem?
    /// What that sheet shows beyond the row; `nil` while it is read, or when
    /// it could not be read (`shownDetailsFailed`).
    @Published private(set) var shownDetails: ConnectionDetails?
    @Published private(set) var shownDetailsFailed = false
    /// The lines of what the shown connection's app was given and was not;
    /// `nil` while unknown.
    var shownGrantedLines: [String]? {
        guard let item = shownConnection, let access = shownDetails?.access, let keys = access.keys else { return nil }
        return DashConnectPermissionText.granted(
            AppConnect.GrantedAccess(
                keys: keys, receivesMessages: access.receivesMessages, isSessionKeyLogin: access.isSessionKeyLogin),
            appLabel: item.name)
    }

    /// Each of the shown connection's keys with what is left of its budget,
    /// as the sheet lists them; `nil` while unknown or not read.
    var shownFundingLines: [(title: String, value: String)]? {
        guard let funding = shownDetails?.keyFunding else { return nil }
        return funding.map { key in
            let title = key.isProfileKey
                ? NSLocalizedString("DashPay profile key", comment: "DashConnect connection sheet: a key's budget line")
                : NSLocalizedString("App key", comment: "DashConnect connection sheet: a key's budget line")
            guard key.isBudgetKnown else {
                // An older record does not say this key's budget.
                guard let remaining = key.remaining else {
                    return (title, NSLocalizedString("Not known", comment: "DashConnect connection sheet"))
                }
                return (title, String(
                    format: NSLocalizedString(
                        "%@ left", comment: "DashConnect connection sheet: what is left of a key's budget; an amount with its unit"),
                    PlatformCreditsFormatter.dashString(remaining)))
            }
            guard let total = key.totalBudget else {
                return (title, NSLocalizedString(
                    "No limit", comment: "DashConnect connection sheet: a key with no spending limit"))
            }
            guard let remaining = key.remaining else {
                return (title, String(
                    format: NSLocalizedString(
                        "Maximum of %@", comment: "DashConnect connection sheet: an amount with its unit, e.g. 0.5 DASH"),
                    PlatformCreditsFormatter.dashString(total)))
            }
            return (title, String(
                format: NSLocalizedString(
                    "%1$@ left of %2$@",
                    comment: "DashConnect connection sheet: what is left of a key's budget, then the budget; amounts with units"),
                PlatformCreditsFormatter.dashString(remaining), PlatformCreditsFormatter.dashString(total)))
        }
    }

    /// Platform could not be read for what is left of the keys' budgets.
    var shownFundingFailed: Bool { shownDetails?.fundingReadFailed == true }

    /// When the shown connection was made.
    var shownConnectedAt: Date? {
        guard shownConnection != nil else { return nil }
        return shownDetails?.connectedAt
    }

    /// The sheet was opened by a row's Disconnect: it asks at once.
    private(set) var shownAsksToDisconnect = false

    var shownWithheldLines: [String] {
        shownDetails?.access?.isSessionKeyLogin == true
            ? DashConnectPermissionText.sessionKeyWithheld : DashConnectPermissionText.withheld
    }
    @Published private(set) var featureUnavailable: Bool
    @Published var pendingRequest: ConnectionRequest?
    @Published var pendingTokenPurchase: DashConnectTokenPurchaseRequest?
    @Published var isApproving = false
    @Published var isApprovingPurchase = false
    @Published var isProcessingStateTransition = false
    /// A disconnect in progress, from the tap until it has ended and the
    /// rows show its result, whether or not it signs an identity
    /// update. Its own flag, not
    /// `isProcessingStateTransition`: a `dash-st:` task clears that one when
    /// it finishes, which would lift the guard while a disconnect is still out.
    @Published private(set) var isDisconnecting = false
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

    /// A request that read while a connection's sheet was up waits here for
    /// that sheet to be gone (`connectionSheetDismissed`): SwiftUI shows one
    /// sheet at a time.
    private var sheetDismissal: CheckedContinuation<Void, Never>?
    private var sheetDismissalNumber = 0
    /// From opening a connection's sheet until it reports being gone: it
    /// may still be leaving the screen after `shownConnection` is cleared.
    private var isConnectionSheetOnScreen = false

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
            .sink { [weak self] rows in
                guard let self else { return }
                self.connections = rows.sorted(by: { $0.updatedAt > $1.updatedAt })
                self.updateShownConnection()
            }
            .store(in: &cancellables)
    }

    /// The page's rows.
    var rows: [ConnectionSheetItem] { connections.map { item(for: $0) } }

    private func item(for connection: DAppConnection) -> ConnectionSheetItem {
        let status: ConnectionSheetItem.Status
        switch connection.status {
        case .active: status = .active
        case .confirming: status = .confirming
        case .approved: status = .waitingForSecondScan
        }
        return ConnectionSheetItem(
            id: connection.id, name: connection.name, url: connection.url, status: status,
            connection: connection)
    }

    /// Opens the sheet of `item`, and reads what it shows. Not while a
    /// request reads or is on screen: its sheet comes next.
    /// With `asksToDisconnect`, the sheet asks about a disconnect as it
    /// opens: a row's Disconnect goes through the same question.
    func showConnection(_ item: ConnectionSheetItem, asksToDisconnect: Bool = false) {
        guard !isResolvingRequest, pendingRequest == nil, pendingTokenPurchase == nil else { return }
        isConnectionSheetOnScreen = true
        shownConnection = item
        shownDetails = nil
        shownDetailsFailed = false
        connectionSheetMessage = nil
        readShownDetails(item)
        shownAsksToDisconnect = asksToDisconnect
    }

    /// The sheet opened by a row's Disconnect is up: its question, asked
    /// once (`disconnectQuestion`).
    func takeDisconnectQuestion() -> Bool? {
        guard shownAsksToDisconnect else { return nil }
        shownAsksToDisconnect = false
        return disconnectQuestion()
    }

    /// What the shown sheet's disconnect question says a disconnect does,
    /// read now; `nil` when it cannot ask, and the sheet then says why.
    func disconnectQuestion() -> Bool? {
        guard let item = shownConnection, let connection = item.connection, item.status.offersDisconnect else {
            connectionSheetMessage = Self.noLongerDisconnectableMessage
            return nil
        }
        guard !isBusyWithAnotherRequest else {
            connectionSheetMessage = Self.anotherRequestMessage
            return nil
        }
        guard let revokesKeys = dataSource.disconnectRevokesKeys(id: connection.id, scope: connection.scope) else {
            // Not the active wallet's, or gone from it.
            connectionSheetMessage = Self.connectionChangedMessage
            return nil
        }
        connectionSheetMessage = nil
        return revokesKeys
    }

    /// Something that signs, or touches the records a disconnect does, is
    /// running or about to show: a disconnect waits for it.
    private var isBusyWithAnotherRequest: Bool { isBusySigning || isResolvingRequest }

    /// Something signs, or an approval is on screen. A request still
    /// resolving is not counted here: a newer scan supersedes it.
    private var isBusySigning: Bool {
        isDisconnecting || isProcessingStateTransition || isApproving || isApprovingPurchase
            || pendingRequest != nil || pendingTokenPurchase != nil
    }

    /// Whether a scan may start now; otherwise the page says why.
    func mayScan() -> Bool {
        guard isBusySigning else { return true }
        message = Self.anotherRequestMessage
        return false
    }

    private static let anotherRequestMessage = ConnectionsScreenMessage(
        kind: .error,
        text: NSLocalizedString(
            "Another DashConnect request is in progress. Try again when it finishes.", comment: "DashConnect"))

    private static let staleQuestionMessage = ConnectionsScreenMessage(
        kind: .error,
        text: NSLocalizedString(
            "What disconnecting does changed since you were asked. Check it and try again.",
            comment: "DashConnect: a disconnect confirmed with text that no longer holds"))

    private static let noLongerDisconnectableMessage = ConnectionsScreenMessage(
        kind: .error,
        text: NSLocalizedString(
            "This connection has nothing to disconnect now.",
            comment: "DashConnect: a disconnect asked for on a connection that no longer offers one"))

    private static let connectionChangedMessage = ConnectionsScreenMessage(
        kind: .error,
        text: NSLocalizedString(
            "This connection changed. Check it and try again.",
            comment: "DashConnect: a disconnect asked for on a row that is no longer the active wallet's"))

    private func readShownDetails(_ item: ConnectionSheetItem) {
        Task { [weak self] in
            guard let self else { return }
            let details = await self.dataSource.connectionDetails(id: item.id, scope: item.connection?.scope)
            // Only for the sheet it was read for: the same app, connected or
            // not as it was. A status change alone does not make it stale.
            guard let shown = self.shownConnection, !Self.readsAnew(shown, from: item) else { return }
            self.shownDetails = details
            self.shownDetailsFailed = details == nil
        }
    }

    func hideConnection() {
        shownAsksToDisconnect = false
        shownConnection = nil
        shownDetails = nil
        shownDetailsFailed = false
        connectionSheetMessage = nil
    }

    /// Whether the sheet's details have to be read again for `item` after
    /// `previous`: another app, a row that changed (its status or kind), or
    /// a connection that is no longer one.
    private static func readsAnew(_ item: ConnectionSheetItem, from previous: ConnectionSheetItem) -> Bool {
        item.id != previous.id || item.connection?.status != previous.connection?.status
            || item.connection?.loginKind != previous.connection?.loginKind
            || (item.connection == nil) != (previous.connection == nil)
    }

    /// The connection's sheet is gone from the screen.
    func connectionSheetDismissed() {
        isConnectionSheetOnScreen = false
        // A request on its way owns the screen: the page cannot show an
        // alert and its sheet at once.
        if let waiting = messageAfterSheet, !isResolvingRequest, pendingRequest == nil, pendingTokenPurchase == nil {
            message = waiting
        }
        messageAfterSheet = nil
        sheetDismissal?.resume()
        sheetDismissal = nil
    }

    /// Closes an open connection's sheet and returns once it is gone, so a
    /// request's sheet can show. A sheet that never reports going (the
    /// screen is not up) is waited for no longer than a second.
    private func closeConnectionSheet() async {
        guard isConnectionSheetOnScreen else { return }
        hideConnection()
        sheetDismissalNumber &+= 1
        let number = sheetDismissalNumber
        await withCheckedContinuation { continuation in
            sheetDismissal?.resume()
            sheetDismissal = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.sheetDismissalNumber == number else { return }
                self.connectionSheetDismissed()
            }
        }
    }

    /// Keeps an open sheet in step with the rows: its status and what it
    /// shows, or closed once it is no longer a row. Not during a disconnect
    /// from it: it closes once the disconnect has ended.
    private func updateShownConnection() {
        guard let shown = shownConnection, !isDisconnecting else { return }
        let current = rows.first { $0.id == shown.id }
        // Another wallet's row of the same app is another connection: the
        // sheet, its question and what it said were about the one before.
        if let current, let scope = current.connection?.scope, let shownScope = shown.connection?.scope,
           scope != shownScope {
            hideConnection()
            return
        }
        if let current {
            guard current != shown else { return }
            shownConnection = current
            // What the sheet reads changes with the app, its row, or whether
            // it is still connected.
            if Self.readsAnew(current, from: shown) {
                shownDetails = nil
                shownDetailsFailed = false
                readShownDetails(current)
            }
        } else {
            // What the sheet was saying goes to the page once it has gone.
            if let said = connectionSheetMessage { holdForAfterSheet(said) }
            hideConnection()
        }
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
            let refusal = ConnectionsScreenMessage(
                kind: .error,
                text: NSLocalizedString("Finish the current DashConnect request first, then try again.",
                                        comment: "DashConnect: a second request arrived during key registration")
            )
            // A disconnect runs from its connection's sheet, which the
            // page's alert cannot show over.
            if shownConnection != nil {
                connectionSheetMessage = refusal
            } else {
                message = refusal
            }
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
                let parsed = try await dataSource.parseQR(content)
                guard generation == requestGeneration else { return }
                switch parsed {
                case let .login(request):
                    // Resolve first, publish second, and publish the pair
                    // together. Between these two lines a newer request may
                    // have arrived; if it has, this one is stale and must
                    // publish nothing — the sheet and the key it authorizes
                    // have to describe the same request.
                    let connectionRequest = await dataSource.makeConnectionRequest(from: request)
                    guard generation == requestGeneration else { return }
                    // The approval cannot show over a connection's sheet, up
                    // now: it closes first.
                    await closeConnectionSheet()
                    guard generation == requestGeneration else { return }
                    pendingLoginRequest = request
                    pendingRequestArrivedByLink = byLink
                    pendingFailureStatus = nil
                    pendingRequest = connectionRequest
                case let .stateTransition(request):
                    guard generation == requestGeneration else { return }
                    await closeConnectionSheet()
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
                let failure = ConnectionsScreenMessage(
                    kind: .error,
                    text: String(
                        format: NSLocalizedString("Could not complete the DashConnect request: %@", comment: "DashConnect"),
                        error.localizedDescription
                    )
                )
                // A request that did not read leaves an open connection's
                // sheet up, and says so on it.
                if shownConnection != nil {
                    connectionSheetMessage = failure
                } else {
                    message = failure
                }
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

    /// A disconnect confirmed on the shown sheet with what it said
    /// (`askedRevokesKeys`). It runs only if the sheet still offers one and
    /// it would still do what was said; otherwise the sheet shows what holds
    /// now, and why nothing ran.
    func disconnectShown(askedRevokesKeys: Bool) {
        guard let item = shownConnection, let connection = item.connection, item.status.offersDisconnect else {
            connectionSheetMessage = Self.noLongerDisconnectableMessage
            return
        }
        let revokesKeys = dataSource.disconnectRevokesKeys(id: connection.id, scope: connection.scope)
        guard revokesKeys == askedRevokesKeys else {
            connectionSheetMessage = revokesKeys == nil
                ? Self.connectionChangedMessage
                : Self.staleQuestionMessage
            return
        }
        disconnect(connection)
    }

    func disconnect(_ connection: DAppConnection) {
        // Disconnecting a one-QR connection signs an identity update, which
        // takes seconds. It must not overlap anything else that signs one or
        // touches the same records: a second tap, an approval on screen or in
        // flight, a request still resolving, a `dash-st:` in progress.
        guard !isBusyWithAnotherRequest else {
            // The user confirmed it; say why nothing ran.
            show(Self.anotherRequestMessage, from: connection)
            return
        }
        isDisconnecting = true
        Task { [weak self] in
            guard let self else { return }
            self.connectionSheetMessage = nil
            let result: DashConnectDisconnectResult
            do {
                result = try await self.dataSource.disconnect(id: connection.id, scope: connection.scope)
            } catch {
                self.isDisconnecting = false
                // It may have turned some keys off before it failed: what
                // the sheet shows is read again.
                self.updateShownConnection()
                if let shown = self.shownConnection, shown.id == connection.id {
                    self.shownDetails = nil
                    self.shownDetailsFailed = false
                    self.readShownDetails(shown)
                }
                self.show(ConnectionsScreenMessage(
                    kind: .error,
                    text: String(
                        format: NSLocalizedString("Could not disconnect: %@", comment: "DashConnect"),
                        error.localizedDescription)),
                    from: connection)
                return
            }
            self.isDisconnecting = false
            self.updateShownConnection()
            // What the disconnect did with the DashPay profile keys no
            // connection accounts for; said, since they may have been
            // another app's.
            var said: [String] = []
            if result.profileKeysUnchecked {
                said.append(NSLocalizedString(
                    "Disconnected. DashPay profile keys not linked to any connection could not be checked, so none of them was turned off.",
                    comment: "DashConnect: after a disconnect whose unattributed DashPay profile keys could not be told apart"))
            } else if result.profileKeysTurnedOff > 0 {
                said.append(String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Disconnected. DashPay profile keys not linked to any connection were turned off as well: %d.",
                        comment: "DashConnect: after a disconnect, how many unattributed DashPay profile keys were also turned off"),
                    result.profileKeysTurnedOff))
            }
            if !said.isEmpty {
                self.show(
                    ConnectionsScreenMessage(kind: .success, text: said.joined(separator: "\n\n")),
                    from: connection)
            }
        }
    }

    /// On the connection's sheet while it is up, on the page otherwise;
    /// once a sheet that is going away has gone, since the page cannot show
    /// it over that sheet.
    private func show(_ message: ConnectionsScreenMessage, from connection: DAppConnection) {
        if shownConnection?.id == connection.id {
            connectionSheetMessage = message
        } else if isConnectionSheetOnScreen {
            holdForAfterSheet(message)
        } else {
            self.message = message
        }
    }

    /// A page message waiting for the connection's sheet to go.
    private var messageAfterSheet: ConnectionsScreenMessage?

    /// Waits with `message` for the sheet to go, after any already waiting.
    private func holdForAfterSheet(_ message: ConnectionsScreenMessage) {
        guard let waiting = messageAfterSheet else {
            messageAfterSheet = message
            return
        }
        messageAfterSheet = ConnectionsScreenMessage(
            kind: waiting.kind == .error || message.kind == .error ? .error : .success,
            text: waiting.text + "\n\n" + message.text)
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
