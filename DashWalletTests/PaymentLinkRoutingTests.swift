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
        let anchor = AnchorProvider(anchor: root)
        let controller = PaymentController()
        controller.presentationContextProvider = anchor
        let waiting = PendingSendOutcomes.Entry(
            txidWire: Data(repeating: 0x9c, count: 32), walletId: Data(repeating: 0x1d, count: 32),
            address: "yAddressForTests", amount: 100_000, sentAt: Date())
        controller.waitingPayment = { $0 == "yAddressForTests" ? waiting : nil }
        var logged: [String] = []
        controller.log = { logged.append($0) }

        var answers: [Bool] = []
        controller.paymentProcessor(DWPaymentProcessor(), shouldPayAddress: "yAddressForTests", isBIP70: true) { answers.append($0) }
        let notice = try XCTUnwrap(root.presentedViewController as? UIHostingController<ModalDialog>, "the notice is up")
        XCTAssertEqual(answers, [], "nothing goes on while it is up")
        XCTAssertNil(notice.rootView.negativeButtonText, "a single OK, no way to send anyway")
        XCTAssertNotNil(notice.rootView.textBlock2, "says how to get past a payment that never arrives")
        XCTAssertEqual(logged.count, 1)
        let shown = try XCTUnwrap(logged.first)
        XCTAssertTrue(shown.contains("TXSEND") && shown.contains("route=BIP70"), shown)
        XCTAssertTrue(shown.contains("pending=\(PendingSendOutcomes.shortTxid(waiting.txidWire))"), shown)
        XCTAssertTrue(shown.contains("wallet=1d1d1d1d"), shown)
        XCTAssertFalse(shown.contains("yAddressForTests"), "never the full address")

        notice.rootView.positiveButtonAction()
        spin(until: { !answers.isEmpty })
        XCTAssertEqual(answers, [false], "OK returns without paying")
        XCTAssertEqual(logged.count, 2)
        XCTAssertTrue(logged.last?.contains("cancelled on OK") == true, logged.last ?? "")

        var other: [Bool] = []
        controller.paymentProcessor(DWPaymentProcessor(), shouldPayAddress: "yOtherAddress", isBIP70: false) { other.append($0) }
        XCTAssertEqual(other, [true], "another address is not interrupted")
        XCTAssertEqual(logged.count, 2, "nothing pending: no log")
    }

    func testAnUnknownOutcomeErrorCarriesItsTxid() {
        let txidWire = Data(repeating: 0x7e, count: 32)
        defer { PendingSendOutcomes.shared.forget(txidsWire: [txidWire]) }
        let error = WalletSendService.unknownOutcomeError(txidWire: txidWire, address: nil, amount: 1, reason: "timeout", walletId: nil)
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

    private func entry(_ byte: UInt8, wallet: Data? = nil, age: TimeInterval, amount: UInt64 = 1_000, notifies: Bool? = nil) -> PendingSendOutcomes.Entry {
        PendingSendOutcomes.Entry(
            txidWire: Data(repeating: byte, count: 32), walletId: wallet ?? walletA, address: "yAddress",
            amount: amount, sentAt: now.addingTimeInterval(-age), notifies: notifies)
    }

    private func decide(
        _ entries: [PendingSendOutcomes.Entry],
        rows: [Data: Policy.RowState]?,
        wallet: Data? = nil,
        followed: Set<Data>? = nil
    ) -> Policy.SettlementDecision {
        let pending = Dictionary(uniqueKeysWithValues: entries.map { ($0.txidWire, $0) })
        let followedNow = followed ?? Set(pending.keys)
        return Policy.settlement(
            of: pending, stillFollowed: { followedNow.contains($0) },
            walletId: wallet ?? walletA, rows: rows, now: now)
    }

    func testAnAcceptedVerdictRereadsButAProcessingRowKeepsTheSendWaiting() {
        let sent = entry(1, age: 60)
        let heard = Policy.acceptances(
            in: [(txidWire: sent.txidWire, walletId: walletA, accepted: true)],
            following: [sent.txidWire: sent], alreadyHeard: [])
        XCTAssertEqual(heard.accepted, [sent.txidWire])
        XCTAssertTrue(heard.isNew, "the rows are read again")

        let decision = decide([sent], rows: [sent.txidWire: .processing])
        XCTAssertTrue(decision.isEmpty, "a node holding the bytes is not a settled payment")
    }

    func testAnAcceptanceIsActedOnOnceAndOnlyFromTheSendsOwnWallet() {
        let sent = entry(1, age: 60)
        let again = Policy.acceptances(
            in: [(txidWire: sent.txidWire, walletId: walletA, accepted: true)],
            following: [sent.txidWire: sent], alreadyHeard: [sent.txidWire])
        XCTAssertFalse(again.isNew, "republished, not new")

        let otherWallet = Policy.acceptances(
            in: [(txidWire: sent.txidWire, walletId: walletB, accepted: true)],
            following: [sent.txidWire: sent], alreadyHeard: [])
        XCTAssertTrue(otherWallet.accepted.isEmpty)
        XCTAssertFalse(otherWallet.isNew)
    }

    func testAFailedReadDecidesNothing() {
        let old = entry(1, age: Policy.missingRowGrace + 3600)
        XCTAssertTrue(decide([old], rows: nil).isEmpty, "a failed read is not \"the row is gone\"")
    }

    func testALockedOrMinedRowSettlesTheSendAndNotifiesOnce() {
        let sent = entry(1, age: 60, amount: 2_500)
        let followed = [sent.txidWire: sent]
        let decision = Policy.settlement(
            of: followed, stillFollowed: { followed[$0] != nil },
            walletId: walletA, rows: [sent.txidWire: .settled], now: now)
        XCTAssertEqual(decision.settled, [sent.txidWire])
        XCTAssertEqual(decision.notifying, [sent])

        // Applied, the send is no longer followed, so the next read of the
        // same rows neither settles it again nor notifies again.
        let remaining = Policy.applying(decision, to: followed)
        XCTAssertTrue(remaining.isEmpty)
        let again = Policy.settlement(
            of: followed, stillFollowed: { remaining[$0] != nil },
            walletId: walletA, rows: [sent.txidWire: .settled], now: now)
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
        XCTAssertTrue(Policy.notifiable(decision.notifying, shownWalletId: walletB).isEmpty, "no toast on B's Home")
        XCTAssertTrue(Policy.notifiable(decision.notifying, shownWalletId: nil).isEmpty, "none during a switch")
        XCTAssertEqual(Policy.notifiable(decision.notifying, shownWalletId: walletA), [sentFromA])
    }

    /// A notice is the shown wallet's: publishing another wallet drops it, a
    /// rebuild of the same wallet keeps it.
    func testASwitchDropsTheShownNoticeAndARebuildKeepsIt() {
        let notice = Policy.merged(nil, adding: 1_000)
        XCTAssertNil(Policy.noticeKept(notice, shownWalletId: walletA, published: walletB), "switched to B")
        XCTAssertNil(Policy.noticeKept(notice, shownWalletId: walletA, published: nil))
        XCTAssertEqual(Policy.noticeKept(notice, shownWalletId: walletA, published: walletA), notice, "A rebuilt")
    }

    func testNoticesMergeOnlyWithinTheShownWallet() {
        let settled = [
            entry(1, wallet: walletA, age: 60, amount: 1_000),
            entry(2, wallet: walletB, age: 60, amount: 5_000),
            entry(3, wallet: walletA, age: 60, amount: 2_000),
        ]
        var notice: PendingSendOutcomes.Notice?
        for entry in Policy.notifiable(settled, shownWalletId: walletA) {
            notice = Policy.merged(notice, adding: entry.amount)
        }
        XCTAssertEqual(notice?.count, 2)
        XCTAssertEqual(notice?.total, 3_000, "B's payment is not added to A's total")
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
            txidWire: txidWire, address: "yAddress", amount: 1_000, walletId: sentFrom)

        XCTAssertEqual(PendingSendOutcomes.shared.entries[txidWire]?.walletId, sentFrom, "followed under its wallet")
        XCTAssertFalse(shownNow, "not the active wallet: no row on screen to point the user at")
    }

    /// The plain-send route: the prepared send carries the signing wallet,
    /// and its unknown outcome is booked under it.
    func testAPreparedSendsUnknownOutcomeIsBookedUnderItsSigningWallet() {
        let signedBy = Data(repeating: 0x7a, count: 32)
        let send = PreparedStandardSend(
            txData: Data([0x01]), txHash: Data(repeating: 0x8b, count: 32), fee: 226,
            address: "yAddress", amount: 1_000, walletId: signedBy,
            broadcastAction: { .unknown(txid: String(repeating: "8b", count: 32), reason: "no answer") })
        defer { PendingSendOutcomes.shared.forget(txidsWire: [send.txidWire], reason: "test send") }

        XCTAssertThrowsError(try send.broadcast()) { error in
            XCTAssertTrue(WalletSendService.isBroadcastUnknownError(error as NSError))
            XCTAssertFalse(WalletSendService.isFollowedUnknownOutcomeError(error as NSError),
                           "its wallet is not on screen: told with the error's own copy")
        }
        XCTAssertEqual(PendingSendOutcomes.shared.entries[send.txidWire]?.walletId, signedBy)
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
        var reportedWallet: Data?
        service.onDetachedBroadcastUnknown = { _, _, _, walletId, _ in
            reportedWallet = walletId
            reported.fulfill()
        }

        let confirmation = try await service.prepareForConfirmation(
            from: URL(string: "http://merchant/pr")!, scheme: "dash", network: .testnet)
        _ = try await service.confirmAndSend(confirmation, awaitAcceptance: false)
        await fulfillment(of: [reported], timeout: 3)

        XCTAssertEqual(reportedWallet, builtFor, "booked under the wallet that built it, whatever is active now")
    }
}

private final class DetachedUnknownWallet: WalletSending {
    let prepared: PreparedSend
    init(walletId: Data) {
        prepared = PreparedSend(
            txData: Data([0xde, 0xad]), fee: 226, txHashDisplay: Data(repeating: 0x42, count: 32), walletId: walletId)
    }
    func buildSignedTransaction(recipients: [(address: String, amountDuffs: UInt64)]) async throws -> PreparedSend { prepared }
    func broadcast(_ prepared: PreparedSend) async throws -> String {
        throw BIP70Error.broadcastOutcomeUnknown(
            txHashDisplay: prepared.txHashDisplay, walletId: prepared.walletId, reason: "no answer")
    }
}

/// An unsigned testnet request with a payment URL, acknowledged on post.
private final class AcknowledgingTransport: PaymentProtocolTransporting {
    func fetchRequest(from url: URL, scheme: String) async throws -> PaymentRequest {
        let script = ScriptAddressCodec.scriptPubKey(forAddress: "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr", network: .testnet)!
        let details = PaymentDetails(
            network: "test", outputs: [PaymentOutput(amount: 100_000, script: script)],
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
