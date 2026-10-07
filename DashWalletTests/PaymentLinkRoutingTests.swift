//
//  PaymentLinkRoutingTests.swift
//  DashWalletTests
//
//  A link never destroys what is on screen. While a send waits on the network
//  or a payment screen holds its exits — also for an unacknowledged inline
//  result — (`PaymentInFlightHold`, ending exactly once, also when dropped), for
//  `PaymentInFlight.resultGracePeriod` after it, or while anything is
//  presented in the chain the router would dismiss, a link that would replace
//  the screen is refused with a notice and not kept.
//

import Combine
import os
import SwiftUI
import UIKit
import XCTest
@testable import dashpay

@MainActor
final class PaymentLinkRoutingTests: XCTestCase {
    private var window: UIWindow!
    private var refusals: [PaymentInFlight.Refusal] = []
    private var notices: Int { refusals.count }
    private var realNotice: ((PaymentInFlight.Refusal) -> Void)!

    override func setUp() {
        super.setUp()
        PaymentInFlight.abandonHolds()
        realNotice = PaymentInFlight.showRefusalNotice
        PaymentInFlight.showRefusalNotice = { [unowned self] in self.refusals.append($0) }
        // Attached to the host app's scene: presentations only run for a
        // window that is really on screen.
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.windowLevel = .alert + 1
    }

    override func tearDown() {
        PaymentInFlight.abandonHolds()
        PaymentInFlight.showRefusalNotice = realNotice
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private func spin(until condition: () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    /// The window's root holding a tab bar with a navigation stack, as the
    /// app's root holds its main screen.
    private func showMainScreen() -> (root: UIViewController, tabScreen: UIViewController) {
        let root = UIViewController()
        let tabScreen = UIViewController()
        let tabs = UITabBarController()
        tabs.viewControllers = [UINavigationController(rootViewController: tabScreen)]
        root.addChild(tabs)
        root.view.addSubview(tabs.view)
        tabs.didMove(toParent: root)
        window.rootViewController = root
        window.makeKeyAndVisible()
        return (root, tabScreen)
    }

    // MARK: Holds

    func testAHoldEndsOnceAndAlsoWhenItsOwnerDropsIt() {
        let hold = PaymentInFlightHold()
        let other = PaymentInFlightHold()
        hold.end()
        hold.end()
        XCTAssertTrue(PaymentInFlight.isActive, "a repeated end does not end another hold")
        other.end()
        XCTAssertFalse(PaymentInFlight.isActive)

        var dropped: PaymentInFlightHold? = PaymentInFlightHold()
        XCTAssertTrue(PaymentInFlight.isActive)
        XCTAssertNotNil(dropped)
        dropped = nil
        XCTAssertFalse(PaymentInFlight.isActive, "a dropped hold ends")
    }

    func testATeardownAbandonsHoldsWithoutAGracePeriodAndTheirLateEndsChangeNothing() {
        var old: PaymentInFlightHold? = PaymentInFlightHold()
        PaymentInFlight.abandonHolds()
        XCTAssertFalse(PaymentInFlight.isActiveOrSettling, "a wipe or network switch ends them at once")

        let fresh = PaymentInFlightHold()
        old?.end()
        old = nil
        XCTAssertTrue(PaymentInFlight.isActive, "an abandoned hold ending late does not end a new one")
        fresh.end()
        XCTAssertFalse(PaymentInFlight.isActive)
    }

    func testAHeldNetworkWaitHoldsForTheWaitAndStartsTheResultsGrace() async throws {
        let result = try await SwiftDashSDKTransactionSender.waitingForNetwork(holdingRouting: true) { () -> Int in
            XCTAssertTrue(PaymentInFlight.isActive, "held while the send waits")
            return 7
        }
        XCTAssertEqual(result, 7)
        XCTAssertFalse(PaymentInFlight.isActive, "ended with the wait")
        XCTAssertTrue(PaymentInFlight.isActiveOrSettling, "the result's way to the screen is still covered")

        do {
            _ = try await SwiftDashSDKTransactionSender.waitingForNetwork(holdingRouting: true) { () -> Int in
                throw CancellationError()
            }
            XCTFail("the failure reaches the caller")
        } catch is CancellationError {}
        XCTAssertFalse(PaymentInFlight.isActive, "a failed wait ends its hold too")
    }

    func testAnUnheldNetworkWaitHoldsNothing() async throws {
        _ = try await SwiftDashSDKTransactionSender.waitingForNetwork(holdingRouting: false) { () -> Int in
            XCTAssertFalse(PaymentInFlight.isActive, "a background send does not refuse links")
            return 1
        }
        XCTAssertFalse(PaymentInFlight.isActiveOrSettling)
    }

    // MARK: The router's rule

    func testALinkIsRoutedWhenNothingIsPresentedAndNothingIsInFlight() {
        let (root, _) = showMainScreen()
        XCTAssertFalse(PaymentInFlight.refusesLink(over: root))
        XCTAssertEqual(notices, 0)
    }

    func testALinkIsRefusedDuringASendAndItsResultsGraceThenRoutedAndNothingIsReplayed() {
        let (root, _) = showMainScreen()
        let send = PaymentInFlightHold()
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root), "refused while the send waits")
        send.end()
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root), "refused while its result may still be on its way")
        XCTAssertEqual(notices, 2, "each refusal says so")

        spin(until: { !PaymentInFlight.isActiveOrSettling }, timeout: PaymentInFlight.resultGracePeriod + 2)
        XCTAssertFalse(PaymentInFlight.refusesLink(over: root), "routed once the grace has passed")
        XCTAssertEqual(notices, 2, "nothing refused earlier is kept or replayed")
    }

    func testALinkIsRefusedWhileAnythingThatRoutingWouldDismissIsPresented() {
        let (root, tabScreen) = showMainScreen()
        let sheet = UIViewController()
        var shown = false
        // From a screen deep in a tab, like a success screen or a sheet over a
        // payment screen: the presentation lands at the root.
        tabScreen.present(sheet, animated: false) { shown = true }
        spin(until: { shown })
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root), "refused over a presented screen")

        let alert = UIAlertController(title: "Done", message: nil, preferredStyle: .alert)
        var alertShown = false
        sheet.present(alert, animated: false) { alertShown = true }
        spin(until: { alertShown })
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root), "and over an alert on top of it")

        var dismissed = false
        root.dismiss(animated: false) { dismissed = true }
        spin(until: { dismissed })
        XCTAssertFalse(PaymentInFlight.refusesLink(over: root), "routed again once nothing is presented")
    }

    func testAPresentationKeptInsideAScreensOwnContextDoesNotRefuseALink() {
        let (root, tabScreen) = showMainScreen()
        // A screen that defines its own presentation context, as some tab
        // screens do: the router's dismissal never reaches what it presents.
        tabScreen.definesPresentationContext = true
        let local = UIViewController()
        local.modalPresentationStyle = .currentContext
        var shown = false
        tabScreen.present(local, animated: false) { shown = true }
        spin(until: { shown })
        XCTAssertFalse(PaymentInFlight.refusesLink(over: root))
    }

    func testAHeldPaymentScreenRefusesLinksAndTabChangesUntilReleased() {
        let (root, tabScreen) = showMainScreen()
        let hold = ExitHold(on: tabScreen)
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root))
        XCTAssertTrue(PaymentInFlight.refusesTabChange(), "another tab or the payments sheet would hide it")
        XCTAssertEqual(refusals, [.link, .navigation])

        hold.release()
        XCTAssertTrue(PaymentInFlight.refusesTabChange(), "a result may still be on its way")
        spin(until: { !PaymentInFlight.isActiveOrSettling }, timeout: PaymentInFlight.resultGracePeriod + 2)
        XCTAssertFalse(PaymentInFlight.refusesTabChange(), "the tab bar is free again after the grace")
        XCTAssertFalse(PaymentInFlight.refusesLink(over: root))
    }

    func testAnInlineSwiftUIResultOwnsRoutingUntilItIsAcknowledged() {
        let (root, _) = showMainScreen()
        let navigation = (root.children.first as? UITabBarController)?.viewControllers?.first as? UINavigationController
        let state = InlineResultState()
        // A pushed payment screen whose result is a dialog in its own view
        // hierarchy, as DashSpend's is — no presentation for the router to see.
        let screen = UIHostingController(rootView: InlineResultScreen(state: state))
        navigation?.pushViewController(screen, animated: false)
        spin(until: { screen.view.window != nil })
        XCTAssertFalse(PaymentInFlight.isAnythingPresented(over: root))

        state.resultShown = true
        spin(until: { PaymentInFlight.isActive })
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root), "refused while the inline result is up")
        XCTAssertTrue(PaymentInFlight.refusesTabChange())

        state.resultShown = false
        spin(until: { !PaymentInFlight.isActive })
        spin(until: { !PaymentInFlight.isActiveOrSettling }, timeout: PaymentInFlight.resultGracePeriod + 2)
        XCTAssertFalse(PaymentInFlight.refusesTabChange(), "acknowledged")
        XCTAssertFalse(PaymentInFlight.refusesLink(over: root))
    }

    func testAPaymentScreenLockedWhileCoveredByAPushTakesNoHoldUntilItIsBackOnScreen() throws {
        let (root, _) = showMainScreen()
        let tabs = try XCTUnwrap(root.children.first as? UITabBarController)
        let navigation = try XCTUnwrap(tabs.viewControllers?.first as? UINavigationController)
        let state = InlineResultState()
        let screen = UIHostingController(rootView: InlineResultScreen(state: state))
        navigation.pushViewController(screen, animated: false)
        spin(until: { screen.view.window != nil })
        XCTAssertNotNil(screen.view.window)
        navigation.pushViewController(UIViewController(), animated: false)
        spin(until: { screen.view.window == nil })
        XCTAssertNil(screen.view.window, "covered")

        // A result arriving for a screen nobody can see must not refuse
        // routing app-wide with nothing on screen.
        state.resultShown = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(PaymentInFlight.isActive)

        navigation.popViewController(animated: false)
        spin(until: { PaymentInFlight.isActive })
        XCTAssertTrue(PaymentInFlight.isActive, "back on screen with its result: held")
        state.resultShown = false
        spin(until: { !PaymentInFlight.isActive })
        XCTAssertFalse(PaymentInFlight.isActive)
    }

    func testAPaymentScreenLockedInAHiddenTabTakesNoHoldUntilItsTabIsBack() throws {
        let (root, _) = showMainScreen()
        let tabs = try XCTUnwrap(root.children.first as? UITabBarController)
        tabs.viewControllers?.append(UINavigationController(rootViewController: UIViewController()))
        let navigation = try XCTUnwrap(tabs.viewControllers?.first as? UINavigationController)
        let state = InlineResultState()
        let screen = UIHostingController(rootView: InlineResultScreen(state: state))
        navigation.pushViewController(screen, animated: false)
        spin(until: { screen.view.window != nil })
        XCTAssertNotNil(screen.view.window)

        tabs.selectedIndex = 1
        spin(until: { screen.view.window == nil })
        XCTAssertNil(screen.view.window, "its tab is hidden")
        state.resultShown = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(PaymentInFlight.isActive, "a hidden tab's screen refuses nothing")

        tabs.selectedIndex = 0
        spin(until: { PaymentInFlight.isActive })
        XCTAssertTrue(PaymentInFlight.isActive, "its tab is back: held")
        state.resultShown = false
        spin(until: { !PaymentInFlight.isActive })
        XCTAssertFalse(PaymentInFlight.isActive)
    }

    func testAWalletSendsPushedResultScreenOwnsRoutingWhileVisible() throws {
        let (root, _) = showMainScreen()
        let tabs = try XCTUnwrap(root.children.first as? UITabBarController)
        let navigation = try XCTUnwrap(tabs.viewControllers?.first as? UINavigationController)
        let result = SuccessfulOperationStatusViewController.initiate(from: sb("OperationStatus"))
        result.holdsExitsWhileShown = true
        navigation.pushViewController(result, animated: false)
        spin(until: { PaymentInFlight.isActive })
        XCTAssertTrue(PaymentInFlight.refusesTabChange(), "the transfer's result is up")
        XCTAssertEqual(navigation.interactivePopGestureRecognizer?.isEnabled, false, "its exits are held")

        navigation.popViewController(animated: false)
        spin(until: { !PaymentInFlight.isActive })
        XCTAssertFalse(PaymentInFlight.isActive, "closed")
        XCTAssertEqual(navigation.interactivePopGestureRecognizer?.isEnabled, true, "and given back")
    }

    func testACoinbaseAPITransfersResultScreenHoldsNothing() throws {
        let (root, _) = showMainScreen()
        let tabs = try XCTUnwrap(root.children.first as? UITabBarController)
        let navigation = try XCTUnwrap(tabs.viewControllers?.first as? UINavigationController)
        let result = SuccessfulOperationStatusViewController.initiate(from: sb("OperationStatus"))
        navigation.pushViewController(result, animated: false)
        spin(until: { result.view.window != nil })
        XCTAssertFalse(PaymentInFlight.isActive)
    }

    /// An unknown broadcast outcome fails the swap with no accepted txid, and
    /// the deposit may still settle: its pushed failure (More-menu entry, so
    /// nothing is presented) holds routing and the tab bar until it is left.
    func testASwapFailedByAnUnknownBroadcastOwnsRoutingUntilClosed() async throws {
        let unknownOutcome = Self.unknownBroadcastError
        XCTAssertTrue(WalletSendService.isBroadcastUnknownError(unknownOutcome))
        let deposit = FailingDeposit(error: unknownOutcome)
        let viewModel = makeSwapViewModel(providerQuote: Self.swapQuote, deposit: deposit)

        await viewModel.handlePrimaryAction()
        guard case .failed = viewModel.swapStatus else {
            return XCTFail("the unknown outcome is shown as a failure, got \(viewModel.swapStatus)")
        }
        XCTAssertEqual(deposit.attempts, 1, "the failure is the deposit's, not an earlier step's")
        XCTAssertNil(viewModel.submittedTxId, "an unknown broadcast leaves no accepted txid")
        XCTAssertFalse(PaymentInFlight.isActive, "the submission's own hold has ended")

        let (root, navigation, _) = try pushSwapStatus(for: viewModel)
        spin(until: { PaymentInFlight.isActive })
        XCTAssertTrue(PaymentInFlight.isActive, "the failure holds routing")
        XCTAssertTrue(PaymentInFlight.refusesTabChange())
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root))

        // Close pops the screen (its `onClose`); popping it directly stands in.
        navigation.popViewController(animated: false)
        spin(until: { !PaymentInFlight.isActive })
        XCTAssertFalse(PaymentInFlight.isActive, "leaving the screen releases it")
    }

    /// A Retry whose quote refresh fails leaves the unresolved deposit's
    /// failure on screen: it keeps holding.
    func testAFailedRetryKeepsAnUnknownDepositsFailureHeld() async throws {
        let unknownOutcome = Self.unknownBroadcastError
        XCTAssertTrue(WalletSendService.isBroadcastUnknownError(unknownOutcome))
        let provider = QuoteOnlySwapProvider(quote: Self.swapQuote)
        let viewModel = makeSwapViewModel(provider: provider, deposit: FailingDeposit(error: unknownOutcome))
        await viewModel.handlePrimaryAction()

        let (root, _, _) = try pushSwapStatus(for: viewModel)
        spin(until: { PaymentInFlight.isActive })
        XCTAssertTrue(PaymentInFlight.isActive)

        let depositFailure = viewModel.swapStatus

        // A quote the provider answers with an error, then one it throws on.
        provider.quote = SwapQuoteResult(
            error: "noRoutesFound", expectedAmountOut: nil, fees: nil,
            inboundAddress: nil, memo: nil, executionNetwork: nil)
        for attempt in ["answered with an error", "threw"] {
            if attempt == "threw" { provider.quoteError = URLError(.timedOut) }
            let retried = await viewModel.retryQuote()
            XCTAssertNil(retried, "the Retry \(attempt)")
            XCTAssertTrue(viewModel.failedAfterDepositAttempt, "the Retry \(attempt)")
            XCTAssertEqual("\(viewModel.swapStatus)", "\(depositFailure)", "the deposit failure's reason stays")
            spin(until: { !PaymentInFlight.isActive }, timeout: 0.3)
            XCTAssertTrue(PaymentInFlight.isActive, "the deposit's outcome is still unresolved")
            XCTAssertTrue(PaymentInFlight.refusesTabChange())
            XCTAssertTrue(PaymentInFlight.refusesLink(over: root))
        }
    }

    /// A quote failure before the deposit moved nothing: its pushed result
    /// holds nothing.
    func testASwapFailedBeforeItsDepositHoldsNothing() async throws {
        let failedQuote = SwapQuoteResult(
            error: "noRoutesFound", expectedAmountOut: nil, fees: nil,
            inboundAddress: nil, memo: nil, executionNetwork: nil)
        let deposit = FailingDeposit(error: NSError(domain: "test", code: 1))
        let viewModel = makeSwapViewModel(providerQuote: failedQuote, deposit: deposit)

        await viewModel.handlePrimaryAction()
        guard case .failed = viewModel.swapStatus else {
            return XCTFail("the quote error is shown as a failure, got \(viewModel.swapStatus)")
        }
        XCTAssertEqual(deposit.attempts, 0, "nothing was sent")

        let (root, _, status) = try pushSwapStatus(for: viewModel)
        spin(until: { status.view.window != nil })
        spin(until: { PaymentInFlight.isActive }, timeout: 0.3)
        XCTAssertFalse(PaymentInFlight.isActive, "the failure holds nothing")
        // Only the submission's own grace is left, and it runs out.
        spin(until: { !PaymentInFlight.isActiveOrSettling })
        XCTAssertFalse(PaymentInFlight.refusesTabChange())
        XCTAssertFalse(PaymentInFlight.refusesLink(over: root))
    }

    /// WalletSendService's broadcast-unknown error (its code type is fileprivate).
    private static let unknownBroadcastError = NSError(
        domain: "org.dashfoundation.dash.wallet-send-service",
        code: 10,
        userInfo: [NSLocalizedDescriptionKey: "Transaction status unknown"])

    private static let swapQuote = SwapQuoteResult(
        error: nil, expectedAmountOut: "100000", fees: nil,
        inboundAddress: "XvaultAddress", memo: nil, executionNetwork: "Test")

    private func makeSwapViewModel(
        providerQuote: SwapQuoteResult,
        deposit: SwapDepositSending
    ) -> OrderPreviewViewModel {
        makeSwapViewModel(provider: QuoteOnlySwapProvider(quote: providerQuote), deposit: deposit)
    }

    private func makeSwapViewModel(provider: QuoteOnlySwapProvider, deposit: SwapDepositSending) -> OrderPreviewViewModel {
        OrderPreviewViewModel(
            coin: SwapCryptoCurrency(id: "btc", code: "BTC", name: "Bitcoin", swapAsset: "BTC.BTC", chain: "BTC"),
            address: "bc1qdestination",
            dashSatoshis: 10_000_000,
            fromDashAmount: "0.1",
            fromFiatAmount: "",
            cryptoFiatRate: 0,
            fiatCurrencyCode: "USD",
            initialQuote: Self.swapQuote,
            swapProvider: provider,
            networkStatus: AlwaysOnline(),
            depositSender: deposit)
    }

    /// The swap status screen pushed inside a tab, as from the More menu.
    private func pushSwapStatus(
        for viewModel: OrderPreviewViewModel
    ) throws -> (root: UIViewController, navigation: UINavigationController, status: UIViewController) {
        let (root, _) = showMainScreen()
        let tabs = try XCTUnwrap(root.children.first as? UITabBarController)
        let navigation = try XCTUnwrap(tabs.viewControllers?.first as? UINavigationController)
        let status = SwapTransactionStatusHostingController(viewModel: viewModel)
        navigation.pushViewController(status, animated: false)
        return (root, navigation, status)
    }

    /// A send whose broadcast got no answer shows the "Waiting for the
    /// network" notice on the paying screen, and its delegate — which leaves
    /// that screen (the SwiftUI Send sheet closes to Home) — is told only once
    /// the notice has been closed and is gone. Until then the notice, a
    /// presented modal, keeps links refused.
    func testAnUnknownSendOutcomeShowsItsNoticeBeforeTheDelegateLeaves() throws {
        let (root, tabScreen) = showMainScreen()
        let delegate = UnknownOutcomeDelegate(anchor: tabScreen)
        let controller = PaymentController()
        controller.delegate = delegate
        controller.presentationContextProvider = delegate

        controller.paymentProcessor(DWPaymentProcessor(), didSendWithUnknownOutcomeTxidWire: Data(repeating: 0xab, count: 32))
        spin(until: { root.presentedViewController != nil })

        let notice = try XCTUnwrap(root.presentedViewController as? UIHostingController<ModalDialog>, "the notice is up")
        XCTAssertEqual(delegate.receivedCount, 1, "bookkeeping is told at once, before the notice is read")
        XCTAssertEqual(delegate.acknowledgements, [], "the delegate leaves only once the notice is closed")
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root), "the notice is a presented modal the router sees")

        notice.rootView.positiveButtonAction()
        spin(until: { !delegate.acknowledgements.isEmpty })
        XCTAssertEqual(delegate.acknowledgements, [false], "told once, with the notice already gone")
    }

    /// A notice UIKit does not present — here its screen is not in a window —
    /// still lets the paying screen go on: it is told at once.
    func testAnUnknownSendOutcomeWhoseNoticeCannotShowStillTellsTheDelegate() {
        let offScreen = UIViewController()
        let delegate = UnknownOutcomeDelegate(anchor: offScreen)
        let controller = PaymentController()
        controller.delegate = delegate
        controller.presentationContextProvider = delegate

        controller.paymentProcessor(DWPaymentProcessor(), didSendWithUnknownOutcomeTxidWire: Data(repeating: 0xcd, count: 32))

        XCTAssertEqual(delegate.receivedCount, 1)
        XCTAssertEqual(delegate.acknowledgements.count, 1, "never stranded waiting for a notice that is not there")
    }

    func testOnlyLinksThatReplaceTheScreenAreSubjectToTheRule() throws {
        func replacesScreen(_ className: String) throws -> Bool {
            let type = try XCTUnwrap(NSClassFromString(className) as? NSObject.Type, className)
            return try XCTUnwrap(type.init().value(forKey: "replacesScreen") as? Bool)
        }
        XCTAssertTrue(try replacesScreen("DWURLPayAction"))
        XCTAssertTrue(try replacesScreen("DWURLScanQRAction"))
        XCTAssertTrue(try replacesScreen("DWURLDashConnectAction"))
        XCTAssertFalse(try replacesScreen("DWURLIntegrationAction"), "a sign-in callback must not wait")
        XCTAssertFalse(try replacesScreen("DWURLRequestAction"), "an address request replaces nothing")
    }
}

private final class InlineResultState: ObservableObject {
    @Published var resultShown = false
}

private struct InlineResultScreen: View {
    @ObservedObject var state: InlineResultState

    var body: some View {
        ZStack {
            Text(verbatim: "Pay")
            if state.resultShown {
                Text(verbatim: "Purchase failed")
            }
        }
        .lockingExit(state.resultShown)
    }
}

private final class AlwaysOnline: NetworkStatusProviding {
    var currentStatus: NetworkStatus { .online }
    var isOnline: Bool { true }
    var statusPublisher: AnyPublisher<NetworkStatus, Never> { Just(.online).eraseToAnyPublisher() }
}

/// Answers every quote with `quote`, or throws `quoteError` when set; nothing
/// else is used by a swap submission.
private final class QuoteOnlySwapProvider: SwapProvider {
    var quote: SwapQuoteResult
    var quoteError: Error?
    var displayName: String { "Test" }
    var onBuyRoutabilityChanged: (() -> Void)?

    init(quote: SwapQuoteResult) { self.quote = quote }

    func fetchPools() async throws -> [SwapPool] { [] }
    func fetchInboundAddresses() async throws -> [SwapInboundAddress] { [] }
    func validateAddress(destination: String, toAsset: String) async -> String? { nil }
    func fetchQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult {
        if let quoteError { throw quoteError }
        return quote
    }
    func fetchSwapStatus(txid: String, depositAddress: String?) async throws -> SwapStatusResult {
        SwapStatusResult(error: nil, isObserved: false, observedStatus: nil, outHashes: nil)
    }
}

private final class FailingDeposit: SwapDepositSending {
    let error: Error
    private(set) var attempts = 0

    init(error: Error) { self.error = error }

    func sendSwapKitSwap(depositAddress: String, dashAmount: UInt64, memo: String?) async throws -> Data {
        attempts += 1
        throw error
    }
}

/// A paying screen that leaves once its unknown outcome was acknowledged.
private final class UnknownOutcomeDelegate: NSObject, PaymentControllerDelegate, PaymentControllerPresentationContextProviding {
    let anchor: UIViewController
    /// One entry per acknowledgement: whether anything was still presented.
    private(set) var acknowledgements: [Bool] = []
    private(set) var receivedCount = 0

    init(anchor: UIViewController) { self.anchor = anchor }

    func paymentControllerDidFinishTransaction(_ controller: PaymentController, txidWire: Data) {}
    func paymentControllerDidCancelTransaction(_ controller: PaymentController) {}
    func paymentControllerDidFailTransaction(_ controller: PaymentController) {}
    func paymentControllerDidReceiveUnknownOutcome(_ controller: PaymentController, txidWire: Data) {
        receivedCount += 1
    }

    func paymentControllerDidSubmitWithUnknownOutcome(_ controller: PaymentController, txidWire: Data) {
        acknowledgements.append(anchor.viewIfLoaded?.window?.rootViewController?.presentedViewController != nil)
    }

    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        anchor
    }
}

/// The legacy amount screen during a submission (its broadcast waits with the
/// UI live): a hardware keyboard edits nothing, and input comes back with the
/// outcome.
@MainActor
final class LegacyAmountSubmissionTests: XCTestCase {
    func testAHardwareEditDuringASubmissionChangesNothingAndInputReturnsWithTheOutcome() throws {
        let screen = ProvideAmountViewController(address: "yXdxAYfK8RZgCRp4Rb3aW6oJpQ6BzTDvVL", amount: 100_000)
        let previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        // Pushed, as the payment flow does.
        window.rootViewController = UINavigationController(rootViewController: screen)
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        screen.loadViewIfNeeded()
        let field = try XCTUnwrap(screen.amountView.amountInputControl.textField)
        let before = screen.model.amount.plainAmount
        let deadline = Date().addingTimeInterval(3)
        while !field.isFirstResponder, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(field.isFirstResponder, "the screen takes hardware input when it appears")

        screen.beginSubmission()
        XCTAssertFalse(field.isFirstResponder, "the hardware keyboard's responder is resigned")
        XCTAssertFalse(field.isEnabled)

        // What a hardware keystroke reaches if anything still routes it here.
        _ = field.delegate?.textField?(field, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "9")
        XCTAssertEqual(screen.model.amount.plainAmount, before, "the confirmed amount is what is sent")

        screen.viewDidAppear(false)
        XCTAssertFalse(field.isFirstResponder, "reappearing does not hand input back mid-submission")

        screen.hideActivityIndicator()
        XCTAssertTrue(field.isEnabled, "the outcome gives input back")
        XCTAssertTrue(field.isFirstResponder, "with the hardware keyboard's responder")
        _ = field.delegate?.textField?(field, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "9")
        XCTAssertNotEqual(screen.model.amount.plainAmount, before, "and edits apply again")
    }
}

/// The dialogs a payment waits on (the unknown-outcome notice, the
/// repeat-payment refusal) report their close exactly once, whatever happens
/// to them, and an unknown outcome keeps its txid for the caller.
@MainActor
final class PaymentDialogOutcomeTests: XCTestCase {
    private var window: UIWindow!
    private var previousKeyWindow: UIWindow?

    override func setUp() {
        super.setUp()
        previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
    }

    override func tearDown() {
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window = nil
        previousKeyWindow?.makeKey()
        super.tearDown()
    }

    private func spin(until condition: () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func present(on presenter: UIViewController, closed: @escaping () -> Void) {
        PaymentController.presentDialog(
            on: presenter, heading: "Previous payment still in progress", message: "…",
            buttonText: "OK", log: "test dialog", onClosed: closed)
    }

    func testADialogThatCannotBeShownReportsAtOnce() {
        var closes = 0
        present(on: UIViewController()) { closes += 1 }
        XCTAssertEqual(closes, 1, "a flow waiting on it goes on")
    }

    func testOKIsReportedOnceAfterTheDialogIsGone() throws {
        let root = try XCTUnwrap(window.rootViewController)
        var closes = 0
        var stillPresentedWhenReported: Bool?
        present(on: root) {
            closes += 1
            stillPresentedWhenReported = root.presentedViewController != nil
        }
        let dialog = try XCTUnwrap(root.presentedViewController as? UIHostingController<ModalDialog>)

        dialog.rootView.positiveButtonAction()
        dialog.rootView.positiveButtonAction()
        spin(until: { closes > 0 })
        spin(until: { false }, timeout: 0.3)
        XCTAssertEqual(closes, 1, "once, however often OK is tapped")
        XCTAssertEqual(stillPresentedWhenReported, false, "reported once the dialog is gone")
    }

    func testADialogTornDownIsReported() throws {
        let root = try XCTUnwrap(window.rootViewController)
        var closes = 0
        present(on: root) { closes += 1 }
        spin(until: { root.presentedViewController?.isBeingPresented == false })
        root.dismiss(animated: false)
        spin(until: { closes > 0 })
        XCTAssertEqual(closes, 1)
    }

    /// Paying an address whose previous payment is still waiting for the
    /// network is refused: the notice is shown, nothing goes on to the PIN
    /// prompt or the build, and OK returns to the paying screen.
    func testARepeatPaymentIsRefusedWithANoticeAndOKReturns() throws {
        let root = try XCTUnwrap(window.rootViewController)
        // Held to the end: the controller keeps its anchor weakly.
        let anchor = AnchorProvider(anchor: root)
        defer { withExtendedLifetime(anchor) { } }
        let controller = PaymentController()
        controller.presentationContextProvider = anchor
        let waiting = PendingSendOutcomes.Entry(
            txidWire: Data(repeating: 0x9c, count: 32), walletId: Data(repeating: 0x1d, count: 32),
            address: "yAddressForTests", amount: 100_000, sentAt: Date())
        controller.waitingPayment = { $0.contains("yAddressForTests") ? waiting : nil }
        var logged: [String] = []
        controller.log = { logged.append($0) }

        var answers: [Bool] = []
        controller.paymentProcessor(DWPaymentProcessor(), shouldPayAddresses: ["yAddressForTests"], isBIP70: true) { answers.append($0) }
        let notice = try XCTUnwrap(root.presentedViewController as? UIHostingController<ModalDialog>, "the notice is up")
        XCTAssertEqual(answers, [], "nothing goes on while it is up")
        XCTAssertNil(notice.rootView.negativeButtonText, "a single OK, no way to send anyway")
        XCTAssertNotNil(notice.rootView.textBlock2, "says how to get past a payment that never arrives")
        XCTAssertEqual(logged.count, 1)
        let shown = try XCTUnwrap(logged.first)
        XCTAssertTrue(shown.contains("TXSEND") && shown.contains("route=BIP70"), shown)
        XCTAssertTrue(shown.contains("pending=\(PendingSendOutcomes.shortTxid(waiting.txidWire))"), shown)
        XCTAssertTrue(shown.contains("wallet=1d1d1d1d"), shown)
        XCTAssertTrue(shown.contains("within the \(PendingSendOutcomes.maxFollowDays)-day window"), shown)
        XCTAssertFalse(shown.contains("yAddressForTests"), "never the full address")

        notice.rootView.positiveButtonAction()
        spin(until: { !answers.isEmpty })
        XCTAssertEqual(answers, [false], "OK returns without paying")
        XCTAssertEqual(logged.count, 2)
        XCTAssertTrue(logged.last?.contains("cancelled on OK") == true, logged.last ?? "")

        var other: [Bool] = []
        controller.paymentProcessor(DWPaymentProcessor(), shouldPayAddresses: ["yOtherAddress"], isBIP70: false) { other.append($0) }
        XCTAssertEqual(other, [true], "another address is not interrupted")
        XCTAssertEqual(logged.count, 2, "nothing pending: no log")
    }

    /// A BIP70 request is asked about with every recipient: one whose earlier
    /// payment waits in a non-first output refuses the whole request, and the
    /// log names that recipient (shortened), not the first one.
    func testARequestIsRefusedForAPendingRecipientThatIsNotItsFirst() throws {
        let root = try XCTUnwrap(window.rootViewController)
        let anchor = AnchorProvider(anchor: root)
        defer { withExtendedLifetime(anchor) { } }
        let controller = PaymentController()
        controller.presentationContextProvider = anchor
        let pending = "yPendingRecipientAddressForTests"
        // The waiting payment itself paid two recipients, `pending` second.
        let waiting = PendingSendOutcomes.Entry(
            txidWire: Data(repeating: 0x9d, count: 32), walletId: Data(repeating: 0x1d, count: 32),
            address: "yEarlierFirstRecipientForTests", otherAddresses: [pending], amount: 123_400_000, sentAt: Date())
        var asked: [[String]] = []
        controller.waitingPayment = { addresses in
            asked.append(addresses)
            return addresses.contains(pending) ? waiting : nil
        }
        var logged: [String] = []
        controller.log = { logged.append($0) }

        var answers: [Bool] = []
        controller.paymentProcessor(
            DWPaymentProcessor(), shouldPayAddresses: ["yFirstRecipientAddressForTests", pending], isBIP70: true
        ) { answers.append($0) }

        XCTAssertEqual(asked, [["yFirstRecipientAddressForTests", pending]], "every recipient is checked")
        let notice = try XCTUnwrap(root.presentedViewController as? UIHostingController<ModalDialog>, "refused")
        XCTAssertEqual(answers, [])
        let text = try XCTUnwrap(notice.rootView.textBlock1)
        XCTAssertFalse(text.contains(waiting.amount.formattedDashAmount),
                       "the whole payment's amount is not what this address was paid: \(text)")
        let shown = try XCTUnwrap(logged.first)
        XCTAssertTrue(shown.contains("to=\(PendingSendOutcomes.masked(pending))"), shown)
        XCTAssertFalse(shown.contains(pending), "never the full address")
        notice.rootView.positiveButtonAction()
        spin(until: { !answers.isEmpty })
        XCTAssertEqual(answers, [false])
    }

    func testAnUnknownOutcomeErrorCarriesItsTxid() {
        let txidWire = Data(repeating: 0x7e, count: 32)
        defer { PendingSendOutcomes.shared.forget(txidsWire: [txidWire]) }
        let error = WalletSendService.unknownOutcomeError(txidWire: txidWire, address: nil, amount: 1, reason: "timeout", origin: nil)
        XCTAssertTrue(WalletSendService.isBroadcastUnknownError(error))
        XCTAssertEqual(WalletSendService.unknownOutcomeTxidWire(of: error), txidWire)
        XCTAssertNil(WalletSendService.unknownOutcomeTxidWire(of: NSError(domain: "other", code: 10)))
    }
}

/// `PendingSendOutcomes`' settlement policy: when a waiting send settles,
/// expires or is dropped, and how its notices merge — without a store,
/// clock or SDK.
final class PendingSendSettlementPolicyTests: XCTestCase {
    private typealias Policy = PendingSendOutcomes
    private let walletA = Data(repeating: 0xa1, count: 32)
    private let walletB = Data(repeating: 0xb2, count: 32)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// The chain the entries and reads of these tests are on unless they say
    /// otherwise.
    private let chain = "testnet"
    private var scopeA: WalletChainScope { WalletChainScope(walletId: walletA, chain: chain) }
    private var scopeB: WalletChainScope { WalletChainScope(walletId: walletB, chain: chain) }

    /// - Parameter chain: the chain the send was signed on; `.some(nil)` is
    ///   an entry stored before the chain was kept.
    private func entry(
        _ byte: UInt8, wallet: Data? = nil, chain: String?? = nil, age: TimeInterval, amount: UInt64 = 1_000,
        notifies: Bool? = nil
    ) -> PendingSendOutcomes.Entry {
        PendingSendOutcomes.Entry(
            txidWire: Data(repeating: byte, count: 32), walletId: wallet ?? walletA, address: "yAddress",
            amount: amount, sentAt: now.addingTimeInterval(-age), notifies: notifies,
            chainScope: chain ?? self.chain)
    }

    private func decide(
        _ entries: [PendingSendOutcomes.Entry],
        rows: [Data: Policy.RowState]?,
        wallet: Data? = nil,
        chain: String? = nil,
        followed: Set<Data>? = nil
    ) -> Policy.SettlementDecision {
        let pending = Dictionary(uniqueKeysWithValues: entries.map { ($0.txidWire, $0) })
        let followedNow = followed ?? Set(pending.keys)
        return Policy.settlement(
            of: pending, stillFollowed: { followedNow.contains($0) },
            readFrom: WalletChainScope(walletId: wallet ?? walletA, chain: chain ?? self.chain), rows: rows, now: now)
    }

    func testAnAcceptedVerdictRereadsButAProcessingRowKeepsTheSendWaiting() {
        let sent = entry(1, age: 60)
        let heard = Policy.acceptances(
            in: [(txidWire: sent.txidWire, walletId: walletA, accepted: true)],
            from: scopeA, following: [sent.txidWire: sent], alreadyHeard: [])
        XCTAssertEqual(heard.accepted, [sent.txidWire])
        XCTAssertTrue(heard.isNew, "the rows are read again")

        let decision = decide([sent], rows: [sent.txidWire: .processing])
        XCTAssertTrue(decision.isEmpty, "a node holding the bytes is not a settled payment")
    }

    func testAnAcceptanceIsActedOnOnceAndOnlyFromTheSendsOwnWallet() {
        let sent = entry(1, age: 60)
        let again = Policy.acceptances(
            in: [(txidWire: sent.txidWire, walletId: walletA, accepted: true)],
            from: scopeA, following: [sent.txidWire: sent], alreadyHeard: [sent.txidWire])
        XCTAssertFalse(again.isNew, "republished, not new")

        let otherWallet = Policy.acceptances(
            in: [(txidWire: sent.txidWire, walletId: walletB, accepted: true)],
            from: scopeB, following: [sent.txidWire: sent], alreadyHeard: [])
        XCTAssertTrue(otherWallet.accepted.isEmpty)
        XCTAssertFalse(otherWallet.isNew)
    }

    func testAFailedReadDecidesNothing() {
        let old = entry(1, age: Policy.missingRowGrace + 3600)
        XCTAssertTrue(decide([old], rows: nil).isEmpty, "a failed read is not \"the row is gone\"")
        let stale = entry(2, age: Policy.maxFollowAge + 3600)
        XCTAssertTrue(decide([stale], rows: nil).isEmpty, "nor \"unconfirmed\": it may have settled, the next read tells")
    }

    func testALockedOrMinedRowSettlesTheSendAndNotifiesOnce() {
        let sent = entry(1, age: 60, amount: 2_500)
        let followed = [sent.txidWire: sent]
        let decision = Policy.settlement(
            of: followed, stillFollowed: { followed[$0] != nil },
            readFrom: scopeA, rows: [sent.txidWire: .settled], now: now)
        XCTAssertEqual(decision.settled, [sent.txidWire])
        XCTAssertEqual(decision.notifying, [sent])

        // Applied, the send is no longer followed, so the next read of the
        // same rows neither settles it again nor notifies again.
        let remaining = Policy.applying(decision, to: followed)
        XCTAssertTrue(remaining.isEmpty)
        let again = Policy.settlement(
            of: followed, stillFollowed: { remaining[$0] != nil },
            readFrom: scopeA, rows: [sent.txidWire: .settled], now: now)
        XCTAssertTrue(again.isEmpty)
    }

    func testASendForgottenWhileTheRowsWereReadNeitherSettlesNorNotifies() {
        let sent = entry(1, age: 60)
        let decision = decide([sent], rows: [sent.txidWire: .settled], followed: [])
        XCTAssertTrue(decision.isEmpty, "removed or wiped during the read")
    }

    func testOnlyTheReadWalletsSendsAreDecided() {
        let mine = entry(1, wallet: walletA, age: 60)
        let theirs = entry(2, wallet: walletB, age: Policy.maxFollowAge + 1)
        let decision = decide([mine, theirs], rows: [mine.txidWire: .settled, theirs.txidWire: .processing], wallet: walletA)
        XCTAssertEqual(decision.settled, [mine.txidWire])
        XCTAssertTrue(decision.expired.isEmpty, "the other wallet's send is left alone")

        // After a switch to B, B's rows decide B's send only: A's settled
        // send is not touched by B's read.
        let switched = decide([mine, theirs], rows: [mine.txidWire: .settled], wallet: walletB)
        XCTAssertTrue(switched.settled.isEmpty, "after a switch, only the new wallet's sends are read")
        XCTAssertEqual(switched.gone, [theirs.txidWire], "B's own send, missing past the grace, is B's to drop")
    }

    func testTheQuietWindowBoundary() {
        let atWindow = entry(1, age: Policy.quietSettleWindow)
        let past = entry(2, age: Policy.quietSettleWindow + 0.001)
        let decision = decide([atWindow, past], rows: [atWindow.txidWire: .settled, past.txidWire: .settled])
        XCTAssertEqual(Set(decision.settled), [atWindow.txidWire, past.txidWire], "both settle")
        XCTAssertEqual(decision.notifying, [past], "only the one past the quiet window is told")
    }

    func testASendThatIsNotAPaymentSettlesWithoutANotice() {
        let sweep = entry(1, age: 60, notifies: false)
        let decision = decide([sweep], rows: [sweep.txidWire: .settled])
        XCTAssertEqual(decision.settled, [sweep.txidWire])
        XCTAssertTrue(decision.notifying.isEmpty)
    }

    func testTheMissingRowGraceBoundary() {
        let atGrace = entry(1, age: Policy.missingRowGrace)
        let past = entry(2, age: Policy.missingRowGrace + 1)
        let decision = decide([atGrace, past], rows: [:])
        XCTAssertEqual(decision.gone, [past.txidWire], "a missing row is gone only after the grace")
        XCTAssertTrue(decision.notifying.isEmpty)
    }

    func testTheMaxFollowAgeBoundary() {
        let atLimit = entry(1, age: Policy.maxFollowAge)
        let past = entry(2, age: Policy.maxFollowAge + 1)
        let decision = decide([atLimit, past], rows: [atLimit.txidWire: .processing, past.txidWire: .processing])
        XCTAssertEqual(decision.expired, [past.txidWire], "still unconfirmed after a week: no longer followed")
    }

    /// Wallet A's send settles after the switch to B (its read finished
    /// late): B's Home tells nothing.
    func testASettlementForAnotherWalletShowsNothingOnTheShownOne() {
        let sentFromA = entry(1, wallet: walletA, age: 60)
        let decision = decide([sentFromA], rows: [sentFromA.txidWire: .settled], wallet: walletA)
        XCTAssertEqual(decision.notifying, [sentFromA], "A's send settled")
        XCTAssertTrue(Policy.notifiable(decision.notifying, shown: scopeB).isEmpty, "no toast on B's Home")
        XCTAssertTrue(Policy.notifiable(decision.notifying, shown: nil).isEmpty, "none during a switch")
        XCTAssertEqual(Policy.notifiable(decision.notifying, shown: scopeA), [sentFromA])
    }

    /// A notice is the shown wallet's: publishing another wallet drops it, a
    /// rebuild of the same wallet keeps it.
    func testASwitchDropsTheShownNoticeAndARebuildKeepsIt() {
        let notice = Policy.merged(nil, adding: 1_000)
        XCTAssertNil(Policy.noticeKept(notice, shown: scopeA, published: scopeB), "switched to B")
        XCTAssertNil(Policy.noticeKept(notice, shown: scopeA, published: nil))
        XCTAssertEqual(Policy.noticeKept(notice, shown: scopeA, published: scopeA), notice, "A rebuilt")
    }

    func testNoticesMergeOnlyWithinTheShownWallet() {
        let settled = [
            entry(1, wallet: walletA, age: 60, amount: 1_000),
            entry(2, wallet: walletB, age: 60, amount: 5_000),
            entry(3, wallet: walletA, age: 60, amount: 2_000),
        ]
        var notice: PendingSendOutcomes.Notice?
        for entry in Policy.notifiable(settled, shown: scopeA) {
            notice = Policy.merged(notice, adding: entry.amount)
        }
        XCTAssertEqual(notice?.count, 2)
        XCTAssertEqual(notice?.total, 3_000, "B's payment is not added to A's total")
    }

    // MARK: One wallet id, several chains

    /// The same seed has the same wallet id on every devnet, and each devnet
    /// has its own transaction store. A send followed on devnet A has no row
    /// in devnet B's store, ever: a read of B's store, with the send over a
    /// day old, must not drop it as gone.
    func testAMissingRowOnAnotherDevnetCannotRemoveAFollowedSend() {
        let sentOnA = entry(1, chain: "devnet-a", age: Policy.missingRowGrace + 3600)
        XCTAssertTrue(decide([sentOnA], rows: [:], chain: "devnet-b").isEmpty,
                      "devnet B's store says nothing about a devnet A send")
        XCTAssertEqual(decide([sentOnA], rows: [:], chain: "devnet-a").gone, [sentOnA.txidWire],
                       "its own store's missing row still does")

        // Nor is it aged out, or settled, by anything read on B.
        let old = entry(2, chain: "devnet-a", age: Policy.maxFollowAge + 3600)
        XCTAssertTrue(decide([old], rows: [:], chain: "devnet-b").isEmpty)
        XCTAssertTrue(decide([old], rows: [old.txidWire: .settled], chain: "devnet-b").isEmpty)
        XCTAssertEqual(Policy.applying(decide([sentOnA, old], rows: [:], chain: "devnet-b"),
                                       to: [sentOnA.txidWire: sentOnA, old.txidWire: old]).count, 2,
                       "back on A, both are still followed")
    }

    /// A send waiting on one chain refuses nothing on another chain of the
    /// same wallet id, and its settlement is not told there. Two devnets are
    /// the real case (one wallet id, one address format). A seed's testnet
    /// and mainnet ids differ in practice, so those are different wallets
    /// already; the pairs are here to show the rule does not lean on that.
    func testASendWaitingOnOneChainRefusesAndTellsNothingOnAnother() {
        for (signedOn, other) in [("devnet-a", "devnet-b"), ("testnet", "mainnet"), ("testnet", "devnet-a")] {
            let sent = entry(1, chain: signedOn, age: 60, amount: 2_500)
            let entries = [sent.txidWire: sent]
            let here = WalletChainScope(walletId: walletA, chain: signedOn)
            let there = WalletChainScope(walletId: walletA, chain: other)

            XCTAssertEqual(Policy.refusing(["yAddress"], on: here, in: entries, now: now), sent, signedOn)
            XCTAssertNil(Policy.refusing(["yAddress"], on: there, in: entries, now: now),
                         "\(signedOn) send refusing on \(other)")

            let settled = Policy.settlement(
                of: entries, stillFollowed: { _ in true }, readFrom: here, rows: [sent.txidWire: .settled], now: now)
            XCTAssertEqual(settled.notifying, [sent])
            XCTAssertEqual(Policy.notifiable(settled.notifying, shown: here), [sent])
            XCTAssertTrue(Policy.notifiable(settled.notifying, shown: there).isEmpty,
                          "\(signedOn) settlement told on \(other)")

            let notice = Policy.merged(nil, adding: sent.amount)
            XCTAssertNil(Policy.noticeKept(notice, shown: here, published: there),
                         "a notice does not follow the wallet to \(other)")
            XCTAssertEqual(Policy.noticeKept(notice, shown: here, published: here), notice)
        }
    }

    /// An entry stored before the chain was kept has no chain, and none is
    /// made up for it. A row found for it settles (or keeps, or expires) it —
    /// a row found here is on this chain. A missing row never drops it as
    /// gone, since it may be waiting on another chain; it ages out instead.
    /// Until then it refuses on every chain of its wallet.
    func testAnEntryStoredWithoutItsChainIsNeverDroppedByAMissingRow() throws {
        let legacy = entry(1, chain: .some(nil), age: Policy.missingRowGrace + 3600, amount: 4_000)
        XCTAssertNil(legacy.chainScope)
        for chain in ["devnet-a", "devnet-b", "mainnet"] {
            XCTAssertTrue(decide([legacy], rows: [:], chain: chain).isEmpty, "not gone on \(chain)")
            XCTAssertEqual(
                Policy.refusing(["yAddress"], on: WalletChainScope(walletId: walletA, chain: chain),
                                in: [legacy.txidWire: legacy], now: now),
                legacy, "refuses on \(chain): it may be this chain's")
        }
        XCTAssertNil(Policy.refusing(["yAddress"], on: scopeB, in: [legacy.txidWire: legacy], now: now),
                     "another wallet's")

        let found = decide([legacy], rows: [legacy.txidWire: .settled], chain: "devnet-a")
        XCTAssertEqual(found.settled, [legacy.txidWire])
        XCTAssertEqual(found.notifying, [legacy], "told where its row was found")

        let aged = entry(2, chain: .some(nil), age: Policy.maxFollowAge + 3600)
        let agedOut = decide([aged], rows: [:], chain: "devnet-b")
        XCTAssertEqual(agedOut.unplaced, [aged.txidWire], "ages out, read or not found")
        XCTAssertTrue(agedOut.gone.isEmpty && agedOut.expired.isEmpty && agedOut.notifying.isEmpty)
        XCTAssertNil(Policy.applying(agedOut, to: [aged.txidWire: aged])[aged.txidWire])
        XCTAssertEqual(decide([aged], rows: [aged.txidWire: .processing], chain: "devnet-b").expired, [aged.txidWire])

        // What such an entry looks like on disk: no chain key.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry(3, age: 60))) as? [String: Any])
        XCTAssertEqual(json["chainScope"] as? String, chain, "new entries store their chain")
        json.removeValue(forKey: "chainScope")
        let decoded = try JSONDecoder().decode(
            PendingSendOutcomes.Entry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.chainScope)
    }

    /// On mainnet and testnet a wallet id belongs to that one chain, so an
    /// entry stored without its chain is that chain's: it is given it, and
    /// the ordinary rules apply (a row missing for a day drops it). On a
    /// devnet nothing is filled in.
    func testAnUnchainedEntryIsPlacedOnlyWhereItsWalletIdIsOfOneChain() {
        let legacy = entry(1, chain: .some(nil), age: Policy.missingRowGrace + 3600)
        let others = entry(2, wallet: walletB, chain: .some(nil), age: 60)
        let entries = [legacy.txidWire: legacy, others.txidWire: others]
        let testnet = WalletChainScope(walletId: walletA, chain: "testnet")

        let placed = Policy.placingUnchained(entries, on: testnet, walletIdIsOfOneChain: true)
        XCTAssertEqual(placed[legacy.txidWire]?.chainScope, "testnet")
        XCTAssertNil(placed[others.txidWire]?.chainScope, "another wallet's entry is not this chain's")
        let decision = Policy.settlement(
            of: placed, stillFollowed: { _ in true }, readFrom: testnet, rows: [:], now: now)
        XCTAssertEqual(decision.gone, [legacy.txidWire], "placed, it follows the ordinary missing-row rule")

        let devnet = WalletChainScope(walletId: walletA, chain: "devnet-a")
        XCTAssertEqual(Policy.placingUnchained(entries, on: devnet, walletIdIsOfOneChain: false), entries,
                       "on a devnet the id is every devnet's: nothing is filled in")
    }

    func testAVerdictFromAnotherChainsManagerIsNotHeard() {
        let sentOnA = entry(1, chain: "devnet-a", age: 60)
        let verdict = [(txidWire: sentOnA.txidWire, walletId: walletA, accepted: true)]
        let onB = Policy.acceptances(
            in: verdict, from: WalletChainScope(walletId: walletA, chain: "devnet-b"),
            following: [sentOnA.txidWire: sentOnA], alreadyHeard: [])
        XCTAssertTrue(onB.accepted.isEmpty)
        let onA = Policy.acceptances(
            in: verdict, from: WalletChainScope(walletId: walletA, chain: "devnet-a"),
            following: [sentOnA.txidWire: sentOnA], alreadyHeard: [])
        XCTAssertEqual(onA.accepted, [sentOnA.txidWire])
    }

    // MARK: Several recipients (BIP70)

    private func multi(_ byte: UInt8, _ primary: String, others: [String], wallet: Data? = nil, age: TimeInterval = 60)
        -> PendingSendOutcomes.Entry {
        PendingSendOutcomes.Entry(
            txidWire: Data(repeating: byte, count: 32), walletId: wallet ?? walletA, address: primary,
            otherAddresses: Policy.distinctOthers(others, primary: primary),
            amount: 5_000, sentAt: now.addingTimeInterval(-age), chainScope: chain)
    }

    /// A followed payment to [B, A] refuses a later plain payment to A, its
    /// second recipient, as well as one to B.
    func testAPlainPaymentToAFollowedNonFirstRecipientIsRefused() {
        let sent = multi(1, "yB", others: ["yA"])
        let entries = [sent.txidWire: sent]
        XCTAssertEqual(Policy.refusing(["yA"], on: scopeA, in: entries, now: now), sent)
        XCTAssertEqual(Policy.refusing(["yB"], on: scopeA, in: entries, now: now), sent)
        XCTAssertNil(Policy.refusing(["yC"], on: scopeA, in: entries, now: now))
        XCTAssertNil(Policy.refusing(["yA"], on: scopeB, in: entries, now: now), "another wallet's send")
    }

    /// A request paying [B, A] is refused while a payment to A is followed:
    /// the pending address need not be the request's first output.
    func testARequestWithThePendingAddressInANonFirstOutputIsRefused() {
        let sent = entry(1, age: 60)  // a plain payment to "yAddress"
        let entries = [sent.txidWire: sent]
        XCTAssertEqual(Policy.refusing(["yB", "yAddress"], on: scopeA, in: entries, now: now), sent)
        XCTAssertNil(Policy.refusing(["yB", "yC"], on: scopeA, in: entries, now: now))
    }

    func testASeveralRecipientSendStopsRefusingEveryRecipientByAge() {
        let stale = multi(1, "yB", others: ["yA"], age: Policy.maxFollowAge + 60)
        XCTAssertNil(Policy.refusing(["yA"], on: scopeA, in: [stale.txidWire: stale], now: now))
        XCTAssertNil(Policy.refusing(["yB"], on: scopeA, in: [stale.txidWire: stale], now: now))
    }

    /// One transaction is one followed send however many addresses it pays:
    /// it settles once, raises one notice of its whole amount, and its log
    /// line lists each address once.
    func testASeveralRecipientSendCountsOnce() {
        let sent = multi(1, "yRecipientB00000", others: ["yRecipientA00000", "yRecipientB00000", "", "yRecipientA00000"])
        XCTAssertEqual(sent.otherAddresses, ["yRecipientA00000"], "no repeats, no primary, no empty address")
        XCTAssertEqual(sent.addresses, ["yRecipientB00000", "yRecipientA00000"])

        let decision = decide([sent], rows: [sent.txidWire: .settled])
        XCTAssertEqual(decision.settled, [sent.txidWire])
        XCTAssertEqual(decision.notifying, [sent])
        let notice = Policy.merged(nil, adding: sent.amount)
        XCTAssertEqual(notice.count, 1)
        XCTAssertEqual(notice.total, 5_000)

        let lifted = Policy.refusalLifted(for: sent.addresses)
        XCTAssertEqual(lifted.components(separatedBy: "yRec…").count - 1, 2, lifted)
        XCTAssertFalse(lifted.contains("yRecipientA00000"), "never a full address")
    }

    /// An entry stored before several recipients were kept still decodes,
    /// and pays its one address.
    func testAnEntryStoredWithoutOtherAddressesStillDecodes() throws {
        let old = entry(1, age: 60)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "otherAddresses")
        json.removeValue(forKey: "notifies")
        let decoded = try JSONDecoder().decode(
            PendingSendOutcomes.Entry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.otherAddresses)
        XCTAssertEqual(decoded.addresses, ["yAddress"])
    }

    func testNoticesMergeAndTheTotalSaturates() {
        let first = Policy.merged(nil, adding: 1_000)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.total, 1_000)

        let second = Policy.merged(first, adding: 2_000)
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(second.total, 3_000)
        XCTAssertNotEqual(second.id, first.id, "a merge is a new notice, shown for its full window")

        let saturated = Policy.merged(second, adding: UInt64.max)
        XCTAssertEqual(saturated.count, 3)
        XCTAssertEqual(saturated.total, UInt64.max)
    }
}

/// A send's unknown outcome is followed under the wallet it was prepared for,
/// even when another wallet is active (or none) by the time it arrives — the
/// detached CTX broadcast's case.
@MainActor
final class UnknownOutcomeWalletTests: XCTestCase {
    /// The test host has no active wallet: this pins that the given wallet is
    /// used rather than the active one (or none).
    func testAnOutcomeIsFollowedUnderTheWalletThatSentItNotTheActiveOne() throws {
        let sentFrom = Data(repeating: 0x5c, count: 32)
        let txidWire = Data(repeating: 0x6d, count: 32)
        defer { PendingSendOutcomes.shared.forget(txidsWire: [txidWire], reason: "test send") }
        XCTAssertNotEqual(SwiftDashSDKHost.shared.wallet?.walletId, sentFrom, "another wallet (or none) is active")

        let shownNow = WalletSendService.followUnknownOutcome(
            txidWire: txidWire, address: "yAddress", amount: 1_000,
            origin: WalletChainScope(walletId: sentFrom, chain: "devnet-a"))

        XCTAssertEqual(PendingSendOutcomes.shared.entries[txidWire]?.walletId, sentFrom, "followed under its wallet")
        XCTAssertEqual(PendingSendOutcomes.shared.entries[txidWire]?.chainScope, "devnet-a", "and its chain")
        XCTAssertFalse(shownNow, "not the active wallet: no row on screen to point the user at")
    }

    /// An outcome names its wallet and chain together; one signed on another
    /// chain of a wallet is not "on screen" for that wallet's other chains.
    func testAnOutcomeIsFollowedUnderTheChainThatSignedIt() {
        let wallet = Data(repeating: 0x5d, count: 32)
        let txidWire = Data(repeating: 0x6f, count: 32)
        defer { PendingSendOutcomes.shared.forget(txidsWire: [txidWire], reason: "test send") }

        WalletSendService.followUnknownOutcome(
            txidWire: txidWire, address: "yAddress", amount: 1_000,
            origin: WalletChainScope(walletId: wallet, chain: "devnet-a"))

        let entries = PendingSendOutcomes.shared.entries
        XCTAssertEqual(
            PendingSendOutcomes.refusing(
                ["yAddress"], on: WalletChainScope(walletId: wallet, chain: "devnet-a"), in: entries, now: Date())?.txidWire,
            txidWire)
        XCTAssertNil(PendingSendOutcomes.refusing(
            ["yAddress"], on: WalletChainScope(walletId: wallet, chain: "devnet-b"), in: entries, now: Date()))
    }

    /// The plain-send route: the prepared send carries the signing wallet,
    /// and its unknown outcome is booked under it.
    func testAPreparedSendsUnknownOutcomeIsBookedUnderItsSigningWallet() {
        let signedBy = Data(repeating: 0x7a, count: 32)
        let send = PreparedStandardSend(
            txData: Data([0x01]), txHash: Data(repeating: 0x8b, count: 32), fee: 226,
            address: "yAddress", amount: 1_000, origin: WalletChainScope(walletId: signedBy, chain: "devnet-a"),
            broadcastAction: { .unknown(txid: String(repeating: "8b", count: 32), reason: "no answer") })
        defer { PendingSendOutcomes.shared.forget(txidsWire: [send.txidWire], reason: "test send") }

        XCTAssertThrowsError(try send.broadcast()) { error in
            XCTAssertTrue(WalletSendService.isBroadcastUnknownError(error as NSError))
            XCTAssertFalse(WalletSendService.isFollowedUnknownOutcomeError(error as NSError),
                           "its wallet is not on screen: told with the error's own copy")
        }
        XCTAssertEqual(PendingSendOutcomes.shared.entries[send.txidWire]?.walletId, signedBy)
        XCTAssertEqual(PendingSendOutcomes.shared.entries[send.txidWire]?.chainScope, "devnet-a")
    }

    /// A several-recipient payment whose outcome is unknown is one followed
    /// send that keeps every address it paid.
    func testAnUnknownOutcomeKeepsEveryRecipientUnderOneSend() {
        let sentFrom = Data(repeating: 0x5c, count: 32)
        let txidWire = Data(repeating: 0x6e, count: 32)
        defer { PendingSendOutcomes.shared.forget(txidsWire: [txidWire], reason: "test send") }
        let before = PendingSendOutcomes.shared.entries.count

        let error = WalletSendService.unknownOutcomeError(
            txidWire: txidWire, address: "yFirst", otherAddresses: ["yFirst", "ySecond", "yFirst"], amount: 3_000,
            reason: "no answer", origin: WalletChainScope(walletId: sentFrom, chain: "testnet"))

        XCTAssertTrue(WalletSendService.isBroadcastUnknownError(error))
        XCTAssertEqual(PendingSendOutcomes.shared.entries.count, before + 1, "one send, not one per address")
        let followed = PendingSendOutcomes.shared.entries[txidWire]
        XCTAssertEqual(followed?.addresses, ["yFirst", "ySecond"])
        XCTAssertEqual(followed?.amount, 3_000)
        XCTAssertEqual(
            PendingSendOutcomes.refusing(
                ["ySecond"], on: WalletChainScope(walletId: sentFrom, chain: "testnet"),
                in: PendingSendOutcomes.shared.entries, now: Date())?.txidWire,
            txidWire, "a plain payment to the second recipient is refused")
    }

    /// The BIP70 layer hands the payment's addresses out with an unknown
    /// outcome, awaited or handed off: every recipient, then the address of
    /// the URI the request came from (what a plain send falls back to when
    /// the request cannot be fetched), each once.
    func testABIP70UnknownOutcomeCarriesEveryRecipientAndTheURIsAddress() async throws {
        let wallet = DetachedUnknownWallet(walletId: Data(repeating: 0x3e, count: 32))
        let service = BIP70PaymentService(
            transport: AcknowledgingTransport(extraOutputs: 1), wallet: wallet,
            receiveAddress: StaticReceiveAddress(), auth: NoAuth())
        let url = URL(string: "http://merchant/pr")!
        // A payable testnet address none of the request's outputs pays.
        let uriAddress = try XCTUnwrap(ScriptAddressCodec.resolveOutputs(
            [PaymentOutput(amount: 1, script: Data([0x76, 0xa9, 0x14] + [UInt8](repeating: 0x77, count: 20) + [0x88, 0xac]))],
            network: .testnet).first?.address)
        let confirmation = try await service.prepareForConfirmation(
            from: url, scheme: "dash", network: .testnet, fallbackAddress: uriAddress)
        let recipients = confirmation.recipients.map(\.address)
        XCTAssertEqual(recipients.count, 2)
        let addresses = confirmation.repeatCheckAddresses
        XCTAssertEqual(addresses, recipients + [uriAddress], "what the repeat-payment check is asked about")

        do {
            _ = try await service.confirmAndSend(confirmation)
            XCTFail("the broadcast got no answer")
        } catch BIP70Error.broadcastOutcomeUnknown(_, _, _, let carried) {
            XCTAssertEqual(carried, addresses, "the awaited broadcast")
        }

        let reported = expectation(description: "the handed-off broadcast reports")
        var detached: [String] = []
        service.onDetachedBroadcastUnknown = { _, _, addresses, _, _ in
            detached = addresses
            reported.fulfill()
        }
        let again = try await service.prepareForConfirmation(
            from: url, scheme: "dash", network: .testnet, fallbackAddress: uriAddress)
        _ = try await service.confirmAndSend(again, awaitAcceptance: false)
        await fulfillment(of: [reported], timeout: 3)
        XCTAssertEqual(detached, addresses, "the handed-off broadcast")

        // The URI's address repeated among the recipients, or absent: each once.
        let same = try await service.prepareForConfirmation(
            from: url, scheme: "dash", network: .testnet, fallbackAddress: recipients[0])
        XCTAssertEqual(same.repeatCheckAddresses, recipients)
        let none = try await service.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        XCTAssertEqual(none.repeatCheckAddresses, recipients)
        // One that is not payable on this network can never be fallen back to.
        let unpayable = try await service.prepareForConfirmation(
            from: url, scheme: "dash", network: .testnet, fallbackAddress: "not an address")
        XCTAssertEqual(unpayable.repeatCheckAddresses, recipients)
    }

    /// A URI address too long to be an address is dropped before any
    /// decoding (Base58 decoding costs time quadratic in its input), and the
    /// request still prepares.
    func testAnOversizedURIAddressIsDroppedWithoutDecoding() async throws {
        let service = BIP70PaymentService(
            transport: AcknowledgingTransport(), wallet: DetachedUnknownWallet(walletId: Data(repeating: 0x3e, count: 32)),
            receiveAddress: StaticReceiveAddress(), auth: NoAuth())
        // 200 000 valid Base58 characters: decoding them would take the
        // quadratic path for a long time; refused by length, this returns at
        // once.
        let oversized = String(repeating: "y", count: 200_000)
        let started = Date()
        let confirmation = try await service.prepareForConfirmation(
            from: URL(string: "http://merchant/pr")!, scheme: "dash", network: .testnet, fallbackAddress: oversized)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "not decoded")
        XCTAssertNil(confirmation.fallbackAddress)
        XCTAssertEqual(confirmation.repeatCheckAddresses, confirmation.recipients.map(\.address))
    }

    /// The codec itself refuses a string longer than its bound without
    /// decoding it, whoever calls it, and still takes valid addresses.
    func testTheAddressCodecRefusesAnOversizedStringAndTakesValidAddresses() throws {
        // The bound decides, not the content: a valid address decodes at a
        // bound of its own length and is refused one below it.
        let valid = "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr"
        XCTAssertEqual(ScriptAddressCodec.base58CheckDecode(valid, maxLength: valid.utf8.count)?.count, 21)
        XCTAssertNil(ScriptAddressCodec.base58CheckDecode(valid, maxLength: valid.utf8.count - 1))

        // 200 000 valid Base58 characters would take the quadratic path for
        // a long time if decoded.
        let started = Date()
        XCTAssertNil(ScriptAddressCodec.scriptPubKey(
            forAddress: String(repeating: "y", count: 200_000), network: .testnet))
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "not decoded")

        // Sampled hashes (the extremes of the range included) of both address
        // kinds on every network round-trip within the address bound.
        for network in [PaymentNetwork.mainnet, .testnet, .devnet] {
            for byte in [UInt8(0x00), 0x11, 0x80, 0xff] {
                let hash = [UInt8](repeating: byte, count: 20)
                for script in [Data([0x76, 0xa9, 0x14] + hash + [0x88, 0xac]), Data([0xa9, 0x14] + hash + [0x87])] {
                    let address = try XCTUnwrap(ScriptAddressCodec.address(forScript: script, network: network))
                    XCTAssertLessThanOrEqual(address.utf8.count, ScriptAddressCodec.maxAddressLength, address)
                    XCTAssertEqual(ScriptAddressCodec.scriptPubKey(forAddress: address, network: network), script, address)
                }
            }
        }
    }

    /// A payment followed under its recipient M and its URI's address X
    /// refuses the plain send to X that a failed request fetch falls back to.
    func testAFallbackPlainSendToTheURIsAddressIsRefused() {
        let wallet = Data(repeating: 0x1d, count: 32)
        let txidWire = Data(repeating: 0x9e, count: 32)
        defer { PendingSendOutcomes.shared.forget(txidsWire: [txidWire], reason: "test send") }
        WalletSendService.followUnknownOutcome(
            txidWire: txidWire, address: "yM", otherAddresses: ["yM", "yX"], amount: 1_000,
            origin: WalletChainScope(walletId: wallet, chain: "testnet"))
        XCTAssertEqual(
            PendingSendOutcomes.refusing(
                ["yX"], on: WalletChainScope(walletId: wallet, chain: "testnet"),
                in: PendingSendOutcomes.shared.entries, now: Date())?.txidWire,
            txidWire)
    }

    func testADetachedBroadcastWithNoAnswerReportsTheWalletThatBuiltIt() async throws {
        let builtFor = Data(repeating: 0x3e, count: 32)
        let wallet = DetachedUnknownWallet(walletId: builtFor)
        let service = BIP70PaymentService(
            transport: AcknowledgingTransport(),
            wallet: wallet,
            receiveAddress: StaticReceiveAddress(),
            auth: NoAuth())
        let reported = expectation(description: "the unknown outcome is reported")
        var reportedOrigin: WalletChainScope?
        service.onDetachedBroadcastUnknown = { _, _, _, origin, _ in
            reportedOrigin = origin
            reported.fulfill()
        }

        let confirmation = try await service.prepareForConfirmation(
            from: URL(string: "http://merchant/pr")!, scheme: "dash", network: .testnet)
        _ = try await service.confirmAndSend(confirmation, awaitAcceptance: false)
        await fulfillment(of: [reported], timeout: 3)

        XCTAssertEqual(
            reportedOrigin, WalletChainScope(walletId: builtFor, chain: "devnet-a"),
            "booked under the wallet and chain that built it, whatever is bound now")
    }
}

private final class DetachedUnknownWallet: WalletSending {
    let prepared: PreparedSend
    init(walletId: Data) {
        prepared = PreparedSend(
            txData: Data([0xde, 0xad]), fee: 226, txHashDisplay: Data(repeating: 0x42, count: 32),
            origin: WalletChainScope(walletId: walletId, chain: "devnet-a"))
    }
    func buildSignedTransaction(recipients: [(address: String, amountDuffs: UInt64)]) async throws -> PreparedSend { prepared }
    func broadcast(_ prepared: PreparedSend) async throws -> String {
        throw BIP70Error.broadcastOutcomeUnknown(
            txHashDisplay: prepared.txHashDisplay, origin: prepared.origin, reason: "no answer")
    }
}

/// An unsigned testnet request with a payment URL, acknowledged on post.
private final class AcknowledgingTransport: PaymentProtocolTransporting {
    /// Further P2PKH outputs after the first, each to its own key hash.
    private let extraOutputs: UInt8
    init(extraOutputs: UInt8 = 0) { self.extraOutputs = extraOutputs }

    func fetchRequest(from url: URL, scheme: String) async throws -> PaymentRequest {
        let script = ScriptAddressCodec.scriptPubKey(forAddress: "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr", network: .testnet)!
        let extra = (0..<extraOutputs).map { index in
            PaymentOutput(
                amount: 50_000,
                script: Data([0x76, 0xa9, 0x14] + [UInt8](repeating: 0x11 + index, count: 20) + [0x88, 0xac]))
        }
        let details = PaymentDetails(
            network: "test", outputs: [PaymentOutput(amount: 100_000, script: script)] + extra,
            expires: UInt64(Date().timeIntervalSince1970) + 3600, memo: "memo",
            paymentURL: "http://merchant/pay", merchantData: Data([0x01]))
        return PaymentRequest(pkiType: "none", serializedDetails: details.encoded())
    }
    func postPayment(_ payment: Payment, to url: URL, scheme: String) async throws -> PaymentACK {
        PaymentACK(payment: nil, memo: "thanks")
    }
}

private final class StaticReceiveAddress: ReceiveAddressProviding {
    func receiveAddress() -> String? { "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr" }
}

private final class NoAuth: SendAuthorizing {
    func authorize() async throws {}
}

/// The Home "… waiting for confirmation" caption's rule.
final class AwaitingConfirmationBalanceTests: XCTestCase {
    private typealias Txo = SwiftDashSDKWalletSource.AwaitingConfirmationTxo

    private func txo(_ dash: UInt64, spender: Bool = false, spent: Bool = false, confirmed: Bool = false,
                     locked: Bool = false, standard: Bool = true) -> Txo {
        Txo(amount: dash * 100_000_000, isSpent: spent, hasSpender: spender, isConfirmed: confirmed,
            isInstantLocked: locked, isStandardAccount: standard)
    }

    /// A persisted chain T1 → T2: T2 spends T1's unconfirmed 9 DASH change and
    /// leaves 8 DASH change. The SDK keeps T1's change `isSpent == false` until
    /// T2 is in a block, with T2 saved as its spender: 8 DASH waits, not 17.
    func testAChainCountsOnlyTheChangeStillInTheWallet() {
        let t1Change = txo(9, spender: true)
        let t2Change = txo(8)
        XCTAssertEqual(SwiftDashSDKWalletSource.awaitingConfirmationTotal(of: [t1Change, t2Change]), 8 * 100_000_000)
    }

    func testOnlyUnsettledStandardOutputsCount() {
        let total = SwiftDashSDKWalletSource.awaitingConfirmationTotal(of: [
            txo(1),
            txo(2, confirmed: true),
            txo(4, locked: true),
            txo(8, spent: true),
            txo(16, standard: false),
        ])
        XCTAssertEqual(total, 1 * 100_000_000)
    }

    func testTheTotalSaturates() {
        let huge = Txo(amount: UInt64.max, isSpent: false, hasSpender: false, isConfirmed: false,
                       isInstantLocked: false, isStandardAccount: true)
        XCTAssertEqual(SwiftDashSDKWalletSource.awaitingConfirmationTotal(of: [huge, txo(1)]), UInt64.max)
    }
}

private final class AnchorProvider: NSObject, PaymentControllerPresentationContextProviding {
    let anchor: UIViewController
    init(anchor: UIViewController) { self.anchor = anchor }
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor { anchor }
}

/// The Home pending caption across a wallet or network switch
/// (`PendingBalanceFollower`).
final class PendingBalanceFollowerTests: XCTestCase {
    private typealias Scope = PendingBalanceFollower.Scope

    private let walletA = Scope(walletId: Data(repeating: 0xa1, count: 32), chain: "testnet")
    private let walletB = Scope(walletId: Data(repeating: 0xb2, count: 32), chain: "testnet")

    private let balanceEvents = PassthroughSubject<Bool, Never>()
    private let coinSaves = PassthroughSubject<Void, Never>()
    private let walletDidChange = PassthroughSubject<Void, Never>()
    /// What the host has bound (read on the main queue and by reads).
    private let bound = OSAllocatedUnfairLock<Scope?>(initialState: nil)
    /// The waiting duffs saved per wallet and network; one not listed fails
    /// to read.
    private let saved = OSAllocatedUnfairLock<[String: UInt64]>(initialState: [:])
    /// Held by a test to keep a read from finishing.
    private let readGate = NSLock()
    private let readCount = OSAllocatedUnfairLock(initialState: 0)

    private func makeFollower() -> PendingBalanceFollower {
        PendingBalanceFollower(
            signals: .init(
                balanceEvents: balanceEvents.eraseToAnyPublisher(),
                coinSaves: coinSaves.eraseToAnyPublisher(),
                walletDidChange: walletDidChange.eraseToAnyPublisher()),
            interval: .milliseconds(100),
            boundScope: { [bound] in bound.withLock { $0 } },
            prepareRead: { [bound, saved, readCount, readGate] in
                guard let scope = bound.withLock({ $0 }) else { return nil }
                return {
                    readCount.withLock { $0 += 1 }
                    readGate.lock()
                    readGate.unlock()
                    return saved.withLock { $0[Self.key(scope)] }.map { .init(scope: scope, duffs: $0) }
                }
            })
    }

    private func bind(_ scope: Scope?) { bound.withLock { $0 = scope } }
    private static func key(_ scope: Scope) -> String { scope.chain + scope.walletId.hexEncodedString() }
    private func save(_ duffs: UInt64?, for scope: Scope) { saved.withLock { $0[Self.key(scope)] = duffs } }
    private var reads: Int { readCount.withLock { $0 } }

    private func spin(until condition: () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func settle(_ seconds: TimeInterval = 0.4) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Wallet A on screen with 7 000 waiting.
    private func followerShowingWalletA() -> PendingBalanceFollower {
        let follower = makeFollower()
        bind(walletA)
        save(7_000, for: walletA)
        balanceEvents.send(true)
        spin(until: { follower.duffs == 7_000 })
        XCTAssertEqual(follower.duffs, 7_000, "wallet A's caption")
        return follower
    }

    /// The runtime publishes the destination wallet's balance and only then
    /// posts the active-wallet notification; on an idle or offline switch
    /// nothing follows it. The read the balance event started found nothing
    /// (its coins were not readable yet), so the notification's own read is
    /// the one that brings the caption up.
    func testTheWalletNotificationReadsWhenTheBalanceEventCameFirstAndNothingFollows() {
        let follower = followerShowingWalletA()

        balanceEvents.send(false)  // teardown
        spin(until: { follower.duffs == nil })
        XCTAssertNil(follower.duffs, "not known while the balance is not")
        bind(walletB)
        let readsBeforeSeed = reads
        balanceEvents.send(true)   // the destination's balance, published first
        spin(until: { self.reads > readsBeforeSeed })
        settle()
        XCTAssertNil(follower.duffs, "the read the balance event started found nothing")

        save(9_000, for: walletB)
        let readsBeforeNotification = reads
        walletDidChange.send()     // the notification, and no event after it
        spin(until: { follower.duffs == 9_000 })
        XCTAssertEqual(follower.duffs, 9_000, "wallet B's caption, from the notification alone")
        XCTAssertEqual(reads, readsBeforeNotification + 1, "one read, started by the notification")
        settle()
        XCTAssertEqual(follower.duffs, 9_000, "and it stays")
    }

    /// The same order with the first read succeeding: the caption is up
    /// before the notification, which does not take it away.
    func testACaptionReadBeforeTheWalletNotificationSurvivesIt() {
        let follower = followerShowingWalletA()
        var seen: [UInt64?] = []
        let watch = follower.$duffs.dropFirst().sink { seen.append($0) }
        defer { watch.cancel() }

        balanceEvents.send(false)
        bind(walletB)
        save(9_000, for: walletB)
        balanceEvents.send(true)
        spin(until: { follower.duffs == 9_000 })
        walletDidChange.send()
        settle()

        XCTAssertEqual(follower.duffs, 9_000)
        XCTAssertEqual(seen, [nil, 9_000], "cleared once for the teardown; the notification clears nothing")
    }

    /// A value is its wallet's: a read that lands after another wallet is
    /// bound is dropped, and the notification clears what was shown.
    func testAnotherWalletsValueIsNeverShown() {
        let follower = followerShowingWalletA()

        // A switch with no teardown event in between (the worst case): wallet
        // B is bound, its coins not readable yet.
        bind(walletB)
        walletDidChange.send()
        spin(until: { follower.duffs == nil })
        XCTAssertNil(follower.duffs, "wallet A's value is not wallet B's")
        coinSaves.send()
        settle()
        XCTAssertNil(follower.duffs, "a failed read brings nothing back")

        save(1_000, for: walletB)
        coinSaves.send()
        spin(until: { follower.duffs == 1_000 })
        XCTAssertEqual(follower.duffs, 1_000)
    }

    /// While the balance is not known (teardown, nothing bound, or the old
    /// wallet still bound under a new Home), nothing is read or shown.
    func testNothingIsReadOrShownWhileTheBalanceIsNotKnown() {
        let follower = followerShowingWalletA()
        balanceEvents.send(false)
        spin(until: { follower.duffs == nil })
        let readsAfterTeardown = reads

        coinSaves.send()  // the old wallet's persister is still writing
        walletDidChange.send()
        settle()
        XCTAssertNil(follower.duffs, "the old wallet is still bound, but its balance is not shown")
        XCTAssertEqual(reads, readsAfterTeardown, "and nothing is read for it")
    }

    /// A rebuild that posts no notification (a plain restart) shows its
    /// caption at its first known balance.
    func testARestartWithNoNotificationShowsItsCaption() {
        let follower = followerShowingWalletA()
        balanceEvents.send(false)
        bind(nil)
        spin(until: { follower.duffs == nil })
        XCTAssertNil(follower.duffs)

        bind(walletA)
        balanceEvents.send(true)
        spin(until: { follower.duffs == 7_000 })
        XCTAssertEqual(follower.duffs, 7_000)
    }

    /// The same wallet id on another network is another wallet: its value is
    /// read for that network, and a read that started on the old one is not
    /// shown.
    func testTheSameWalletOnAnotherNetworkIsAnotherScope() {
        let follower = followerShowingWalletA()
        let onMainnet = Scope(walletId: walletA.walletId, chain: "mainnet")
        save(3_000, for: onMainnet)

        readGate.lock()            // a testnet read is held in flight
        let before = reads
        coinSaves.send()
        spin(until: { self.reads > before })
        bind(onMainnet)            // the switch lands meanwhile
        walletDidChange.send()
        spin(until: { follower.duffs == nil })
        readGate.unlock()

        spin(until: { follower.duffs == 3_000 })
        XCTAssertEqual(follower.duffs, 3_000, "mainnet's value, never testnet's 7 000 again")
    }

    /// One read at a time: events during a slow read start exactly one more
    /// when it lands, so reads do not pile up and the last event is read for.
    func testEventsDuringASlowReadStartOneMoreRead() {
        let follower = followerShowingWalletA()
        readGate.lock()
        let before = reads
        coinSaves.send()
        spin(until: { self.reads > before })
        save(8_000, for: walletA)
        for _ in 0..<5 {
            coinSaves.send()
            settle(0.12)
        }
        XCTAssertEqual(reads, before + 1, "nothing starts while one is running")
        readGate.unlock()

        spin(until: { follower.duffs == 8_000 })
        settle()
        XCTAssertEqual(follower.duffs, 8_000)
        XCTAssertEqual(reads, before + 2, "one more, for the events that came meanwhile")
    }

    /// A failed read keeps the last known value of the same wallet.
    func testAFailedReadKeepsTheLastValue() {
        let follower = followerShowingWalletA()
        save(nil, for: walletA)
        let before = reads
        coinSaves.send()
        spin(until: { self.reads > before })
        settle()
        XCTAssertEqual(follower.duffs, 7_000)
    }
}
