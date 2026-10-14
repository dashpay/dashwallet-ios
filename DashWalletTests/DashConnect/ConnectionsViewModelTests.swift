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
import XCTest

#if canImport(dashpay)
@testable import dashpay
#elseif canImport(dashwallet)
@testable import dashwallet
#else
#error("Unknown test host module")
#endif

/// A data source whose metadata lookups wait until the test lets them go.
/// The sample QR code resolves to the sample request; any other content is
/// a login request labelled with that content, so a test can tell which
/// request published its sheet.
private final class DelayedLookupDataSource: DashConnectDataSource {
    var connections: AnyPublisher<[DAppConnection], Never> { Just([]).eraseToAnyPublisher() }

    /// Waiting lookups, oldest first, by request label.
    private var waiting: [(label: String, lookup: CheckedContinuation<Void, Never>)] = []
    private(set) var lookups = 0
    var waitingLabels: [String] { waiting.map(\.label) }

    /// Lets the oldest waiting lookup return.
    func finishLookup() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().lookup.resume()
    }

    /// Lets the lookup for the request labelled `label` return.
    func finishLookup(_ label: String) {
        guard let index = waiting.firstIndex(where: { $0.label == label }) else { return }
        waiting.remove(at: index).lookup.resume()
    }

    func parseQR(_ content: String) async throws -> DashConnectQr {
        let sample = MockDashConnectDataSource.sampleLoginRequest
        guard content != MockDashConnectDataSource.sampleLoginQRCode else { return .login(sample) }
        return .login(DashKeyRequest(appEphemeralPubKey: sample.appEphemeralPubKey, contractId: sample.contractId, label: content, network: sample.network))
    }

    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest {
        lookups += 1
        await withCheckedContinuation { waiting.append((loginRequest.label, $0)) }
        guard loginRequest != MockDashConnectDataSource.sampleLoginRequest else {
            return ConnectionRequest(loginRequest: loginRequest)
        }
        return ConnectionRequest(appLabel: loginRequest.label, appUrl: "", appContractId: "", walletUsername: nil, walletIdentityId: nil, existingConnection: nil)
    }

    func approveLogin(_ request: DashKeyRequest) async throws -> DAppConnection {
        throw DashConnectMockError.approveFailed
    }

    func handleStateTransition(_ request: DashStRequest) async throws -> DashConnectStAction {
        throw DashConnectMockError.stateTransitionNotSupported
    }

    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws {
        throw DashConnectMockError.approveFailed
    }

    func disconnect(id: String) async {}
    func remove(id: String) async {}
}

/// A data source with no lookup delay: content starting with `bad` fails to
/// parse, content starting with `st-` is a state transition that completes
/// a key registration — held until the test lets it go when
/// `holdsStateTransitions` is set — and anything else is a login request
/// labelled with that content.
private final class ScriptedDataSource: DashConnectDataSource {
    var connections: AnyPublisher<[DAppConnection], Never> { Just([]).eraseToAnyPublisher() }

    var holdsStateTransitions = false
    private var heldTransitions: [CheckedContinuation<Void, Never>] = []
    var heldTransitionCount: Int { heldTransitions.count }

    func finishStateTransition() {
        guard !heldTransitions.isEmpty else { return }
        heldTransitions.removeFirst().resume()
    }

    func parseQR(_ content: String) async throws -> DashConnectQr {
        let sample = MockDashConnectDataSource.sampleLoginRequest
        if content.hasPrefix("bad") { throw DashConnectMockError.stateTransitionNotSupported }
        if content.hasPrefix("st-") { return .stateTransition(DashStRequest(transitionBytes: Data(content.utf8), network: sample.network)) }
        return .login(DashKeyRequest(appEphemeralPubKey: sample.appEphemeralPubKey, contractId: sample.contractId, label: content, network: sample.network))
    }

    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest {
        ConnectionRequest(appLabel: loginRequest.label, appUrl: "", appContractId: "", walletUsername: nil, walletIdentityId: nil, existingConnection: nil)
    }

    func approveLogin(_ request: DashKeyRequest) async throws -> DAppConnection {
        throw DashConnectMockError.approveFailed
    }

    func handleStateTransition(_ request: DashStRequest) async throws -> DashConnectStAction {
        if holdsStateTransitions {
            await withCheckedContinuation { heldTransitions.append($0) }
        }
        return .keyRegistrationCompleted
    }

    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws {
        throw DashConnectMockError.approveFailed
    }

    func disconnect(id: String) async {}
    func remove(id: String) async {}
}

/// The deep-link queue hands a `dash-key:` link to the Connections screen and
/// waits for the view model's settlement — the approval sheet published, or
/// a refusal shown — before the next link. Without it, a second link that
/// arrived during the metadata lookup superseded the first and discarded
/// its approval.
@MainActor
final class ConnectionsViewModelTests: XCTestCase {
    private func settle(_ condition: @autoclosure @escaping () -> Bool, within seconds: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func testTwoQueuedLinksWithADelayedLookupSettleInTurnAndKeepTheFirstApproval() async {
        let dataSource = DelayedLookupDataSource()
        let viewModel = ConnectionsViewModel(dataSource: dataSource, featureUnavailable: false)
        let link = MockDashConnectDataSource.sampleLoginQRCode

        var firstSettled = 0
        viewModel.onURIReceived(link) { firstSettled += 1 }
        await settle(dataSource.lookups == 1)
        XCTAssertEqual(firstSettled, 0, "the lookup is still running: the queue stays busy")
        XCTAssertNil(viewModel.pendingRequest)

        dataSource.finishLookup()
        await settle(viewModel.pendingRequest != nil)
        XCTAssertEqual(viewModel.pendingRequest, MockDashConnectDataSource.sampleRequest)
        XCTAssertEqual(firstSettled, 0, "published is not presented: the queue waits for the sheet to be on screen")
        viewModel.sheetDidAppear()
        await settle(firstSettled == 1)
        XCTAssertEqual(firstSettled, 1, "settled once the approval sheet appeared")
        viewModel.sheetDidAppear()
        await settle(firstSettled > 1, within: 0.1)
        XCTAssertEqual(firstSettled, 1, "once")

        // The queue hands the second link over only now; the first request is
        // on screen and owns it, so the second is refused — and settles on
        // the next turn, with no presentation to wait for.
        var secondSettled = 0
        viewModel.onURIReceived(link) { secondSettled += 1 }
        XCTAssertEqual(secondSettled, 0, "never inside the call")
        await settle(secondSettled == 1)
        XCTAssertEqual(secondSettled, 1, "a refusal settles without waiting for a presentation")
        XCTAssertEqual(viewModel.pendingRequest, MockDashConnectDataSource.sampleRequest, "the first approval is still the one on screen")
        XCTAssertNotNil(viewModel.approveError, "the refusal is shown on the sheet")
        XCTAssertEqual(dataSource.lookups, 1, "no second lookup")
    }

    func testASupersededRequestSettlesSoTheQueueIsNotHeldByIt() async {
        let dataSource = DelayedLookupDataSource()
        let viewModel = ConnectionsViewModel(dataSource: dataSource, featureUnavailable: false)
        let link = MockDashConnectDataSource.sampleLoginQRCode

        var firstSettled = 0
        viewModel.onURIReceived(link) { firstSettled += 1 }
        await settle(dataSource.lookups == 1)

        // A QR scan from the screen itself (not the queue) supersedes the
        // resolving request: the queue's link settles, on the next turn.
        viewModel.onQRScanned(link)
        XCTAssertEqual(firstSettled, 0, "never inside the call that superseded it")
        await settle(firstSettled == 1)
        XCTAssertEqual(firstSettled, 1)

        dataSource.finishLookup()
        await settle(dataSource.lookups == 2)
        dataSource.finishLookup()
        await settle(viewModel.pendingRequest != nil)
        XCTAssertEqual(firstSettled, 1, "settled once, not again when the superseded lookup returns")
    }

    /// The metadata lookup outlasts the queue's watchdog: the queue moves on
    /// (its next link opens its own screen), and when the lookup returns the
    /// abandoned request publishes no approval sheet — nothing lands on top
    /// of that screen.
    func testARequestTheQueueGaveUpPublishesNothingWhenItsLookupReturns() async {
        let dataSource = DelayedLookupDataSource()
        let viewModel = ConnectionsViewModel(dataSource: dataSource, featureUnavailable: false)
        var abandoned = false
        var settled = 0
        viewModel.onURIReceived(MockDashConnectDataSource.sampleLoginQRCode, settled: { settled += 1 }, isAbandoned: { abandoned })
        await settle(dataSource.lookups == 1)

        abandoned = true // the watchdog released the dispatch
        dataSource.finishLookup()
        await settle(settled == 1)
        XCTAssertEqual(settled, 1, "settled, so a late report reaches the queue (which ignores it)")
        XCTAssertNil(viewModel.pendingRequest, "no approval sheet for a request the queue gave up")
        XCTAssertNil(viewModel.message)
    }

    /// The screen reporting an appearance while nothing waits for one (a
    /// sheet opened by a QR scan, a re-appearance) settles nothing.
    func testAnAppearanceNobodyWaitsForSettlesNothing() async {
        let dataSource = DelayedLookupDataSource()
        let viewModel = ConnectionsViewModel(dataSource: dataSource, featureUnavailable: false)
        viewModel.sheetDidAppear()

        var settled = 0
        viewModel.onURIReceived(MockDashConnectDataSource.sampleLoginQRCode) { settled += 1 }
        await settle(dataSource.lookups == 1)
        viewModel.sheetDidAppear()
        XCTAssertEqual(settled, 0, "nothing published yet: an appearance now is not this request's")
        dataSource.finishLookup()
        await settle(viewModel.pendingRequest != nil)
        XCTAssertEqual(settled, 0)
        viewModel.sheetDidAppear()
        await settle(settled == 1)
        XCTAssertEqual(settled, 1)
    }

    func testAnUnavailableFeatureSettlesAtOnce() async {
        let viewModel = ConnectionsViewModel(dataSource: DelayedLookupDataSource(), featureUnavailable: true)
        var settled = 0
        viewModel.onURIReceived(MockDashConnectDataSource.sampleLoginQRCode) { settled += 1 }
        await settle(settled == 1)
        XCTAssertEqual(settled, 1)
    }

    /// The root controller's side for DashConnect links: the real queue, and
    /// per hand-over the root's completion — end that hand-over, then hand
    /// the next link over at once, as `afterDismissingPresented` does with
    /// nothing presented — into the same view model.
    @MainActor
    private final class LinkRoot {
        let queue = DeepLinkQueue()
        let viewModel: ConnectionsViewModel
        private(set) var dispatched: [String] = []
        private(set) var completions: [String: Int] = [:]

        init(viewModel: ConnectionsViewModel) {
            self.viewModel = viewModel
        }

        func enqueue(_ label: String) {
            queue.enqueue(DeepLink(url: URL(string: label)!, isInvitation: false, isUnsupported: false))
        }

        func dispatchNext() {
            guard let link = queue.takeNext(walletPresented: true, attached: true, unlocked: true, launchHoldPending: false, invitationsReady: true) else { return }
            let label = link.url.absoluteString
            let token = queue.dispatchToken
            dispatched.append(label)
            viewModel.onURIReceived(label, settled: { [unowned self] in
                self.completions[label, default: 0] += 1
                guard self.queue.dispatchDidFinish(token: token) else { return }
                self.dispatchNext()
            }, isAbandoned: { [unowned self] in !self.queue.isDispatching || self.queue.dispatchToken != token })
        }
    }

    /// Link A is resolving its metadata, links C and D are queued, and the
    /// user scans request B on the Connections screen. B's start must not
    /// run C inside it; C is handed over on the next turn and owns the view
    /// model (B's and A's lookups publish nothing), D is handed over once
    /// C's sheet is on screen, and A, C and D each settle exactly once.
    func testAManualScanOverAResolvingLinkDoesNotReenterOrLoseTheQueuedOne() async {
        let dataSource = DelayedLookupDataSource()
        let viewModel = ConnectionsViewModel(dataSource: dataSource, featureUnavailable: false)
        let root = LinkRoot(viewModel: viewModel)
        root.enqueue("link-a")
        root.enqueue("link-c")
        root.enqueue("link-d")
        root.dispatchNext()
        await settle(dataSource.waitingLabels == ["link-a"])
        XCTAssertEqual(dataSource.waitingLabels, ["link-a"], "A is resolving")

        viewModel.onQRScanned("scan-b") // the Connections screen's own scanner

        XCTAssertEqual(root.dispatched, ["link-a"], "C is not handed over inside B's start")
        XCTAssertTrue(root.completions.isEmpty, "A is settled after B's start returns, not inside it")

        await settle(root.dispatched == ["link-a", "link-c"])
        XCTAssertEqual(root.completions, ["link-a": 1])
        await settle(Set(dataSource.waitingLabels) == ["link-a", "scan-b", "link-c"])
        XCTAssertEqual(Set(dataSource.waitingLabels), ["link-a", "scan-b", "link-c"])

        // B's and A's lookups return first: both were superseded.
        dataSource.finishLookup("scan-b")
        dataSource.finishLookup("link-a")
        await settle(viewModel.pendingRequest != nil, within: 0.3)
        XCTAssertNil(viewModel.pendingRequest, "a superseded request publishes nothing")
        XCTAssertTrue(root.queue.isDispatching, "C's hand-over is still in flight")

        dataSource.finishLookup("link-c")
        await settle(viewModel.pendingRequest != nil)
        XCTAssertEqual(viewModel.pendingRequest?.appLabel, "link-c", "C owns the view model")
        XCTAssertNil(root.completions["link-c"], "C waits for its sheet to be on screen")
        XCTAssertEqual(root.dispatched, ["link-a", "link-c"], "D waits for C")

        viewModel.sheetDidAppear() // C's sheet appeared
        await settle(root.completions["link-d"] == 1)

        XCTAssertEqual(root.dispatched, ["link-a", "link-c", "link-d"], "D is handed over once C settled")
        XCTAssertEqual(root.completions, ["link-a": 1, "link-c": 1, "link-d": 1], "each link settled exactly once")
        XCTAssertEqual(viewModel.pendingRequest?.appLabel, "link-c", "D was refused: C's sheet is up")
        XCTAssertNotNil(viewModel.approveError)
        XCTAssertFalse(root.queue.isDispatching)
        XCTAssertTrue(root.queue.isEmpty)
        XCTAssertEqual(dataSource.lookups, 3, "no lookup for the refused D")
    }

    /// Link C has published its approval, but its sheet has not appeared
    /// yet, when a manual scan arrives (C's lookup finished while the
    /// scanner was being dismissed). The newcomer is refused without
    /// starting: C stays current, C's link is not settled and link D is not
    /// handed over until C's sheet appears; a refused newcomer that carries
    /// a completion settles it once. Then C's appearance settles C once and
    /// D proceeds.
    func testARefusedNewcomerBeforeTheSheetAppearsLeavesThePendingRequestWaiting() async {
        let dataSource = DelayedLookupDataSource()
        let viewModel = ConnectionsViewModel(dataSource: dataSource, featureUnavailable: false)
        let root = LinkRoot(viewModel: viewModel)
        root.enqueue("link-c")
        root.enqueue("link-d")
        root.dispatchNext()
        await settle(dataSource.waitingLabels == ["link-c"])
        dataSource.finishLookup("link-c")
        await settle(viewModel.pendingRequest != nil)
        XCTAssertEqual(viewModel.pendingRequest?.appLabel, "link-c", "C's approval is published, its sheet not yet on screen")

        viewModel.onQRScanned("scan-x") // the scanner's late callback
        var newcomerSettled = 0
        viewModel.onQRScanned("scan-y", settled: { newcomerSettled += 1 })

        await settle(newcomerSettled == 1)
        await settle(root.completions["link-c"] != nil, within: 0.3)
        XCTAssertEqual(newcomerSettled, 1, "the refused newcomer's own completion settles")
        XCTAssertNil(root.completions["link-c"], "C still waits for its sheet to appear")
        XCTAssertEqual(root.dispatched, ["link-c"], "D is not handed over before C's sheet appears")
        XCTAssertTrue(root.queue.isDispatching)
        XCTAssertEqual(viewModel.pendingRequest?.appLabel, "link-c", "C's approval is not replaced")
        XCTAssertNotNil(viewModel.approveError, "the refusal is shown on C's sheet")
        XCTAssertEqual(dataSource.lookups, 1, "the refused newcomers start no lookup")

        viewModel.sheetDidAppear() // C's sheet appeared
        await settle(root.completions["link-d"] == 1)
        XCTAssertEqual(root.completions, ["link-c": 1, "link-d": 1], "C settled once, on its appearance; D (refused: C's sheet is up) once")
        XCTAssertEqual(root.dispatched, ["link-c", "link-d"])
        XCTAssertEqual(newcomerSettled, 1, "once")
        XCTAssertFalse(root.queue.isDispatching)
        XCTAssertTrue(root.queue.isEmpty)
    }

    // MARK: Alerts settle on dismissal

    /// A link that fails shows an error alert. A native alert hosts no view,
    /// so nothing reports it on screen; the link settles when the alert is
    /// dismissed, and a sheet appearing meanwhile is not its settlement.
    func testAFailedLinkSettlesWhenItsAlertIsDismissed() async {
        let viewModel = ConnectionsViewModel(dataSource: ScriptedDataSource(), featureUnavailable: false)
        var settled = 0
        viewModel.onURIReceived("bad-link") { settled += 1 }
        await settle(viewModel.message != nil)
        XCTAssertEqual(viewModel.message?.kind, .error)

        viewModel.sheetDidAppear()
        await settle(settled > 0, within: 0.1)
        XCTAssertEqual(settled, 0, "the alert is up: the queue waits for its dismissal")

        viewModel.message = nil // OK
        await settle(settled == 1)
        XCTAssertEqual(settled, 1)
        await settle(settled > 1, within: 0.1)
        XCTAssertEqual(settled, 1, "once")
    }

    func testAKeyRegistrationSettlesWhenItsSuccessAlertIsDismissed() async {
        let viewModel = ConnectionsViewModel(dataSource: ScriptedDataSource(), featureUnavailable: false)
        var settled = 0
        viewModel.onURIReceived("st-registration") { settled += 1 }
        await settle(viewModel.message != nil)
        XCTAssertEqual(viewModel.message?.kind, .success)
        await settle(settled > 0, within: 0.1)
        XCTAssertEqual(settled, 0)

        viewModel.message = nil
        await settle(settled == 1)
        XCTAssertEqual(settled, 1)
    }

    /// A failed link's alert is still up when the queue moves on (its
    /// watchdog released it) and the next link publishes an approval sheet.
    /// That sheet's appearance settles the sheet's own link, not the
    /// failed one, which settles when its alert is dismissed.
    func testASheetAppearanceSettlesItsOwnLinkWhileAnEarlierAlertIsUp() async {
        let viewModel = ConnectionsViewModel(dataSource: ScriptedDataSource(), featureUnavailable: false)
        var failedSettled = 0
        viewModel.onURIReceived("bad-link") { failedSettled += 1 }
        await settle(viewModel.message != nil)

        var loginSettled = 0
        viewModel.onURIReceived("login-b") { loginSettled += 1 }
        await settle(viewModel.pendingRequest != nil)
        XCTAssertEqual(viewModel.pendingRequest?.appLabel, "login-b")

        viewModel.sheetDidAppear()
        await settle(loginSettled == 1)
        XCTAssertEqual(loginSettled, 1, "the sheet's appearance is the login link's")
        XCTAssertEqual(failedSettled, 0, "the failed link still waits for its alert to be dismissed")

        viewModel.message = nil
        await settle(failedSettled == 1)
        XCTAssertEqual(failedSettled, 1)
        XCTAssertEqual(loginSettled, 1)
    }

    /// A link refused while a key registration is running shows its refusal
    /// as an alert and settles when that alert is dismissed; the
    /// registration's own link settles when its success alert is dismissed.
    func testALinkRefusedDuringAKeyRegistrationSettlesWhenItsAlertIsDismissed() async {
        let dataSource = ScriptedDataSource()
        dataSource.holdsStateTransitions = true
        let viewModel = ConnectionsViewModel(dataSource: dataSource, featureUnavailable: false)
        var registrationSettled = 0
        viewModel.onURIReceived("st-registration") { registrationSettled += 1 }
        await settle(dataSource.heldTransitionCount == 1)
        XCTAssertTrue(viewModel.isProcessingStateTransition)

        var refusedSettled = 0
        viewModel.onURIReceived("login-b") { refusedSettled += 1 }
        XCTAssertEqual(viewModel.message?.kind, .error, "the refusal is an alert")
        viewModel.sheetDidAppear()
        await settle(refusedSettled > 0, within: 0.1)
        XCTAssertEqual(refusedSettled, 0, "the refusal waits for its alert to be dismissed")

        viewModel.message = nil
        await settle(refusedSettled == 1)
        XCTAssertEqual(refusedSettled, 1)
        XCTAssertEqual(registrationSettled, 0, "the registration is still running")

        dataSource.finishStateTransition()
        await settle(viewModel.message?.kind == .success)
        XCTAssertEqual(registrationSettled, 0)
        viewModel.message = nil
        await settle(registrationSettled == 1)
        XCTAssertEqual(registrationSettled, 1)
        XCTAssertEqual(refusedSettled, 1)
    }
}
