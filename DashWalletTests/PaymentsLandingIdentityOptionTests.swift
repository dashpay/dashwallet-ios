//
//  PaymentsLandingIdentityOptionTests.swift
//  DashWalletTests
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

import SwiftDashSDK
import SwiftUI
import XCTest
@testable import dashpay

/// When Receive offers the Identity option, what its card shows, and where
/// the selection goes when the option disappears (AC-03, AC-09 – AC-14).
@MainActor
final class PaymentsLandingIdentityOptionTests: XCTestCase {
    private let identityId = Data((1...32).map { UInt8($0) })
    private let otherIdentityId = Data((0..<32).map { UInt8(255 - $0) })

    private var identity: ReceiveIdentity {
        get throws { try XCTUnwrap(ReceiveIdentity(identityId: identityId, username: "alice")) }
    }

    // MARK: Card state

    func testIdentityCardCarriesTheBareBase58Id() throws {
        let id = try identity.identityIdBase58
        XCTAssertEqual(id, ScriptAddressCodec.base58Encode(identityId))
        XCTAssertTrue((43...44).contains(id.count), "\(id.count)")
        XCTAssertFalse(id.contains("alice"))
        XCTAssertFalse(id.contains(":"))
        XCTAssertEqual(try identity.username, "alice")
    }

    func testNoIdentityOrNoUsernameMeansNoIdentityCard() {
        XCTAssertNil(ReceiveIdentity(identityId: nil, username: "alice"))
        XCTAssertNil(ReceiveIdentity(identityId: identityId, username: nil))
        XCTAssertNil(ReceiveIdentity(identityId: identityId, username: ""))
    }

    // MARK: Offered options

    func testAdvancedModeOffIsTheBasicReceive() throws {
        XCTAssertEqual(
            ReceiveOptionPolicy.options(isAdvancedMode: false, identity: try identity, isQuickReceive: false),
            [.core, .shielded])
    }

    func testAdvancedModeOnWithoutAUsernameOffersNoIdentity() {
        XCTAssertEqual(
            ReceiveOptionPolicy.options(isAdvancedMode: true, identity: nil, isQuickReceive: false),
            [.core, .shielded, .platform])
    }

    func testAdvancedModeOnWithAUsernameAppendsIdentityAfterPlatform() throws {
        XCTAssertEqual(
            ReceiveOptionPolicy.options(isAdvancedMode: true, identity: try identity, isQuickReceive: false),
            [.core, .shielded, .platform, .identity])
    }

    func testQuickReceiveNeverOffersIdentity() throws {
        XCTAssertFalse(
            ReceiveOptionPolicy.options(isAdvancedMode: true, identity: try identity, isQuickReceive: true)
                .contains(.identity))
        let model = PaymentsLandingViewModel.makeForPreview(activeTab: .receive, isQuickReceive: true)
        model.updateReceiveState(isAdvancedMode: true, identity: try identity)
        XCTAssertFalse(model.receiveOptions.contains(.identity))
    }

    // MARK: Selection

    private func modelOnIdentity() throws -> PaymentsLandingViewModel {
        let model = PaymentsLandingViewModel.makeForPreview(activeTab: .receive)
        model.updateReceiveState(isAdvancedMode: true, identity: try identity)
        model.network = .identity
        return model
    }

    func testAdvancedModeOffOnIdentityMovesToCore() throws {
        let model = try modelOnIdentity()
        model.updateReceiveState(isAdvancedMode: false, identity: try identity)
        XCTAssertEqual(model.network, .core)
        XCTAssertEqual(model.receiveOptions, [.core, .shielded])
    }

    func testUsernameAppearingKeepsTheSelection() throws {
        let model = PaymentsLandingViewModel.makeForPreview(activeTab: .receive)
        model.updateReceiveState(isAdvancedMode: true, identity: nil)
        model.network = .platform
        model.updateReceiveState(isAdvancedMode: true, identity: try identity)
        XCTAssertEqual(model.network, .platform)
        XCTAssertEqual(model.receiveOptions.last, .identity)
    }

    func testLosingTheUsernameOnIdentityMovesToCoreAndClearsTheCard() throws {
        let model = try modelOnIdentity()
        model.updateReceiveState(isAdvancedMode: true, identity: nil)
        XCTAssertEqual(model.network, .core)
        XCTAssertNil(model.receiveIdentity)
    }

    func testChangedUsernameStaysOnIdentityAndShowsTheNewName() throws {
        let model = try modelOnIdentity()
        model.updateReceiveState(
            isAdvancedMode: true, identity: ReceiveIdentity(identityId: identityId, username: "bob"))
        XCTAssertEqual(model.network, .identity)
        XCTAssertEqual(model.receiveIdentity?.username, "bob")
    }

    func testSwitchToAnotherIdentityShowsOnlyTheNewId() throws {
        let model = try modelOnIdentity()
        let other = try XCTUnwrap(ReceiveIdentity(identityId: otherIdentityId, username: "carol"))
        model.updateReceiveState(isAdvancedMode: true, identity: other)
        XCTAssertEqual(model.network, .identity)
        XCTAssertEqual(model.receiveIdentity, other)
        XCTAssertNotEqual(model.receiveIdentity?.identityIdBase58, try identity.identityIdBase58)
    }

    // MARK: Card content

    /// The QR, Copy and Share all take `currentAddress`; on Identity it is the
    /// bare Base58 ID and nothing else (AC-03).
    func testOnIdentityTheCardEncodesCopiesAndSharesTheBareId() throws {
        let model = try modelOnIdentity()
        XCTAssertEqual(model.currentAddress, try identity.identityIdBase58)
        UIPasteboard.general.string = nil
        model.copyCurrentAddressToPasteboard()
        XCTAssertEqual(UIPasteboard.general.string, try identity.identityIdBase58)
    }

    func testCopyUsernameCopiesExactlyTheUsername() throws {
        let model = try modelOnIdentity()
        UIPasteboard.general.string = nil
        model.copyUsernameToPasteboard()
        XCTAssertEqual(UIPasteboard.general.string, "alice")
    }

    func testIdentityWithoutUsernameHasNothingToEncode() {
        let model = PaymentsLandingViewModel.makeForPreview(activeTab: .receive)
        model.updateReceiveState(isAdvancedMode: true, identity: nil)
        model.network = .identity
        XCTAssertNil(model.currentAddress)
    }

    func testIdentityReceiptNamesTheIdentityBalanceAndIsReceived() {
        let receipt = ReceiveReceipt(
            id: "identity-1", rail: .identity, amountDuffs: 1, receivedAt: Date(), memo: nil, transactionId: nil)
        XCTAssertEqual(receipt.rail.balanceName, NSLocalizedString("Identity", comment: ""))
        XCTAssertEqual(receipt.statusTitle, NSLocalizedString("Received", comment: "Receive payment status"))
    }

    // MARK: Identity watch (T6)

    private let walletId = Data(repeating: 9, count: 32)

    /// Answers reads from a queue (failure when empty) and records them.
    private final class FakeCredits {
        var answers: [UInt64] = []
        private(set) var reads: [IdentityCreditsWatcher.Session] = []

        func read(_ session: IdentityCreditsWatcher.Session) -> Result<UInt64, Error> {
            reads.append(session)
            guard !answers.isEmpty else { return .failure(IdentityBalanceRefresh.Superseded()) }
            return .success(answers.removeFirst())
        }
    }

    /// Keeps the watcher's tick so the test fires it instead of a timer.
    private final class Ticks {
        var tick: (@MainActor () async -> Void)?

        func fire() async { await tick?() }
    }

    private let credits = FakeCredits()
    private let ticks = Ticks()
    private let topUpCenter = NotificationCenter()

    private func watchedModel(isQuickReceive: Bool = false) throws -> PaymentsLandingViewModel {
        let credits = credits
        let ticks = ticks
        let watcher = IdentityCreditsWatcher(
            read: { credits.read($0) },
            schedule: { _, tick in
                ticks.tick = tick
                return Task {}
            },
            center: topUpCenter)
        let walletId = walletId
        let model = PaymentsLandingViewModel.makeForPreview(
            activeTab: .receive,
            isQuickReceive: isQuickReceive,
            identityWatcher: watcher,
            identityContext: { (walletId, .testnet) },
            receiveIdentitySource: { [identityId] in ReceiveIdentity(identityId: identityId, username: "alice") })
        model.updateReceiveState(isAdvancedMode: true, identity: try identity)
        model.network = .identity
        model.setReceiveSurfaceVisible(true)
        return model
    }

    private var watchSession: IdentityCreditsWatcher.Session {
        IdentityCreditsWatcher.Session(walletId: walletId, network: .testnet, identityId: identityId)
    }

    func testPickingIdentityStartsAWatchForTheCurrentIdentity() async throws {
        let model = try watchedModel()
        credits.answers = [10_000]
        await ticks.fire()
        XCTAssertEqual(credits.reads, [watchSession])
        XCTAssertTrue(model.isWatchingForReceipt)
    }

    func testARiseRaisesAnIdentityReceiptWithNoTransaction() async throws {
        let model = try watchedModel()
        credits.answers = [10_000, 5_010_000]
        await ticks.fire()
        await ticks.fire()
        let receipt = try XCTUnwrap(model.receipt)
        XCTAssertEqual(receipt.rail, .identity)
        XCTAssertEqual(receipt.amountDuffs, 5_000)
        XCTAssertNil(receipt.transactionId)
        XCTAssertFalse(model.canViewTransaction)
        XCTAssertFalse(model.isWatchingForReceipt)
    }

    func testAFailedReadDropsTheWatchingNote() async throws {
        let model = try watchedModel()
        credits.answers = [10_000]
        await ticks.fire()
        XCTAssertTrue(model.isWatchingForReceipt)
        await ticks.fire()
        XCTAssertFalse(model.isWatchingForReceipt)
    }

    func testARegistrationUpdateMidSessionKeepsTheStartingBalance() async throws {
        let model = try watchedModel()
        credits.answers = [10_000, 12_000]
        await ticks.fire()
        model.registrationStatusDidChange()
        await ticks.fire()
        XCTAssertEqual(model.network, .identity)
        XCTAssertEqual(model.receipt?.amountDuffs, 2)
    }

    func testQuickReceiveStartsNoWatchEvenWithIdentitySelected() async throws {
        let model = try watchedModel(isQuickReceive: true)
        model.network = .identity
        model.setReceiveSurfaceVisible(true)
        credits.answers = [10_000]
        await ticks.fire()
        XCTAssertTrue(credits.reads.isEmpty)
        XCTAssertFalse(model.isWatchingForReceipt)
    }

    func testUsernameChangeKeepsTheStartingBalance() async throws {
        let model = try watchedModel()
        credits.answers = [10_000, 12_000]
        await ticks.fire()
        model.updateReceiveState(
            isAdvancedMode: true, identity: ReceiveIdentity(identityId: identityId, username: "bob"))
        await ticks.fire()
        XCTAssertEqual(model.receipt?.amountDuffs, 2)
    }

    func testAnotherIdentityStartsANewSession() async throws {
        let model = try watchedModel()
        credits.answers = [10_000, 50_000]
        await ticks.fire()
        model.updateReceiveState(
            isAdvancedMode: true, identity: ReceiveIdentity(identityId: otherIdentityId, username: "carol"))
        await ticks.fire()
        XCTAssertEqual(credits.reads.last?.identityId, otherIdentityId)
        XCTAssertNil(model.receipt, "The new identity's first read is its Starting balance")
    }

    func testAdvancedModeOffStopsTheWatch() async throws {
        let model = try watchedModel()
        credits.answers = [10_000, 50_000]
        await ticks.fire()
        model.updateReceiveState(isAdvancedMode: false, identity: try identity)
        await ticks.fire()
        XCTAssertEqual(credits.reads.count, 1)
        XCTAssertNil(model.receipt)
    }

    func testNoChecksWhileTheCardIsCovered() async throws {
        let model = try watchedModel()
        credits.answers = [10_000]
        await ticks.fire()
        model.setReceiptWatchingObscured(true)
        await ticks.fire()
        XCTAssertEqual(credits.reads.count, 1)
        XCTAssertFalse(model.isWatchingForReceipt)
    }

    // MARK: The production read (AC-07, AC-13)

    private enum Offline: Error { case unreachable }

    /// The read with a recording refresh; `context` is the active wallet and network.
    private func productionRead(
        context: (walletId: Data, network: Network?)?,
        answer: Result<UInt64, Error> = .success(42)
    ) -> (IdentityCreditsWatcher.Read, () -> [IdentityCreditsWatcher.Session]) {
        var refreshed: [IdentityCreditsWatcher.Session] = []
        let read = PaymentsLandingViewModel.identityBalanceRead(
            activeContext: { context },
            refresh: { refreshed.append($0); return answer })
        return (read, { refreshed })
    }

    func testTheReadRefreshesTheSessionsIdentityInTheActiveContext() async {
        let (read, refreshed) = productionRead(context: (walletId, .testnet))
        let result = await read(watchSession)
        XCTAssertEqual(try? result.get(), 42)
        XCTAssertEqual(refreshed(), [watchSession])
    }

    func testTheReadPassesARefreshFailureThrough() async {
        let (read, _) = productionRead(context: (walletId, .testnet), answer: .failure(Offline.unreachable))
        let result = await read(watchSession)
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? Offline, .unreachable) }
    }

    func testTheReadNeverRefreshesForAnotherWalletNetworkOrNoWallet() async {
        let contexts: [(walletId: Data, network: Network?)?] = [
            (Data(repeating: 7, count: 32), .testnet),
            (walletId, .mainnet),
            (walletId, nil),
            nil
        ]
        for context in contexts {
            let (read, refreshed) = productionRead(context: context)
            let result = await read(watchSession)
            XCTAssertThrowsError(try result.get())
            XCTAssertTrue(refreshed().isEmpty)
        }
    }

    // MARK: A trip to Internal transfer (AC-08)

    private func visitInternalTransfer(_ model: PaymentsLandingViewModel, while action: () -> Void = {}) {
        model.activeTab = .internalTransfer
        action()
        model.activeTab = .receive
    }

    func testPayerCreditsDuringInternalTransferRaiseAReceiptOnReturn() async throws {
        let model = try watchedModel()
        credits.answers = [10_000, 30_000]
        await ticks.fire()
        visitInternalTransfer(model)
        await ticks.fire()
        XCTAssertEqual(model.network, .identity)
        XCTAssertEqual(model.receipt?.amountDuffs, 20)
    }

    func testOwnTopUpDuringInternalTransferRaisesNoReceipt() async throws {
        let model = try watchedModel()
        credits.answers = [10_000, 30_000]
        await ticks.fire()
        visitInternalTransfer(model) {
            IdentityTopUpDidComplete(
                walletId: walletId, network: .testnet, identityId: identityId,
                balanceAfter: 30_000, suppliedCredits: 20_000)
                .post(to: topUpCenter)
        }
        await ticks.fire()
        XCTAssertNil(model.receipt)
        XCTAssertTrue(model.isWatchingForReceipt)
    }

    func testNoChecksWhileOnInternalTransfer() async throws {
        let model = try watchedModel()
        credits.answers = [10_000]
        await ticks.fire()
        model.activeTab = .internalTransfer
        await ticks.fire()
        XCTAssertEqual(credits.reads.count, 1)
        XCTAssertFalse(model.isWatchingForReceipt)
    }

    func testReceiveAnotherStartsAFreshStartingBalance() async throws {
        let model = try watchedModel()
        credits.answers = [10_000, 20_000, 20_000]
        await ticks.fire()
        await ticks.fire()
        XCTAssertEqual(model.receipt?.amountDuffs, 10)
        model.receiveAnother()
        await ticks.fire()
        XCTAssertNil(model.receipt)
        XCTAssertTrue(model.isWatchingForReceipt)
    }

    // MARK: Layout

    /// The Identity card is the tallest Receive card. On a screen shorter
    /// than it, the page must still fit what it is given (it scrolls) rather
    /// than ask for more: an overflowing page squeezes the AC-04 warning to
    /// one truncated line per sentence and pushes Close off the top.
    func testIdentityReceivePageFitsTheHeightItIsGiven() throws {
        let model = PaymentsLandingViewModel.makeForPreview(activeTab: .receive, isWatching: true)
        model.updateReceiveState(isAdvancedMode: true, identity: try identity)
        model.network = .identity
        let screen = PaymentsLandingScreen(
            viewModel: model,
            onClose: {},
            onDone: {},
            onCopyAddress: {},
            onShareAddress: {},
            onSpecifyAmount: {},
            onViewTransaction: { _ in },
            onScanQR: {},
            embeddedTransferViewModel: .makeForPreview(),
            embeddedSendViewModel: .makeForPreview(),
            showsHeader: false)
        let host = UIHostingController(rootView: screen)
        // The payments sheet's content area on an iPhone 17 and on the
        // smallest supported iPhone (375 × 667 pt, less the sheet's top gap
        // and the home indicator).
        for given in [CGSize(width: 402, height: 778), CGSize(width: 375, height: 600)] {
            let needed = host.sizeThatFits(in: given)
            XCTAssertLessThanOrEqual(needed.height, given.height, "page at \(given)")
        }
    }
}
