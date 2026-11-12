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
        /// A disconnect that ended with something to tell: neither a
        /// failure nor a plain success.
        case notice
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
        case .notice:
            return NSLocalizedString("Disconnected", comment: "DashConnect")
        }
    }
}

/// The tabs of the Connections page.
enum ConnectionsTab: CaseIterable {
    case active
    case disconnected
}

/// A connection as its sheet shows it: a row of the page, or an app
/// disconnected earlier.
struct ConnectionSheetItem: Identifiable, Equatable {
    let id: String
    let name: String
    let url: String
    let status: ConnectionStatus
    /// The page's row, which a disconnect acts on; `nil` for a disconnected app.
    let connection: DAppConnection?
    /// What was recorded of a disconnected app; `nil` for a row.
    let entry: DisconnectedConnection?
    /// The wallet, network and endpoint the item was published for.
    let scope: String?

    var disconnectedAt: Date? { entry?.disconnectedAt }
}

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published private(set) var connections: [DAppConnection] = []
    /// The rows were delivered once: until then nothing is known to be
    /// connected or not.
    @Published private(set) var hasReadRows = false
    @Published var selectedTab: ConnectionsTab = .active
    /// The apps disconnected on this wallet.
    @Published private(set) var history: [DisconnectedConnection] = []
    /// The wallet, network and endpoint the rows and the history were
    /// published for.
    private var listedScope: String?
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
        guard let item = shownConnection, let access = shownDetails?.access else { return nil }
        return DashConnectPermissionText.granted(access.granted, appLabel: item.name)
    }

    /// Each of the shown connection's keys with what is left of its budget,
    /// as the sheet lists them; `nil` while unknown or not read.
    var shownFundingLines: [(title: String, value: String)]? {
        guard let funding = shownDetails?.keyFunding else { return nil }
        return funding.map { key in
            let title = key.isProfileKey
                ? NSLocalizedString("DashPay profile key", comment: "DashConnect connection sheet: a key's budget line")
                : NSLocalizedString("App key", comment: "DashConnect connection sheet: a key's budget line")
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
        guard let item = shownConnection else { return nil }
        if let entry = item.entry { return entry.connectedAt }
        return shownDetails?.connectedAt
    }

    /// Counts the reads of the shown sheet's details, and its closing: only
    /// the latest read is shown.
    private var detailsReadNumber = 0

    /// The sheet was opened by a row's Disconnect: it asks at once.
    private(set) var shownAsksToDisconnect = false

    var shownWithheldLines: [String] { DashConnectPermissionText.withheld }
    @Published private(set) var featureUnavailable: Bool
    @Published var pendingRequest: ConnectionRequest?
    @Published var pendingTokenPurchase: DashConnectTokenPurchaseRequest?
    @Published var isApproving = false
    @Published var isApprovingPurchase = false
    @Published var isProcessingStateTransition = false
    /// A disconnect in progress, from the tap until it has ended and the
    /// local history shows its result, whether or not it signs an identity
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
    /// is still resolving, but nothing may interrupt an approval, which is
    /// already committing to the network.
    private var isResolvingRequest = false

    /// A request that read while a connection's sheet was up waits here for
    /// that sheet to be gone (`connectionSheetDismissed`): SwiftUI shows one
    /// sheet at a time.
    private var sheetDismissal: CheckedContinuation<Void, Never>?
    /// Moves on with every sheet opened and every dismissal reported, so a
    /// fallback timeout of an earlier dismissal does nothing.
    private var sheetDismissalNumber = 0
    /// From opening a connection's sheet until it reports being gone: it
    /// may still be leaving the screen after `shownConnection` is cleared.
    private(set) var isConnectionSheetOnScreen = false

    init(
        dataSource: (any DashConnectDataSource)? = nil,
        featureUnavailable: Bool? = nil,
        openURL: (@MainActor (URL) -> Void)? = nil
    ) {
        let computedFeatureUnavailable = featureUnavailable ?? !WalletEnvironment.isTestNetwork
        self.featureUnavailable = computedFeatureUnavailable
        self.dataSource = dataSource ?? Self.defaultDataSource(featureUnavailable: computedFeatureUnavailable)
        self.openURL = openURL ?? { UIApplication.shared.open($0) }

        // The rows and the history come in one value, under the wallet they
        // are of: a sheet of another wallet's app closes on its own.
        self.dataSource.listing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] listing in
                guard let self else { return }
                self.listedScope = listing.scope
                self.connections = listing.rows.sorted(by: { $0.updatedAt > $1.updatedAt })
                self.history = listing.disconnected
                self.hasReadRows = true
                self.updateShownConnection()
            }
            .store(in: &cancellables)
    }

    /// The rows of `tab`. A disconnected app is listed while it is not a row.
    func rows(for tab: ConnectionsTab) -> [ConnectionSheetItem] {
        switch tab {
        case .active:
            return connections.map { item(for: $0) }
        case .disconnected:
            return history.map(item(for:))
        }
    }

    /// Whether the page shows its tabs: once anything was connected.
    var hasConnectionsOrHistory: Bool {
        !connections.isEmpty || !history.isEmpty
    }

    private func item(for connection: DAppConnection) -> ConnectionSheetItem {
        ConnectionSheetItem(
            id: connection.id, name: connection.name, url: connection.url, status: connection.status,
            connection: connection, entry: nil, scope: connection.scope)
    }

    private func item(for entry: DisconnectedConnection) -> ConnectionSheetItem {
        ConnectionSheetItem(
            id: entry.id, name: entry.name, url: entry.url, status: .disconnected,
            connection: nil, entry: entry, scope: listedScope)
    }

    /// Opens the sheet of `item`, and reads what it shows. Not while a
    /// request reads or is on screen: its sheet comes next.
    /// With `asksToDisconnect`, the sheet asks about a disconnect as it
    /// opens: a row's Disconnect goes through the same question.
    func showConnection(_ item: ConnectionSheetItem, asksToDisconnect: Bool = false) {
        guard !isResolvingRequest, pendingRequest == nil, pendingTokenPurchase == nil else { return }
        isConnectionSheetOnScreen = true
        sheetDismissalNumber &+= 1
        shownConnection = item
        shownDetails = nil
        shownDetailsFailed = false
        connectionSheetMessage = nil
        readShownDetails(item)
        shownAsksToDisconnect = asksToDisconnect
    }

    /// The sheet opened by a row's Disconnect is up: its question, asked
    /// once (`disconnectQuestion`).
    func takeDisconnectQuestion() -> Bool {
        guard shownAsksToDisconnect else { return false }
        shownAsksToDisconnect = false
        return disconnectQuestion()
    }

    /// Whether the shown sheet may ask about a disconnect now; when it may
    /// not, the sheet says why.
    func disconnectQuestion() -> Bool {
        guard shownDisconnectable != nil else {
            connectionSheetMessage = Self.noLongerDisconnectableMessage
            return false
        }
        guard !isBusyWithAnotherRequest else {
            connectionSheetMessage = Self.anotherRequestMessage
            return false
        }
        connectionSheetMessage = nil
        return true
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

    private static let noLongerDisconnectableMessage = ConnectionsScreenMessage(
        kind: .error,
        text: NSLocalizedString(
            "This connection has nothing to disconnect now.",
            comment: "DashConnect: a disconnect asked for on a connection that no longer offers one"))

    /// With `keepingShown`, a read that fails leaves what the sheet shows.
    private func readShownDetails(_ item: ConnectionSheetItem, keepingShown: Bool = false) {
        detailsReadNumber += 1
        let number = detailsReadNumber
        if let entry = item.entry {
            shownDetails = ConnectionDetails(
                appId: entry.id, identityId: entry.identityId, username: entry.username, access: entry.access)
            shownDetailsFailed = false
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let details = await self.dataSource.connectionDetails(id: item.id, scope: item.connection?.scope)
            // Only the latest read of the sheet still up: one started before
            // the sheet closed, opened again or read again tells of a
            // connection as it was then.
            guard number == self.detailsReadNumber, self.shownConnection != nil else { return }
            if details == nil, keepingShown, self.shownDetails != nil { return }
            self.shownDetails = details
            self.shownDetailsFailed = details == nil
        }
    }

    func hideConnection() {
        detailsReadNumber += 1
        shownAsksToDisconnect = false
        shownConnection = nil
        shownDetails = nil
        shownDetailsFailed = false
        connectionSheetMessage = nil
    }

    /// Whether the sheet's details have to be read again for `item` after
    /// `previous`: another app, a row whose status changed, or a
    /// disconnected app's entry recorded again.
    private static func readsAnew(_ item: ConnectionSheetItem, from previous: ConnectionSheetItem) -> Bool {
        item.id != previous.id || item.connection?.status != previous.connection?.status
            || item.disconnectedAt != previous.disconnectedAt
    }

    /// The connection's sheet is gone from the screen.
    func connectionSheetDismissed() {
        isConnectionSheetOnScreen = false
        sheetDismissalNumber &+= 1
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
    func closeConnectionSheet() async {
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
    /// shows, or closed once it is neither a row nor a disconnected app, or
    /// is another wallet's. Not during a disconnect from it: the sheet waits
    /// for the list that shows the app disconnected.
    private func updateShownConnection() {
        guard let shown = shownConnection, !isDisconnecting else { return }
        let current = ConnectionsTab.allCases.lazy.flatMap { self.rows(for: $0) }.first { $0.id == shown.id }
        // Another wallet's row or disconnected app of the same app is
        // another connection: the sheet, its question and what it said were
        // about the one before.
        if let current, current.scope != shown.scope {
            hideConnection()
            return
        }
        if let current {
            if current != shown { shownConnection = current }
            // What the sheet reads changes with the app, its row, or whether
            // it is still connected.
            if Self.readsAnew(current, from: shown) {
                shownDetails = nil
                shownDetailsFailed = false
                readShownDetails(current)
            } else {
                // Same app and status: what it holds may still have changed
                // (another approval of it, a limits update), and the row
                // does not tell. Read again, showing the old until then.
                readShownDetails(current, keepingShown: true)
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
                self.pendingFailureStatus = nil
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
        // A request refused before the sheet never showed where it would
        // return, so its callback is not opened. One refused or failed at
        // Approve did, and the app hears how it ended.
        if let pendingLoginRequest, pendingRequest?.login.isApprovable == true || pendingFailureStatus != nil {
            openCallback(of: pendingLoginRequest, status: pendingFailureStatus ?? .declined)
        }
        pendingRequest = nil
        pendingLoginRequest = nil
        pendingFailureStatus = nil
        approveError = nil
    }

    /// Returns to the app that sent an App Connect request, with how it
    /// ended (`ac=<status>`). Only the callback the sheet showed ("returns
    /// to <host>") is opened, and only once the user has answered it: the
    /// user's answer to a sheet naming the host, with a warning when the app
    /// is unknown or the host is not its website
    /// (`AppConnect.originWarning`), stands in for the profile's "ask".
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

    /// The shown sheet's row, while its status still offers a disconnect
    /// (`StateActions`): a row that turned Refused or Disconnected while the
    /// sheet asked no longer does.
    private var shownDisconnectable: DAppConnection? {
        guard let shown = shownConnection, let connection = shown.connection,
              AppConnect.StateActions.row(for: shown.status).actions.contains(.disconnect) else { return nil }
        return connection
    }

    /// A disconnect confirmed on the shown sheet. It runs only if the sheet
    /// still offers one; otherwise the sheet says why nothing ran.
    func disconnectShown() {
        guard let connection = shownDisconnectable else {
            connectionSheetMessage = Self.noLongerDisconnectableMessage
            return
        }
        disconnect(connection)
    }

    func disconnect(_ connection: DAppConnection) {
        // Disconnecting an App Connect connection signs an identity update,
        // which takes seconds. It must not overlap anything else that signs
        // one or touches the same records: a second tap, an approval on
        // screen or in flight, a request still resolving, a `dash-st:` in
        // progress.
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
                // It may have turned some keys off before it failed, or the
                // records changed: what the sheet shows is read again.
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
            let notTurnedOff = result.keysStillLive > 0 || result.fencesNotPlaced > 0
            guard notTurnedOff || result.keysOnAnotherIdentity || result.keysNotChecked > 0 || result.keysNotAttributable > 0
                || result.unrecordedKeysTurnedOff > 0 else { return }
            var texts: [String] = []
            if result.unrecordedKeysTurnedOff > 0 {
                // swiftlint:disable line_length
                texts.append(String.localizedStringWithFormat(
                    NSLocalizedString(
                        "This also turned off keys on your identity that this wallet has no record of giving (%d), such as keys given on another device or DashPay profile keys.",
                        comment: "DashConnect: after a disconnect that turned off keys no approval in this wallet names"),
                    result.unrecordedKeysTurnedOff))
                // swiftlint:enable line_length
            }
            if result.keysStillLive > 0 {
                texts.append(String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Not every key was turned off: %d still on your identity. The connection stays listed; disconnect it again to turn them off.",
                        comment: "DashConnect: after a disconnect that stopped part-way or left keys live"),
                    result.keysStillLive))
            }
            if result.fencesNotPlaced > 0 {
                texts.append(String.localizedStringWithFormat(
                    NSLocalizedString(
                        "The sign-in may still land: some temporary keys (%d) may not be placed yet. Disconnect again to be sure they are turned off.",
                        comment: "DashConnect: after a disconnect whose fence keys the read after it does not show"),
                    result.fencesNotPlaced))
            }
            if result.keysNotChecked > 0 {
                texts.append(String.localizedStringWithFormat(
                    NSLocalizedString(
                        "This wallet could not tell yet which app holds some keys on your identity (%d), so it left them on. Open Connections again later to check them.",
                        comment: "DashConnect: after a disconnect that found keys whose app is not known yet"),
                    result.keysNotChecked))
            }
            if result.keysNotAttributable > 0 {
                // swiftlint:disable line_length
                texts.append(String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Some keys on your identity (%d) may belong to another app of the same developer, so this wallet left them on. Each one shows on its own row in Connections; disconnect it there if you no longer need it.",
                        comment: "DashConnect: after a disconnect that left keys another app of the same developer may hold"),
                    result.keysNotAttributable))
                // swiftlint:enable line_length
            }
            if result.keysOnAnotherIdentity {
                texts.append(DashConnectPlatformError.grantOnAnotherIdentity.localizedDescription)
            }
            // Keys still live, or nothing turned off here while the app still
            // has keys elsewhere, is not a success.
            let failed = notTurnedOff || (result.keysOnAnotherIdentity && result.keysTurnedOff == 0)
            self.show(
                ConnectionsScreenMessage(kind: failed ? .error : .notice, text: texts.joined(separator: "\n\n")),
                from: connection)
        }
    }

    /// Reads the active identity again when the screen shows, so a
    /// connection whose update landed or was turned off elsewhere shows as it
    /// is. Skipped while anything else is running.
    func refreshConnections() async {
        guard !featureUnavailable, !isDisconnecting, !isApproving, !isApprovingPurchase,
              !isProcessingStateTransition else { return }
        await dataSource.refreshConnections()
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
        // An error wins.
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
