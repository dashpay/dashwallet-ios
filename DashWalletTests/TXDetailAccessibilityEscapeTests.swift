//
//  TXDetailAccessibilityEscapeTests.swift
//  DashWalletTests
//

import XCTest
@testable import dashpay

/// VoiceOver's escape on the transaction detail. A host that embeds the detail answers escape
/// through `onAccessibilityEscape`; returning `false` leaves the escape to the responders above
/// the detail, as a controller without the hook does. Escape handling never loads the view, whose
/// `viewDidLoad` starts explorer and database lookups.
@MainActor
final class TXDetailAccessibilityEscapeTests: XCTestCase {
    func testEscapeIsConsumedWhenTheHookActs() {
        let detail = makeDetail()
        let hook = CountingHook(returning: true)
        detail.onAccessibilityEscape = hook.callAsFunction

        XCTAssertTrue(detail.accessibilityPerformEscape())
        XCTAssertEqual(hook.calls, 1)
        XCTAssertFalse(detail.isViewLoaded)
    }

    func testEscapeRisesWhenTheHookDeclines() {
        let detail = makeDetail()
        let hook = CountingHook(returning: false)
        detail.onAccessibilityEscape = hook.callAsFunction

        XCTAssertFalse(detail.accessibilityPerformEscape())
        XCTAssertEqual(hook.calls, 1)
        XCTAssertFalse(detail.isViewLoaded)
    }

    func testEscapeRisesWithoutAHook() {
        let detail = makeDetail()

        XCTAssertFalse(detail.accessibilityPerformEscape())
        XCTAssertFalse(detail.isViewLoaded)
    }

    func testEscapeSkipsTheHookWhilePresentedViewControllerIsSet() {
        let detail = makePresentingDetail()
        let hook = CountingHook(returning: true)
        detail.onAccessibilityEscape = hook.callAsFunction

        XCTAssertFalse(detail.accessibilityPerformEscape())
        XCTAssertEqual(hook.calls, 0)
        XCTAssertFalse(detail.isViewLoaded)
    }

    // MARK: - Helpers

    private final class CountingHook {
        private let result: Bool
        private(set) var calls = 0

        init(returning result: Bool) {
            self.result = result
        }

        func callAsFunction() -> Bool {
            calls += 1
            return result
        }
    }

    /// A detail whose `presentedViewController` is set, without loading the view or putting it
    /// in a window.
    private final class PresentingDetail: TXDetailViewController {
        private let presented = UIViewController()

        override var presentedViewController: UIViewController? {
            presented
        }
    }

    private func makeModel() -> TxDetailModel {
        TxDetailModel(transaction: Transaction(
            syntheticTxid: Data(repeating: 1, count: 32),
            directionRaw: 0,
            netAmount: 100,
            fee: nil,
            contextRaw: 0,
            date: Date(timeIntervalSince1970: 1)))
    }

    private func makeDetail() -> TXDetailViewController {
        TXDetailViewController(model: makeModel())
    }

    private func makePresentingDetail() -> TXDetailViewController {
        PresentingDetail(model: makeModel())
    }
}
