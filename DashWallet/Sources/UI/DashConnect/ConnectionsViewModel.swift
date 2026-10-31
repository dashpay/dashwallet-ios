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

/// The tabs of the Connections page.
enum ConnectionsTab: CaseIterable {
    case active
    case disconnected
    case expired
}

/// A connection as its sheet shows it: a row of the page, or an app
/// disconnected earlier.
struct ConnectionSheetItem: Identifiable, Equatable {
    enum Status: Equatable {
        case active
        /// A v2 approval whose update's outcome is not known yet.
        case confirming
        /// A two-QR login waiting for the app's second code.
        case waitingForSecondScan
        case expired
        case disconnected
    }

    let id: String
    let name: String
    let url: String
    let status: Status
    /// Whether Platform could be read for the expiry; `false` shows the
    /// status as not checked.
    let isStatusChecked: Bool
    /// The page's row, which a disconnect acts on; `nil` for a disconnected app.
    let connection: DAppConnection?
    let disconnectedAt: Date?
}

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published private(set) var connections: [DAppConnection] = []
    @Published var selectedTab: ConnectionsTab = .active
    /// The apps disconnected on this wallet; `nil` until read, or when they
    /// could not be read (`historyIsUnreadable`).
    @Published private(set) var history: [DisconnectedConnection]?
    @Published private(set) var historyIsUnreadable = false
    /// Platform is being read for the connected apps' expiries.
    @Published private(set) var isCheckingStatus = false
    /// What the last action from the connection sheet ended in, shown on
    /// the sheet: an alert of the page cannot appear over it.
    @Published var connectionSheetMessage: ConnectionsScreenMessage?
    /// The history and expiry read running now; one asked for meanwhile
    /// runs once it ends (`refreshesStatusAgain`).
    private var statusRead: Task<Void, Never>?
    private var refreshesStatusAgain = false
    /// Each connected app's expiry as Platform shows it; `nil` until read, or
    /// when the identity could not be read. A row is listed as expired only
    /// once read so.
    @Published private(set) var expiries: [String: ConnectionExpiry]?
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
            appLabel: item.name,
            tense: item.status == .expired || item.status == .disconnected ? .past : .present)
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
        guard let item = shownConnection else { return nil }
        if item.connection == nil { return history?.first { $0.id == item.id }?.connectedAt }
        return shownDetails?.connectedAt
    }

    /// Whether disconnecting the shown connection turns its keys off on
    /// Platform, as the data source will run it; the row's kind until the
    /// details are read.
    var shownDisconnectRevokesKeys: Bool {
        shownDetails?.disconnectRevokesKeys ?? (shownConnection?.connection?.loginKind != .twoQR)
    }

    var shownWithheldLines: [String] {
        shownDetails?.access?.isSessionKeyLogin == true
            ? DashConnectPermissionText.sessionKeyWithheld : DashConnectPermissionText.withheld
    }
    @Published private(set) var featureUnavailable: Bool
    /// The wallet has no username: the page offers to create one, and a
    /// request that arrives is not read.
    @Published private(set) var needsUsername: Bool
    @Published var pendingRequest: ConnectionRequest? {
        didSet {
            // Terms belong to one request: a sheet for another one (or the
            // same one rebuilt with another plan) starts from its defaults;
            // the same request rebuilt keeps what the user chose.
            let plan = pendingRequest?.login.grantPlan
            if plan?.appEphemeralPubKeyHash != oldValue?.login.grantPlan?.appEphemeralPubKeyHash || approvalTerms == nil {
                approvalTerms = plan.map { AppConnect.defaultTerms(for: $0, now: now()) }
            }
            if plan == nil { approvalTerms = nil }
            approveNeedsTopUp = false
        }
    }
    /// The funding limit and expiry the user set for the pending v2 request;
    /// `nil` for any other request.
    @Published private(set) var approvalTerms: AppConnect.ConnectionTerms?
    /// The last approve attempt stopped because the identity's balance
    /// cannot pay to register the keys; the sheet offers a top-up.
    @Published private(set) var approveNeedsTopUp = false
    @Published var pendingTokenPurchase: DashConnectTokenPurchaseRequest?
    @Published var isApproving = false
    @Published var isApprovingPurchase = false
    @Published var isProcessingStateTransition = false
    /// A disconnect in progress, from the tap until it has ended and the
    /// local history shows its result, whether or not it signs an identity
    /// update; the expiry read after it is not part of it. Its own flag, not
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
    private let hasUsername: @MainActor () -> Bool
    /// Whether the identity's balance can pay to register keys; `nil` when it
    /// cannot be read.
    private let canPayKeyRegistration: @MainActor () -> Bool?
    private let now: () -> Date
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
        openURL: (@MainActor (URL) -> Void)? = nil,
        hasUsername: @escaping @MainActor () -> Bool = { true },
        canPayKeyRegistration: (@MainActor () -> Bool?)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let computedFeatureUnavailable = featureUnavailable ?? !WalletEnvironment.isTestNetwork
        self.featureUnavailable = computedFeatureUnavailable
        self.hasUsername = hasUsername
        self.needsUsername = !hasUsername()
        self.canPayKeyRegistration = canPayKeyRegistration ?? Self.identityCanPayKeyRegistration
        self.now = now
        self.dataSource = dataSource ?? Self.defaultDataSource(featureUnavailable: computedFeatureUnavailable)
        self.openURL = openURL ?? { UIApplication.shared.open($0) }

        self.dataSource.connections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.connections = $0.sorted(by: { $0.updatedAt > $1.updatedAt })
                self?.updateShownConnection()
            }
            .store(in: &cancellables)
        // The rows change when an app is approved, confirmed or removed,
        // which is when the expiries and the history can change too. The
        // screen reads them when it appears; the current value the
        // publisher replays is skipped.
        self.dataSource.connections
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshConnectionStatus()
            }
            .store(in: &cancellables)
    }

    /// The rows of `tab`. A row moves to Expired only once Platform showed
    /// its keys expired; a disconnected app is listed while it is not a row.
    func rows(for tab: ConnectionsTab) -> [ConnectionSheetItem] {
        switch tab {
        case .active:
            return connections.filter { !isExpired($0) }.map { item(for: $0) }
        case .expired:
            return connections.filter(isExpired).map { item(for: $0) }
        case .disconnected:
            let connected = Set(connections.map(\.id))
            return (history ?? []).filter { !connected.contains($0.id) }.map(item(for:))
        }
    }

    /// Whether the page shows its tabs: once anything was connected.
    var hasConnectionsOrHistory: Bool {
        !connections.isEmpty || !(history ?? []).isEmpty || historyIsUnreadable
    }

    /// Platform's expiries were read.
    var expiriesAreKnown: Bool { expiries != nil }

    /// The disconnected apps are being read for the first time.
    var isLoadingHistory: Bool { history == nil && !historyIsUnreadable && !featureUnavailable }

    /// An active row whose keys Platform showed expired. A row confirming
    /// a renewal stays under Active whatever its earlier keys show.
    private func isExpired(_ connection: DAppConnection) -> Bool {
        connection.status == .active && expiries?[connection.id] == .expired
    }

    private func item(for connection: DAppConnection) -> ConnectionSheetItem {
        let status: ConnectionSheetItem.Status
        switch connection.status {
        case .active: status = isExpired(connection) ? .expired : .active
        case .confirming: status = .confirming
        case .approved: status = .waitingForSecondScan
        }
        // Every active row has an answer once read; an app with nothing to
        // judge on this identity (`.notJudged`) is not a failed check.
        let checked = expiries?[connection.id].map { $0 != .unknown } ?? false
        return ConnectionSheetItem(
            id: connection.id, name: connection.name, url: connection.url, status: status,
            isStatusChecked: connection.status != .active || checked, connection: connection, disconnectedAt: nil)
    }

    private func item(for entry: DisconnectedConnection) -> ConnectionSheetItem {
        ConnectionSheetItem(
            id: entry.id, name: entry.name, url: entry.url, status: .disconnected, isStatusChecked: true,
            connection: nil, disconnectedAt: entry.disconnectedAt)
    }

    /// Reads the disconnected apps and the connected apps' expiries again.
    func refreshConnectionStatus() {
        guard !featureUnavailable else { return }
        Task { [weak self] in await self?.readConnectionStatus() }
    }

    /// One read at a time: the expiry read loads the identity from Platform
    /// in turn with the operations that sign, so a burst of row changes
    /// makes one more read, not one each. Returns once a read that started
    /// after this call has ended.
    private func readConnectionStatus() async {
        if let running = statusRead {
            refreshesStatusAgain = true
            await running.value
            return
        }
        let read = Task { [weak self] in
            guard let self else { return }
            await self.runStatusReads()
        }
        statusRead = read
        await read.value
    }

    private func runStatusReads() async {
        isCheckingStatus = true
        repeat {
            refreshesStatusAgain = false
            // The history is local: it shows without waiting on Platform.
            async let expiries = dataSource.connectionExpiries()
            let history = await dataSource.disconnectedConnections()
            self.history = history
            historyIsUnreadable = history == nil
            updateShownConnection()
            self.expiries = await expiries
            updateShownConnection()
        } while refreshesStatusAgain
        isCheckingStatus = false
        statusRead = nil
    }

    /// Opens the sheet of `item`, and reads what it shows. Not while a
    /// request reads or is on screen: its sheet comes next.
    func showConnection(_ item: ConnectionSheetItem) {
        guard !isResolvingRequest, pendingRequest == nil, pendingTokenPurchase == nil else { return }
        isConnectionSheetOnScreen = true
        shownConnection = item
        shownDetails = nil
        shownDetailsFailed = false
        connectionSheetMessage = nil
        readShownDetails(item)
    }

    private func readShownDetails(_ item: ConnectionSheetItem) {
        if item.connection == nil {
            let entry = history?.first { $0.id == item.id }
            shownDetails = entry.map {
                ConnectionDetails(appId: $0.id, identityId: $0.identityId, username: $0.username, access: $0.access)
            }
            shownDetailsFailed = entry == nil
            return
        }
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
        shownConnection = nil
        shownDetails = nil
        shownDetailsFailed = false
        connectionSheetMessage = nil
    }

    /// Whether the sheet's details have to be read again for `item` after
    /// `previous`: another app, a row that changed (its status or kind), or
    /// a connection that is no longer one. Not for the expiry check alone.
    private static func readsAnew(_ item: ConnectionSheetItem, from previous: ConnectionSheetItem) -> Bool {
        item.id != previous.id || item.connection?.status != previous.connection?.status
            || item.connection?.loginKind != previous.connection?.loginKind
            || (item.connection == nil) != (previous.connection == nil)
    }

    /// The connection's sheet is gone from the screen.
    func connectionSheetDismissed() {
        isConnectionSheetOnScreen = false
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
    /// shows, or closed once it is neither a row nor a disconnected app. Not
    /// during a disconnect from it: the row goes before the history entry is
    /// read, and the sheet then shows the app disconnected.
    private func updateShownConnection() {
        guard let shown = shownConnection, !isDisconnecting else { return }
        let current = ConnectionsTab.allCases.lazy.flatMap { self.rows(for: $0) }.first { $0.id == shown.id }
        if let current {
            guard current != shown else { return }
            shownConnection = current
            // What the sheet reads changes with the app, its row, or whether
            // it is still connected, not with the expiry check.
            if Self.readsAnew(current, from: shown) {
                shownDetails = nil
                shownDetailsFailed = false
                readShownDetails(current)
            }
        } else {
            hideConnection()
        }
    }

    func onQRScanned(_ content: String) {
        receive(content, byLink: false)
    }

    /// Reads again whether the wallet has a username, for a page coming back
    /// from creating one.
    func refreshUsername() {
        needsUsername = !hasUsername()
    }

    private func receive(_ content: String, byLink: Bool) {
        guard !featureUnavailable else { return }
        // A request opened from anywhere without a username lands on the
        // page's create-username state, not on an error: nothing is read.
        refreshUsername()
        guard !needsUsername else { return }

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
        guard var consent = pendingRequest, consent.login.isApprovable,
              let pendingLoginRequest, !isApproving, !isResolvingRequest else { return }

        // A v2 approval registers its keys with the terms the user set.
        if let plan = consent.login.grantPlan {
            guard let terms = approvalTerms, let applied = AppConnect.applying(terms, to: plan, now: now()) else {
                approveError = NSLocalizedString(
                    "Set a funding limit and an expiry within the limits, then approve again.",
                    comment: "DashConnect approve sheet: the terms are out of bounds")
                return
            }
            // Registering keys costs the identity a fee: one that cannot pay
            // it is offered a top-up rather than an update Platform refuses.
            if canPayKeyRegistration() == false {
                approveNeedsTopUp = true
                approveError = NSLocalizedString(
                    "Your identity balance cannot cover the fee to register this app's keys. Top it up, then approve again.",
                    comment: "DashConnect approve sheet: the identity cannot pay the key registration fee")
                return
            }
            consent.login = .appConnect(applied)
        }

        isApproving = true
        approveError = nil
        approveNeedsTopUp = false

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

    // MARK: Approval terms

    /// The pending v2 plan with the user's terms applied, as the sheet lists
    /// it; `nil` for any other request or terms out of bounds.
    var termsAppliedPlan: AppConnect.GrantPlan? {
        guard let plan = pendingRequest?.login.grantPlan, let approvalTerms else { return nil }
        return AppConnect.applying(approvalTerms, to: plan, now: now())
    }

    /// "Maximum of 0.5 DASH" for the pending request's funding limit.
    var approvalFundingText: String? {
        approvalTerms.map {
            String(
                format: NSLocalizedString(
                    "Maximum of %@", comment: "DashConnect approve sheet: the funding limit with its unit, e.g. 0.5 DASH"),
                PlatformCreditsFormatter.dashString($0.fundingLimit))
        }
    }

    /// The pending request's expiry as the sheet writes dates.
    var approvalExpiryText: String? {
        approvalTerms.map {
            DashConnectPermissionText.expiryFormatter.string(
                from: Date(timeIntervalSince1970: TimeInterval($0.expiresAt) / 1000))
        }
    }

    /// The lines of what the pending v2 request's app will be able to do.
    var approvalGrantedLines: [String]? {
        guard let plan = termsAppliedPlan, let request = pendingRequest else { return nil }
        return DashConnectPermissionText.granted(AppConnect.GrantedAccess(plan: plan), appLabel: request.appLabel)
    }

    /// What the sheet says about where the pending v2 request came from: a
    /// warning first when there is one, then when to approve it. When it was
    /// made is a detail line of its own.
    var approvalOriginLines: [String] {
        guard let plan = pendingRequest?.login.grantPlan, let request = pendingRequest else { return [] }
        return [AppConnectOriginText.warning(plan)].compactMap { $0 }
            + [AppConnectOriginText.onlyApprove(plan, appLabel: request.appLabel)]
    }

    var approvalHasOriginWarning: Bool {
        pendingRequest?.login.grantPlan.flatMap(AppConnectOriginText.warning) != nil
    }

    /// The first-connection caution: the app is neither connected nor in
    /// the history, in any status. A history not read yet counts as no
    /// earlier connection.
    var pendingIsFirstConnection: Bool {
        guard let id = pendingRequest?.appContractId else { return false }
        return !connections.contains { $0.id == id } && !(history ?? []).contains { $0.id == id }
    }

    /// The funding presets, with the one in effect.
    var fundingPresets: [(credits: UInt64, isSelected: Bool)] {
        AppConnect.fundingPresets.map { ($0, $0 == approvalTerms?.fundingLimit) }
    }

    /// The expiry presets in days, with the one in effect (to the day).
    var expiryPresets: [(days: Int, isSelected: Bool)] {
        let start = now()
        return AppConnect.expiryPresetDays.map { days in
            (days, approvalTerms.map { Self.sameDay($0.expiresAt, AppConnect.expiry(days: days, from: start)) } ?? false)
        }
    }

    /// The latest expiry the user may pick now.
    var latestExpiry: Date { now().addingTimeInterval(AppConnect.v2LifetimeCap) }

    /// Sets the funding limit. False when it is out of bounds.
    @discardableResult
    func setFundingLimit(_ credits: UInt64) -> Bool {
        guard approvalTerms != nil, AppConnect.isValidFundingLimit(credits) else { return false }
        approvalTerms?.fundingLimit = credits
        return true
    }

    /// The credits a typed amount in DASH comes to, or `nil` when it is not a
    /// number this locale writes.
    func credits(fromDash text: String, locale: Locale = .current) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let dash = Decimal(string: trimmed, locale: locale), dash >= 0 else { return nil }
        let credits = dash * Decimal(PlatformCreditsFormatter.creditsPerDash)
        guard credits <= Decimal(UInt64.max) else { return nil }
        return NSDecimalNumber(decimal: credits).uint64Value
    }

    /// Why a typed funding limit cannot be set, or `nil` when it can.
    func fundingLimitError(forDash text: String, locale: Locale = .current) -> String? {
        guard let credits = credits(fromDash: text, locale: locale), credits > 0 else { return nil }
        guard credits <= AppConnect.v2BudgetCapCredits else {
            return String(
                format: NSLocalizedString(
                    "Max limit is %@", comment: "DashConnect funding limit keypad: the cap with its unit, e.g. 5 DASH"),
                PlatformCreditsFormatter.dashString(AppConnect.v2BudgetCapCredits))
        }
        return nil
    }

    /// Sets the expiry to `days` from now.
    func setExpiry(days: Int) {
        setExpiry(AppConnect.expiry(days: days, from: now()))
    }

    /// Sets the expiry to the end of the day of `date`, capped at the latest
    /// allowed. False when that is not after now.
    @discardableResult
    func setExpiry(date: Date) -> Bool {
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
        let expiry = min(AppConnect.milliseconds(endOfDay), AppConnect.milliseconds(latestExpiry))
        return setExpiry(expiry)
    }

    @discardableResult
    private func setExpiry(_ expiresAt: UInt64) -> Bool {
        guard approvalTerms != nil, AppConnect.isValidExpiry(expiresAt, now: now()) else { return false }
        approvalTerms?.expiresAt = expiresAt
        return true
    }

    private static func sameDay(_ lhs: UInt64, _ rhs: UInt64) -> Bool {
        Calendar.current.isDate(
            Date(timeIntervalSince1970: TimeInterval(lhs) / 1000),
            inSameDayAs: Date(timeIntervalSince1970: TimeInterval(rhs) / 1000))
    }

    @MainActor
    private static func identityCanPayKeyRegistration() -> Bool? {
        #if DASHPAY
        return IdentityCreditBalance.current()?.isEnough
        #else
        return nil
        #endif
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
        guard !isDisconnecting, !isProcessingStateTransition, !isApproving, !isApprovingPurchase,
              !isResolvingRequest, pendingRequest == nil, pendingTokenPurchase == nil else {
            // The user confirmed it; say why nothing ran.
            show(ConnectionsScreenMessage(
                kind: .error,
                text: NSLocalizedString(
                    "Another DashConnect request is in progress. Try again when it finishes.", comment: "DashConnect")),
                from: connection)
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
                self.refreshConnectionStatus()
                self.show(ConnectionsScreenMessage(
                    kind: .error,
                    text: String(
                        format: NSLocalizedString("Could not disconnect: %@", comment: "DashConnect"),
                        error.localizedDescription)),
                    from: connection)
                return
            }
            // The history is local: read before the disconnect ends, so the
            // sheet shows the app disconnected rather than closing as its
            // row goes. The expiries, read from Platform, follow after.
            let history = await self.dataSource.disconnectedConnections()
            self.history = history
            self.historyIsUnreadable = history == nil
            self.isDisconnecting = false
            // The rows changed, which reads the expiries again.
            self.updateShownConnection()
            // What the disconnect did with the DashPay profile keys no
            // connection accounts for; said, since they may have been
            // another app's.
            if result.profileKeysUnchecked {
                self.show(ConnectionsScreenMessage(
                    kind: .success,
                    text: NSLocalizedString(
                        "Disconnected. DashPay profile keys not linked to any connection could not be checked, so none of them was turned off.",
                        comment: "DashConnect: after a disconnect whose unattributed DashPay profile keys could not be told apart")),
                    from: connection)
            } else if result.profileKeysTurnedOff > 0 {
                self.show(ConnectionsScreenMessage(
                    kind: .success,
                    text: String.localizedStringWithFormat(
                        NSLocalizedString(
                            "Disconnected. DashPay profile keys not linked to any connection were turned off as well: %d.",
                            comment: "DashConnect: after a disconnect, how many unattributed DashPay profile keys were also turned off"),
                        result.profileKeysTurnedOff)),
                    from: connection)
            }
        }
    }

    /// On the connection's sheet while it is up, on the page otherwise.
    private func show(_ message: ConnectionsScreenMessage, from connection: DAppConnection) {
        if shownConnection?.id == connection.id {
            connectionSheetMessage = message
        } else {
            self.message = message
        }
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
