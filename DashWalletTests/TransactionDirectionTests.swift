//
//  TransactionDirectionTests.swift
//  DashWalletTests
//

import Foundation
import XCTest
@testable import dashwallet

final class TransactionDirectionTests: XCTestCase {
    func testFFIDirectionMapping() {
        XCTAssertEqual(makeTransaction(directionRaw: 0, netAmount: 100).direction, .received)
        XCTAssertEqual(makeTransaction(directionRaw: 1, netAmount: -110, fee: 10).direction, .sent)
        XCTAssertEqual(makeTransaction(directionRaw: 2, netAmount: 0).direction, .moved)
        XCTAssertEqual(makeTransaction(directionRaw: 3, netAmount: -10, fee: 10).direction, .sent)
    }

    func testUnknownFFIDirectionFallsBackToNetAmountSign() {
        XCTAssertEqual(makeTransaction(directionRaw: .max, netAmount: 1).direction, .received)
        XCTAssertEqual(makeTransaction(directionRaw: .max, netAmount: 0).direction, .received)
        XCTAssertEqual(makeTransaction(directionRaw: .max, netAmount: -1).direction, .sent)
    }

    func testOutgoingFeeOnlySelfSendIsMoved() {
        let transaction = makeTransaction(directionRaw: 1, netAmount: -10, fee: 10)

        XCTAssertEqual(transaction.direction, .moved)
        XCTAssertEqual(transaction.dashAmount, 0)
        XCTAssertEqual(transaction.signedDashAmount, 0)
    }

    func testSentAndReceivedAmountsKeepTheirSigns() {
        let received = makeTransaction(directionRaw: 0, netAmount: 125)
        let sent = makeTransaction(directionRaw: 1, netAmount: -125, fee: 25)

        XCTAssertEqual(received.dashAmount, 125)
        XCTAssertEqual(received.signedDashAmount, 125)
        XCTAssertEqual(sent.dashAmount, 100)
        XCTAssertEqual(sent.signedDashAmount, -100)
    }

    func testPresentationAndDefaultTaxCategories() {
        assertPresentation(
            .sent,
            titleKey: "Amount Sent",
            symbol: "-",
            iconName: "tx.item.sent.icon",
            taxCategory: .transferOut)
        assertPresentation(
            .received,
            titleKey: "Amount received",
            symbol: "+",
            iconName: "tx.item.received.icon",
            taxCategory: .transferIn)
        assertPresentation(
            .moved,
            titleKey: "Moved to Address",
            symbol: "",
            iconName: "tx.item.internal.icon",
            taxCategory: .expense)
        assertPresentation(
            .notAccountFunds,
            titleKey: "Registered Masternode",
            symbol: "",
            iconName: "tx.item.received.icon",
            taxCategory: .unknown)
    }

    func testInternalTransferDefaultTaxCategory() {
        // A plain self-send (`.moved` ⇒ coreToCore route) defaults to the
        // dedicated Internal Transfer category instead of the direction's
        // Expense fallback.
        let selfSend = makeTransaction(directionRaw: 2, netAmount: 0)
        XCTAssertEqual(selfSend.internalTransferRoute, .coreToCore)
        XCTAssertEqual(selfSend.defaultTaxCategory, .internalTransfer)

        // External sends/receives carry no internal route and keep the
        // direction defaults.
        let sent = makeTransaction(directionRaw: 1, netAmount: -110, fee: 10)
        XCTAssertNil(sent.internalTransferRoute)
        XCTAssertEqual(sent.defaultTaxCategory, .transferOut)
        XCTAssertEqual(makeTransaction(directionRaw: 0, netAmount: 100).defaultTaxCategory, .transferIn)
    }

    func testCrowdNodeTopUpStillRequiresMovedDirection() {
        let address = "Xcrowdnode"
        let output = ObservedTransaction.Output(
            address: address,
            amount: CrowdNode.requiredForSignup)
        let moved = makeObservedTransaction(
            wrapped: makeTransaction(directionRaw: 1, netAmount: -10, fee: 10),
            output: output)
        let sent = makeObservedTransaction(
            wrapped: makeTransaction(directionRaw: 1, netAmount: -110, fee: 10),
            output: output)

        XCTAssertTrue(CrowdNodeTopUpTx(address: address).matches(moved))
        XCTAssertFalse(CrowdNodeTopUpTx(address: address).matches(sent))
    }

    private func makeTransaction(
        directionRaw: UInt32,
        netAmount: Int64,
        fee: UInt64? = nil
    ) -> Transaction {
        Transaction(
            syntheticTxid: Data(repeating: UInt8(truncatingIfNeeded: directionRaw), count: 32),
            directionRaw: directionRaw,
            netAmount: netAmount,
            fee: fee,
            contextRaw: 0,
            date: Date(timeIntervalSince1970: 1))
    }

    private func makeObservedTransaction(
        wrapped: Transaction,
        output: ObservedTransaction.Output
    ) -> ObservedTransaction {
        ObservedTransaction(
            txid: wrapped.txHashData,
            txidHexDisplay: wrapped.txHashHexString,
            outputs: [output],
            inputAddresses: [],
            timestamp: wrapped.date,
            ownOutputsAmount: 0,
            ownOutputAddresses: [],
            isChainAccepted: true,
            context: 2,
            wrapped: wrapped)
    }

    private func assertPresentation(
        _ direction: TransactionDirection,
        titleKey: String,
        symbol: String,
        iconName: String,
        taxCategory: TxMetadataTaxCategory,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            direction.title,
            NSLocalizedString(titleKey, comment: ""),
            file: file,
            line: line)
        XCTAssertEqual(direction.directionSymbol, symbol, file: file, line: line)
        XCTAssertEqual(direction.iconName, iconName, file: file, line: line)
        XCTAssertEqual(direction.defaultTaxCategory, taxCategory, file: file, line: line)
    }
}
