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
        /// Active, with every live key past its expiry by this phone's clock
        /// and by the Core tip with its margin (`ConnectionExpiry.Verdict.expired`).
        case expired
        case disconnected

        /// A connection in this status can be disconnected: its keys may
        /// still be on. A two-QR row waiting for its second code offers that
        /// code instead, and a disconnected app has nothing left.
        var offersDisconnect: Bool { self == .active || self == .confirming || self == .expired }
    }

    let id: String
    let name: String
    let url: String
    let status: Status
    /// The page's row, which a disconnect acts on; `nil` for a disconnected app.
    let connection: DAppConnection?
    /// What was recorded of a disconnected app; `nil` for a row.
    let entry: DisconnectedConnection?
    /// The wallet, network and endpoint the item was published for.
    let scope: String?
    /// What the expiry check told for an active row; `nil` when it told
    /// nothing for it, and for any other item.
    var expiry: ConnectionExpiry.Verdict? = nil

    var disconnectedAt: Date? { entry?.disconnectedAt }
}

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published private(set) var connections: [DAppConnection] = []
    /// The rows were delivered once: until then nothing is known to be
    /// connected or not.
    @Published private(set) var hasReadRows = false
    @Published var selectedTab: ConnectionsTab = .active
    /// The apps disconnected on this wallet; `nil` when they could not be
    /// read (`historyIsUnreadable`).
    @Published private(set) var history: [DisconnectedConnection]? = []
    /// The wallet, network and endpoint the rows and the history were
    /// published for.
    private var listedScope: String?
    /// The expiry check of the rows, as published with them.
    @Published private(set) var expiries = ConnectionExpiries.notStarted
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
        if let entry = item.entry { return entry.connectedAt }
        return shownDetails?.connectedAt
    }

    /// Counts the reads of the shown sheet's details, and its closing: only
    /// the latest read is shown.
    private var detailsReadNumber = 0

    /// The sheet was opened by a row's Disconnect: it asks at once.
    private(set) var shownAsksToDisconnect = false

    var shownWithheldLines: [String] {
        shownDetails?.access?.isSessionKeyLogin == true
            ? DashConnectPermissionText.sessionKeyWithheld : DashConnectPermissionText.withheld
    }
    @Published private(set) var featureUnavailable: Bool
    /// The wallet has no username: a page with nothing connected offers to
    /// create one, and a login request that arrives is not approved
    /// (`answerWithoutUsername`).
    @Published private(set) var needsUsername: Bool
    @Published var pendingRequest: ConnectionRequest? {
        didSet {
            // Terms belong to one request, by its ephemeral key: a sheet for
            // another request starts from its defaults; the same request
            // rebuilt keeps what the user chose, also across a rebuild that
            // could not tell its login for a while.
            if let plan = pendingRequest?.login.grantPlan, plan.hasRecordedTerms {
                // An earlier approval of it recorded its terms; they stay.
                termsRequestHash = plan.appEphemeralPubKeyHash
                approvalTerms = AppConnect.terms(of: plan)
                approvalTermsLocked = true
            } else if let plan = pendingRequest?.login.grantPlan,
                      plan.appEphemeralPubKeyHash != termsRequestHash || approvalTermsLocked {
                // Another request, or the same one no longer carrying the
                // terms that fixed it (the record went): its defaults.
                termsRequestHash = plan.appEphemeralPubKeyHash
                approvalTerms = AppConnect.defaultTerms(for: plan, now: now())
                approvalTermsLocked = false
            } else if pendingRequest == nil {
                termsRequestHash = nil
                approvalTerms = nil
                approvalTermsLocked = false
            }
            approveNeedsTopUp = false
            smallestFundingLimit = pendingRequest?.login.grantPlan.flatMap(AppConnect.smallestFundingLimit)
        }
    }
    /// The smallest funding limit every key of the pending v2 request can
    /// share; read once per request (`AppConnect.smallestFundingLimit`).
    private var smallestFundingLimit: UInt64?
    /// The funding limit and expiry the user set for the pending v2 request;
    /// `nil` for any other request.
    @Published private(set) var approvalTerms: AppConnect.ConnectionTerms?
    /// The request `approvalTerms` were set for.
    private var termsRequestHash: Data?
    /// An earlier approval of this request recorded these terms before it
    /// submitted (`GrantPlan.hasRecordedTerms`): its update may have landed,
    /// so a retry sends them as they were and they cannot change.
    @Published private(set) var approvalTermsLocked = false
    /// The last approve attempt stopped because the identity's balance
    /// cannot pay to register the keys or to publish the response; the
    /// sheet offers a top-up.
    @Published private(set) var approveNeedsTopUp = false
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
    @Published var approveError: String? {
        didSet { approveErrorSubject = .request }
    }

    /// What `approveError` is about: a change of the terms clears a note
    /// on them, and leaves any other (a balance refusal, with its top-up).
    private enum ApproveErrorSubject {
        case terms
        case request
    }

    private var approveErrorSubject = ApproveErrorSubject.request
    /// Failure of the last token-purchase approve attempt, rendered inside
    /// the purchase sheet for the same reason as `approveError`.
    @Published var purchaseApproveError: String?

    private let dataSource: any DashConnectDataSource
    private let hasUsername: @MainActor () -> Bool
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
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = .default
    ) {
        let computedFeatureUnavailable = featureUnavailable ?? !WalletEnvironment.isTestNetwork
        self.featureUnavailable = computedFeatureUnavailable
        self.hasUsername = hasUsername
        self.needsUsername = !hasUsername()
        self.now = now
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
                self.expiries = listing.expiries
                self.hasReadRows = true
                self.updateShownConnection()
            }
            .store(in: &cancellables)
        // Back in the foreground, the expiry check's clocks may have moved on.
        notificationCenter.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.featureUnavailable else { return }
                self.dataSource.connectionExpiriesForegrounded()
            }
            .store(in: &cancellables)
    }

    /// The rows of `tab`. A row moves to Expired only once the check told it
    /// expired; a disconnected app is listed while it is not a row.
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

    /// The disconnected apps could not be read.
    var historyIsUnreadable: Bool { history == nil }

    /// Where the expiry check of the rows is.
    var expiryCheck: ConnectionExpiries.Check { expiries.check }

    /// The check ended telling every active row, but not for each whether it
    /// expired: some are past expiry by the phone alone, or held by a key
    /// that cannot be matched to an app. Reading again does not tell more.
    var expiriesAreUndecided: Bool {
        guard expiries.check == .read, !expiryCheckIsIncomplete else { return false }
        return connections.contains {
            guard $0.status == .active, let verdict = expiries.byApp[$0.id]?.verdict else { return false }
            return verdict == .undecided || verdict == .pastByPhone
        }
    }

    /// The expiry check ended without telling every active row: the read
    /// failed, could not be made on this network, or left a row unknown or
    /// out. More rows may have expired.
    var expiryCheckIsIncomplete: Bool {
        // With no active row there is nothing to check.
        guard hasActiveRows else { return false }
        switch expiries.check {
        case .failed, .unavailable: return true
        case .read:
            return connections.contains {
                $0.status == .active && (expiries.byApp[$0.id]?.verdict ?? .unknown) == .unknown
            }
        case .notStarted, .checking: return false
        }
    }

    /// Which rows have expired is not known yet: a row is active and no
    /// check has ended.
    var isCheckingExpiries: Bool {
        hasActiveRows && (expiries.check == .notStarted || expiries.check == .checking)
    }

    private var hasActiveRows: Bool { connections.contains { $0.status == .active } }

    /// The page appeared: the expiry check is made again, and goes on while
    /// the page is on screen.
    func checkExpiries() {
        guard !featureUnavailable else { return }
        dataSource.refreshConnectionExpiries(forcesRead: false)
    }

    /// Retry: the identity is read again.
    func retryExpiryCheck() {
        guard !featureUnavailable else { return }
        dataSource.refreshConnectionExpiries(forcesRead: true)
    }

    /// The page left the screen: the check stops reading.
    func stopCheckingExpiries() {
        guard !featureUnavailable else { return }
        dataSource.stopConnectionExpiryReads()
    }

    /// An active row the check told expired. A row confirming a renewal
    /// stays under Active whatever its earlier keys show.
    private func isExpired(_ connection: DAppConnection) -> Bool {
        connection.status == .active && expiries.byApp[connection.id]?.verdict == .expired
    }

    private func item(for connection: DAppConnection) -> ConnectionSheetItem {
        let status: ConnectionSheetItem.Status
        switch connection.status {
        case .active: status = isExpired(connection) ? .expired : .active
        case .confirming: status = .confirming
        case .approved: status = .waitingForSecondScan
        }
        return ConnectionSheetItem(
            id: connection.id, name: connection.name, url: connection.url, status: status,
            connection: connection, entry: nil, scope: connection.scope,
            expiry: connection.status == .active ? expiries.byApp[connection.id]?.verdict : nil)
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
        guard !isResolvingRequest, pendingRequest == nil, pendingReturn == nil, pendingTokenPurchase == nil else { return }
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
    func takeDisconnectQuestion() -> DashConnectDisconnectEffect? {
        guard shownAsksToDisconnect else { return nil }
        shownAsksToDisconnect = false
        return disconnectQuestion()
    }

    /// What the shown sheet's disconnect question says a disconnect does,
    /// read now; `nil` when it cannot ask, and the sheet then says why.
    func disconnectQuestion() -> DashConnectDisconnectEffect? {
        guard let item = shownConnection, let connection = item.connection, item.status.offersDisconnect else {
            connectionSheetMessage = Self.noLongerDisconnectableMessage
            return nil
        }
        guard !isBusyWithAnotherRequest else {
            connectionSheetMessage = Self.anotherRequestMessage
            return nil
        }
        guard let effect = dataSource.disconnectEffect(id: connection.id, scope: connection.scope) else {
            // Not the active wallet's, or gone from it.
            connectionSheetMessage = Self.connectionChangedMessage
            return nil
        }
        connectionSheetMessage = nil
        return effect
    }

    /// Something that signs, or touches the records a disconnect does, is
    /// running or about to show: a disconnect waits for it.
    private var isBusyWithAnotherRequest: Bool { isBusySigning || isResolvingRequest }

    /// Something signs, or an approval is on screen. A request still
    /// resolving is not counted here: a newer scan supersedes it.
    private var isBusySigning: Bool {
        isDisconnecting || isProcessingStateTransition || isApproving || isApprovingPurchase
            || pendingRequest != nil || pendingReturn != nil || pendingTokenPurchase != nil
    }

    /// Whether a scan may start now; otherwise the page says why.
    func mayScan() -> Bool {
        guard isBusySigning else { return true }
        // The return step covers the page, and an alert cannot show over it.
        if pendingReturn == nil { message = Self.anotherRequestMessage }
        return false
    }

    private static let anotherRequestMessage = ConnectionsScreenMessage(
        kind: .error,
        text: NSLocalizedString(
            "Another DashConnect request is in progress. Try again when it finishes.", comment: "DashConnect"))

    private static let staleQuestionMessage = ConnectionsScreenMessage(
        kind: .error, text: DashConnectPlatformError.disconnectEffectChanged.localizedDescription)

    private static let noLongerDisconnectableMessage = ConnectionsScreenMessage(
        kind: .error,
        text: NSLocalizedString(
            "This connection has nothing to disconnect now.",
            comment: "DashConnect: a disconnect asked for on a connection that no longer offers one"))

    private static let connectionChangedMessage = ConnectionsScreenMessage(
        kind: .error, text: DashConnectPlatformError.connectionGone.localizedDescription)

    private func readShownDetails(_ item: ConnectionSheetItem) {
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
    /// `previous`: another app, a row that changed (its status or kind), or
    /// a disconnected app's entry recorded again.
    private static func readsAnew(_ item: ConnectionSheetItem, from previous: ConnectionSheetItem) -> Bool {
        item.id != previous.id || item.connection?.status != previous.connection?.status
            || item.connection?.loginKind != previous.connection?.loginKind
            || item.disconnectedAt != previous.disconnectedAt
    }

    /// The connection's sheet is gone from the screen.
    func connectionSheetDismissed() {
        isConnectionSheetOnScreen = false
        // A request on its way owns the screen: the page cannot show an
        // alert and its sheet at once.
        if let waiting = messageAfterSheet, !isResolvingRequest, pendingRequest == nil, pendingReturn == nil,
           pendingTokenPurchase == nil {
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

    /// Reads again whether the wallet has a username, for a page coming back
    /// from creating one.
    func refreshUsername() {
        needsUsername = !hasUsername()
    }

    private func receive(_ content: String, byLink: Bool) {
        guard !featureUnavailable else { return }
        // Read before the request: the page shows whether to create a
        // username, and a request needs one unless it is a state transition.
        refreshUsername()
        // Without a username only a `dash-st:` request goes on. A key
        // registration runs: it completes a two-QR login this wallet
        // approved already, and fails without that approved row
        // (`pendingApprovedConnectionForKeyRegistration`). A token purchase
        // is refused once parsed, before the network is read for it
        // (`handleStateTransition`). Any other request is not approved
        // (`answerWithoutUsername`).
        if needsUsername, !DashConnectUri.isStUri(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
            answerWithoutUsername()
            return
        }

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

        // A new request ends the return step of the one before: its
        // return is not opened.
        pendingReturn = nil
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

                    let action: DashConnectStAction
                    do {
                        action = try await dataSource.handleStateTransition(
                            request, refusesTokenPurchase: needsUsername)
                    } catch let error as DashConnectPlatformError
                        where error == .tokenPurchaseNeedsUsername || (needsUsername && error == .noIdentity) {
                        // Said on every page, the create-username one too:
                        // the request goes no further. A wallet without a
                        // username usually has no identity either, which
                        // stops the request before its kind is read, so that
                        // one is told to create a username for apps at all.
                        message = ConnectionsScreenMessage(
                            kind: .error,
                            text: error == .tokenPurchaseNeedsUsername
                                ? DashConnectPlatformError.tokenPurchaseNeedsUsername.localizedDescription
                                : Self.usernameNeededText)
                        return
                    }
                    switch action {
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

    /// A login request that came while the wallet has no username: only
    /// the create-username note is shown, on the page, on an open
    /// connection's sheet, or on the return step's sheet when one is up.
    /// Nothing is opened and no return step starts: the user never saw this
    /// request's sheet, so its return address was not shown to anyone.
    private func answerWithoutUsername() {
        guard pendingReturn == nil else {
            returnStepNote = Self.usernameNeededText
            return
        }
        sayUsernameIsNeeded()
    }

    /// Why a request was not taken without a username.
    private func sayUsernameIsNeeded() {
        // The create-username page says it by itself; a page that may show
        // connections says it where the user is looking.
        if hasConnectionsOrHistory || !hasReadRows {
            let note = ConnectionsScreenMessage(kind: .error, text: Self.usernameNeededText)
            if shownConnection != nil { connectionSheetMessage = note } else { message = note }
        }
    }

    static var usernameNeededText: String {
        NSLocalizedString(
            "Create a username to connect apps, then ask the app for a new code.",
            comment: "DashConnect: a request arrived while the wallet has no username")
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
        let requestHash = consent.login.grantPlan?.appEphemeralPubKeyHash

        // A v2 approval registers its keys with the terms the user set.
        if consent.login.grantPlan != nil {
            // The button is off then; a tap that comes anyway gets the
            // reason as the sheet's note.
            guard let applied = termsAppliedPlan else {
                approveError = approveDisabledReason
                approveErrorSubject = .terms
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
                openCallback(of: pendingLoginRequest, status: .ok, asksToReturn: true)
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
            } catch DashConnectPlatformError.approvalTermsExpired {
                // The expiry went by while the PIN prompt was up. Nothing
                // was signed: the sheet stays, and says why itself
                // (`approveDisabledReason`). Closing the sheet now is a
                // decline, not a failure, unless an earlier attempt may have
                // landed (its terms are recorded).
                if !self.approvalTermsLocked { self.pendingFailureStatus = nil }
                self.approveError = nil
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
                let needsTopUp = AppConnect.isInsufficientBalance(error)
                // A grant recorded before the update was submitted fixes the
                // terms of a retry: the sheet is read again so it shows them,
                // when it still shows the request that failed.
                let platformError = error as? DashConnectPlatformError
                // Whatever the error, a record still kept fixes the terms: a
                // balance refusal may come after the keys were registered (the
                // response's publish), or after an attempt that may land.
                if platformError != .authorizationCancelled, platformError != .authorizationFailed,
                   let requestHash,
                   let access = await dataSource.recordedGrantedAccess(for: pendingLoginRequest),
                   var current = self.pendingRequest, let plan = current.login.grantPlan,
                   plan.appEphemeralPubKeyHash == requestHash {
                    let recorded = AppConnect.withRecordedTerms(
                        plan, access: access, recordedFor: requestHash, now: now())
                    if recorded.hasRecordedTerms {
                        current.login = .appConnect(recorded)
                        self.pendingRequest = current
                    }
                }
                // Platform refused the identity update, or the response's
                // publish after it, for the identity's balance.
                self.approveNeedsTopUp = needsTopUp
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
        guard let plan = pendingRequest?.login.grantPlan else { return nil }
        // Encryption keys only: no term applies to them, recorded or not.
        if plan.auth.isEmpty { return plan }
        guard let approvalTerms else { return nil }
        if plan.hasRecordedTerms { return AppConnect.hasValidTerms(plan, now: now()) ? plan : nil }
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
        // What the app asks for: a response that leaves an encryption slot out
        // is only known once it is sealed.
        return DashConnectPermissionText.granted(
            AppConnect.GrantedAccess(plan: plan, receivesMessages: !plan.encryption.isEmpty),
            appLabel: request.resolvedAppLabel)
    }

    /// How long ago the pending v2 request was made.
    var approvalRequestAge: String? {
        pendingRequest?.login.grantPlan.map { AppConnectOriginText.age($0, now: now()) }
    }

    /// The host of the return the step asks about (`pendingReturn`) or,
    /// before it, of the pending request's: a link's callback, which the
    /// return step asks about before opening. `nil` for a scanned code or a
    /// request with no callback. The parser takes lowercase hosts only.
    var pendingReturnHost: String? {
        if let pendingReturn { return pendingReturn.host }
        guard pendingRequestArrivedByLink, let callback = pendingLoginRequest?.appConnect?.callback else { return nil }
        return callback.host
    }

    /// What the sheet says first about any app, which the wallet does not
    /// know: naming `returnHost` when the wallet will ask before returning
    /// there.
    static func unknownAppText(returnHost: String?) -> String {
        guard let returnHost else {
            return NSLocalizedString(
                "This wallet does not know this app.",
                comment: "DashConnect approve sheet: an app the wallet does not know")
        }
        return String(
            format: NSLocalizedString(
                "This wallet does not know this app, so it cannot confirm where it will return you (%@).",
                comment: "DashConnect approve sheet: an app the wallet does not know; the placeholder is a website, e.g. yap.pr"),
            returnHost)
    }

    /// The first-connection caution. It does not name the app: the name is
    /// the one the request gives, shown in the title.
    static var firstConnectionText: String {
        NSLocalizedString(
            "You have never connected to this app before. Only approve if you trust it.",
            comment: "DashConnect: approve sheet, first connection caution")
    }

    /// The approve sheet's caution box for a v2 request, read from the
    /// pending request alone (the sheet's own). For a re-login: "This
    /// connection already exists." over since when it is on, then the
    /// unknown-app sentence (`unknownAppText`, naming the host of a link's
    /// return), one per line. Otherwise the unknown-app sentence over the
    /// first-connection caution, or over nothing.
    var approvalCaution: (title: String, subtitle: String?)? {
        guard let request = pendingRequest, request.login.grantPlan != nil else { return nil }
        if request.isRelogin {
            let lines = [request.connectedSinceText, Self.unknownAppText(returnHost: pendingReturnHost)]
            return (ConnectionRequest.alreadyConnectedText, lines.compactMap { $0 }.joined(separator: "\n"))
        }
        return (
            Self.unknownAppText(returnHost: pendingReturnHost),
            pendingIsFirstConnection ? Self.firstConnectionText : nil)
    }

    /// The first-connection caution: the app is neither connected nor in
    /// the history, in any status. While the history is not read, or cannot
    /// be, there is no caution: an earlier connection cannot be ruled out.
    var pendingIsFirstConnection: Bool {
        guard hasReadRows, let id = pendingRequest?.appContractId, let history else { return false }
        return !connections.contains { $0.id == id } && !history.contains { $0.id == id }
    }

    /// The funding presets every key of the pending request can share, with
    /// the one in effect.
    var fundingPresets: [(credits: UInt64, isSelected: Bool)] {
        AppConnect.fundingPresets
            .filter { preset in smallestFundingLimit.map { preset >= $0 } ?? false }
            .map { ($0, $0 == approvalTerms?.fundingLimit) }
    }

    /// The funding limit in effect when it is none of the presets offered
    /// (an app's own ask, or a typed amount), as "0.51 DASH"; `nil` when a
    /// preset is in effect.
    var customFundingLimitText: String? {
        guard let limit = approvalTerms?.fundingLimit, !fundingPresets.contains(where: \.isSelected) else { return nil }
        return PlatformCreditsFormatter.dashString(limit)
    }

    /// The custom limit as the keypad writes it ("0.51"), for the keypad to
    /// open on; `nil` when a preset is in effect.
    var customFundingLimitTyped: String? {
        guard customFundingLimitText != nil, let limit = approvalTerms?.fundingLimit else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = Self.creditDigits
        return formatter.string(from: NSDecimalNumber(
            decimal: Decimal(limit) / Decimal(PlatformCreditsFormatter.creditsPerDash)))
    }

    /// Whether the pending v2 request has a funding limit and an expiry to
    /// set: not for a plan of encryption keys only.
    var approvalHasTerms: Bool {
        pendingRequest?.login.grantPlan.map { !$0.auth.isEmpty } ?? false
    }

    /// Whether the user may change the funding limit: not for a request of
    /// DashPay profile keys only, whose budget is fixed (`profileKeyShare`).
    var canChangeFundingLimit: Bool {
        guard let plan = pendingRequest?.login.grantPlan else { return false }
        return !plan.auth.allSatisfy(AppConnect.isProfileKey)
    }

    /// The expiry presets in days, with the one in effect (to the day).
    var expiryPresets: [(days: Int, isSelected: Bool)] {
        let start = now()
        return AppConnect.expiryPresetDays.map { days in
            (days, approvalTerms.map { Self.sameDay($0.expiresAt, AppConnect.expiry(days: days, from: start)) } ?? false)
        }
    }

    /// The expiry in effect when it is none of the presets (an app's own
    /// ask, or a picked date), as the sheet writes dates; `nil` when a preset
    /// is in effect.
    var customExpiryText: String? {
        guard approvalTerms != nil, !expiryPresets.contains(where: \.isSelected) else { return nil }
        return approvalExpiryText
    }

    /// The latest expiry the user may pick now.
    var latestExpiry: Date { now().addingTimeInterval(AppConnect.v2LifetimeCap) }

    /// Sets the funding limit. False when it is out of bounds.
    @discardableResult
    func setFundingLimit(_ credits: UInt64) -> Bool {
        guard approvalTerms != nil, !approvalTermsLocked, AppConnect.isValidFundingLimit(credits),
              let plan = pendingRequest?.login.grantPlan,
              AppConnect.keyBudgets(for: plan, limit: credits) != nil else { return false }
        approvalTerms?.fundingLimit = credits
        // A note on the terms before is out of date.
        if approveErrorSubject == .terms { approveError = nil }
        return true
    }

    /// The credits a typed amount in DASH comes to, or `nil` when it is not a
    /// number this locale writes, or not a whole number of credits.
    func credits(fromDash text: String, locale: Locale = .current) -> UInt64? {
        guard let credits = typedCredits(fromDash: text, locale: locale), Self.isWhole(credits) else { return nil }
        return NSDecimalNumber(decimal: credits).uint64Value
    }

    private func typedCredits(fromDash text: String, locale: Locale) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let dash = Decimal(string: trimmed, locale: locale), dash >= 0 else { return nil }
        let credits = dash * Decimal(PlatformCreditsFormatter.creditsPerDash)
        return credits <= Decimal(UInt64.max) ? credits : nil
    }

    /// The decimal places of DASH a credit is: a limit has no more.
    private static let creditDigits = String(PlatformCreditsFormatter.creditsPerDash).count - 1

    private static func isWhole(_ value: Decimal) -> Bool {
        var value = value
        var whole = Decimal()
        NSDecimalRound(&whole, &value, 0, .down)
        return whole == value
    }

    /// Why a typed funding limit cannot be set, or `nil` when it can.
    func fundingLimitError(forDash text: String, locale: Locale = .current) -> String? {
        // Finer than a credit: said rather than cut to a smaller limit.
        if let typed = typedCredits(fromDash: text, locale: locale), !Self.isWhole(typed) {
            return String(
                format: NSLocalizedString(
                    "Use at most %ld digits after the decimal point",
                    comment: "DashConnect funding limit keypad: the number of decimal places a limit can have"),
                Self.creditDigits)
        }
        guard let credits = credits(fromDash: text, locale: locale), credits > 0 else { return nil }
        guard credits <= AppConnect.v2BudgetCapCredits else {
            return String(
                format: NSLocalizedString(
                    "Max limit is %@", comment: "DashConnect funding limit keypad: the cap with its unit, e.g. 5 DASH"),
                PlatformCreditsFormatter.dashString(AppConnect.v2BudgetCapCredits))
        }
        // Every key needs a budget of its own: a limit too small to share
        // gives one of them nothing.
        if let plan = pendingRequest?.login.grantPlan, AppConnect.keyBudgets(for: plan, limit: credits) == nil {
            return smallestFundingLimit.map {
                String(
                    format: NSLocalizedString(
                        "Min limit is %@", comment: "DashConnect funding limit keypad: the smallest limit with its unit"),
                    PlatformCreditsFormatter.dashString($0))
            } ?? NSLocalizedString(
                "This limit cannot be shared between the app's keys.",
                comment: "DashConnect funding limit keypad")
        }
        return nil
    }

    /// Why Approve cannot be pressed for the pending v2 request with the
    /// terms on screen; `nil` when it can.
    var approveDisabledReason: String? {
        guard pendingRequest?.login.grantPlan != nil, termsAppliedPlan == nil else { return nil }
        if approvalTermsLocked {
            return NSLocalizedString(
                "The terms an earlier approval of this request recorded are no longer valid. Ask the app for a new code.",
                comment: "DashConnect approve sheet: recorded terms out of bounds")
        }
        if let expiresAt = approvalTerms?.expiresAt, expiresAt <= AppConnect.milliseconds(now()) {
            return NSLocalizedString(
                "This expiry has passed. Pick another one, then approve.",
                comment: "DashConnect approve sheet: the chosen expiry is in the past")
        }
        return NSLocalizedString(
            "Set a funding limit and an expiry within the limits, then approve.",
            comment: "DashConnect approve sheet: the terms are out of bounds")
    }

    /// The expiry in effect, as a date, for the date picker to open on.
    var approvalExpiryDate: Date? {
        approvalTerms.map { Date(timeIntervalSince1970: TimeInterval($0.expiresAt) / 1000) }
    }

    /// The earliest expiry the user may pick now.
    var earliestExpiry: Date { now() }

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
        guard approvalTerms != nil, !approvalTermsLocked, AppConnect.isValidExpiry(expiresAt, now: now()) else {
            return false
        }
        approvalTerms?.expiresAt = expiresAt
        // A note on the terms before is out of date.
        if approveErrorSubject == .terms { approveError = nil }
        return true
    }

    private static func sameDay(_ lhs: UInt64, _ rhs: UInt64) -> Bool {
        Calendar.current.isDate(
            Date(timeIntervalSince1970: TimeInterval(lhs) / 1000),
            inSameDayAs: Date(timeIntervalSince1970: TimeInterval(rhs) / 1000))
    }

    /// Declines the request on screen. `asksToReturn`: the Deny button; a
    /// sheet closed by the user (`false`) does not go on to ask about the
    /// return, and nothing is opened.
    func denyPendingRequest(asksToReturn: Bool) {
        guard !isApproving else { return }
        // A refused request never showed where it would return, so its
        // callback is not opened.
        if let pendingLoginRequest, pendingRequest?.login.isApprovable == true {
            openCallback(of: pendingLoginRequest, status: pendingFailureStatus ?? .declined, asksToReturn: asksToReturn)
        }
        pendingRequest = nil
        pendingLoginRequest = nil
        pendingFailureStatus = nil
        approveError = nil
    }

    /// Returns to the app that sent an App Connect request, with how it
    /// ended (`ac=<status>`): only for a request that came as a link, and
    /// only once the user has answered it. The wallet knows no app's
    /// website, so every return is asked about on the sheet first
    /// (`pendingReturn`) when `asksToReturn`, and is not opened otherwise.
    /// The app treats it as a nudge to look for the response, never as
    /// proof of anything.
    private func openCallback(
        of request: DashKeyRequest,
        status: AppConnect.CallbackStatus,
        asksToReturn: Bool
    ) {
        guard asksToReturn, pendingRequestArrivedByLink,
              let callback = request.appConnect?.callback,
              let url = AppConnect.callbackURL(callback, status: status) else { return }
        pendingReturn = url
    }

    /// The return to an app the wallet does not know, of a request already
    /// answered: the approve sheet stays up and asks whether to open it
    /// (`openPendingReturn`, `stayInWallet`).
    @Published private(set) var pendingReturn: URL? {
        didSet { returnStepNote = nil }
    }

    /// Why a request that came while the return step is up was not taken,
    /// said on the step's sheet.
    @Published private(set) var returnStepNote: String?

    /// Opens the return the sheet asked about, and closes the sheet.
    func openPendingReturn() {
        guard let url = pendingReturn else { return }
        pendingReturn = nil
        openURL(url)
    }

    /// Closes the sheet without opening the return.
    func stayInWallet() {
        pendingReturn = nil
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
    /// (`asked`). It runs only if the sheet still offers one and the local
    /// records still describe it so (`DashConnectDisconnectEffect.accepts`);
    /// otherwise the sheet shows what holds now, and why nothing ran. The
    /// data source holds the disconnect to `asked` in its turn again.
    func disconnectShown(asked: DashConnectDisconnectEffect) {
        guard let item = shownConnection, let connection = item.connection, item.status.offersDisconnect else {
            connectionSheetMessage = Self.noLongerDisconnectableMessage
            return
        }
        guard let effect = dataSource.disconnectEffect(id: connection.id, scope: connection.scope) else {
            connectionSheetMessage = Self.connectionChangedMessage
            return
        }
        guard asked.accepts(effect) else {
            connectionSheetMessage = Self.staleQuestionMessage
            return
        }
        disconnect(connection, expecting: asked)
    }

    /// Disconnects `connection`, which the user was told does `expecting`.
    func disconnect(_ connection: DAppConnection, expecting: DashConnectDisconnectEffect) {
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
                result = try await self.dataSource.disconnect(
                    id: connection.id, scope: connection.scope, expecting: expecting)
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
                switch error {
                case DashConnectPlatformError.disconnectEffectChanged:
                    // Nothing ran: the sheet's Disconnect asks again with
                    // what holds now.
                    self.show(Self.staleQuestionMessage, from: connection)
                    return
                case DashConnectPlatformError.connectionGone:
                    // Nothing ran: the data source shows the page its rows,
                    // and the sheet of a row they no longer list closes.
                    self.show(Self.connectionChangedMessage, from: connection)
                    return
                default:
                    break
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
            // another app's. And when the app could not be kept in the
            // disconnected list.
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
            if result.notRecordedInHistory {
                said.append(said.isEmpty
                    ? NSLocalizedString(
                        "Disconnected. It could not be saved among the disconnected apps.",
                        comment: "DashConnect: after a disconnect that could not be kept in the Disconnected list")
                    : NSLocalizedString(
                        "It could not be saved among the disconnected apps.",
                        comment: "DashConnect: after a disconnect that could not be kept in the Disconnected list"))
            }
            if !said.isEmpty {
                // Not kept among the disconnected apps is a partial failure.
                self.show(
                    ConnectionsScreenMessage(
                        kind: result.notRecordedInHistory ? .error : .success, text: said.joined(separator: "\n\n")),
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
