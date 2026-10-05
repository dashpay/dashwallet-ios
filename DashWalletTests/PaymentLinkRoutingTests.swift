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
        XCTAssertEqual(delegate.acknowledgements, [], "the delegate is told only once the notice is closed")
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root), "the notice is a presented modal the router sees")

        notice.rootView.positiveButtonAction()
        spin(until: { !delegate.acknowledgements.isEmpty })
        XCTAssertEqual(delegate.acknowledgements, [false], "told once, with the notice already gone")
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

    init(anchor: UIViewController) { self.anchor = anchor }

    func paymentControllerDidFinishTransaction(_ controller: PaymentController, txidWire: Data) {}
    func paymentControllerDidCancelTransaction(_ controller: PaymentController) {}
    func paymentControllerDidFailTransaction(_ controller: PaymentController) {}
    func paymentControllerDidSubmitWithUnknownOutcome(_ controller: PaymentController, txidWire: Data) {
        acknowledgements.append(anchor.view.window?.rootViewController?.presentedViewController != nil)
    }

    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        anchor
    }
}
