//
//  CoinbaseTransactionMetadataTests.swift
//  DashWalletTests
//

import DashUIKit
import Foundation
import XCTest
@testable import dashwallet

final class CoinbaseTransactionMetadataTests: XCTestCase {
    func testDirectCoinbaseHashConvertsDisplayOrderToWireOrder() {
        XCTAssertEqual(
            CoinbaseTransactionMetadataTagger.walletTxHashData(from: " 000102 "),
            Data([0x02, 0x01, 0x00]))
        XCTAssertNil(CoinbaseTransactionMetadataTagger.walletTxHashData(from: nil))
        XCTAssertNil(CoinbaseTransactionMetadataTagger.walletTxHashData(from: "not-hex"))
    }

    func testWalletRecordKeepsWireOrderAndDerivesDisplayOrderTxid() {
        let transaction = Transaction(
            syntheticTxid: Data([0x00, 0x01, 0x02]),
            directionRaw: 0,
            netAmount: 100,
            fee: nil,
            contextRaw: 0,
            date: Date(timeIntervalSince1970: 123))

        let record = CoinbaseWalletTransactionRecord(transaction: transaction)

        XCTAssertEqual(record.txHashData, Data([0x00, 0x01, 0x02]))
        XCTAssertEqual(record.txHashHexString, "020100")
    }

    func testFallbackRequiresReceivedDirectionAddressAmountAndMinimumTimestamp() {
        let walletId = Data([0x01])
        let pending = makePending(walletId: walletId)
        let matching = makeRecord(id: 1)
        let candidates = [
            makeRecord(id: 2, direction: .sent),
            makeRecord(id: 3, address: "wrong-address"),
            makeRecord(id: 4, amount: 999),
            makeRecord(id: 5, timestamp: 99),
            matching,
        ]

        XCTAssertEqual(
            CoinbaseTransactionMetadataResolver.matchingTransaction(
                for: pending,
                in: candidates),
            matching)
    }

    func testFallbackChoosesEarliestTimestamp() {
        let pending = makePending()
        let later = makeRecord(id: 1, displayHash: "01", timestamp: 200)
        let earlier = makeRecord(id: 2, displayHash: "ff", timestamp: 150)

        XCTAssertEqual(
            CoinbaseTransactionMetadataResolver.matchingTransaction(
                for: pending,
                in: [later, earlier]),
            earlier)
    }

    func testFallbackBreaksTimestampTieByDisplayTxid() {
        let pending = makePending()
        let greaterHash = makeRecord(id: 1, displayHash: "bb", timestamp: 150)
        let lesserHash = makeRecord(id: 2, displayHash: "aa", timestamp: 150)

        XCTAssertEqual(
            CoinbaseTransactionMetadataResolver.matchingTransaction(
                for: pending,
                in: [greaterHash, lesserHash]),
            lesserHash)
    }

    func testResolutionDoesNotReuseOneTransaction() {
        let walletId = Data([0x01])
        let pending = makePending(walletId: walletId)
        let transaction = makeRecord(id: 1)
        let snapshot = CoinbaseWalletTransactionSnapshot(
            walletId: walletId,
            transactions: [transaction])

        let resolution = CoinbaseTransactionMetadataResolver.resolve(
            pendingTransfers: [pending, pending],
            against: snapshot)

        XCTAssertEqual(resolution.matchedTxHashes, [transaction.txHashData])
        XCTAssertEqual(resolution.unresolved, [pending])
    }

    func testFallbackTransferKeepsOriginatingWalletIdUntilLaterSnapshot() throws {
        let walletId = Data([0x01])
        let response = Data(
            """
            {
              "amount": { "amount": "0.00000100", "currency": "DASH" },
              "created_at": "1970-01-01T00:01:40Z",
              "to": { "address": "Xreceive" }
            }
            """.utf8)
        let transaction = try JSONDecoder().decode(CoinbaseTransaction.self, from: response)
        let pending = try XCTUnwrap(
            CoinbaseTransactionMetadataTagger.pendingReceiveTransfer(
                from: transaction,
                walletId: walletId))
        XCTAssertEqual(pending.walletId, walletId)

        let emptySnapshot = CoinbaseWalletTransactionSnapshot(
            walletId: walletId,
            transactions: [])

        let first = CoinbaseTransactionMetadataResolver.resolve(
            pendingTransfers: [pending],
            against: emptySnapshot)
        XCTAssertEqual(first.unresolved, [pending])

        let transaction = makeRecord(id: 1)
        let second = CoinbaseTransactionMetadataResolver.resolve(
            pendingTransfers: first.unresolved,
            against: CoinbaseWalletTransactionSnapshot(
                walletId: walletId,
                transactions: [transaction]))

        XCTAssertEqual(second.matchedTxHashes, [transaction.txHashData])
        XCTAssertTrue(second.unresolved.isEmpty)
    }

    func testPendingTransferIsIsolatedByWalletId() {
        let firstWallet = Data([0x01])
        let secondWallet = Data([0x02])
        let pending = makePending(walletId: firstWallet)
        let transaction = makeRecord(id: 1)

        let wrongWallet = CoinbaseTransactionMetadataResolver.resolve(
            pendingTransfers: [pending],
            against: CoinbaseWalletTransactionSnapshot(
                walletId: secondWallet,
                transactions: [transaction]))
        XCTAssertTrue(wrongWallet.matchedTxHashes.isEmpty)
        XCTAssertEqual(wrongWallet.unresolved, [pending])

        let originalWallet = CoinbaseTransactionMetadataResolver.resolve(
            pendingTransfers: wrongWallet.unresolved,
            against: CoinbaseWalletTransactionSnapshot(
                walletId: firstWallet,
                transactions: [transaction]))
        XCTAssertEqual(originalWallet.matchedTxHashes, [transaction.txHashData])
        XCTAssertTrue(originalWallet.unresolved.isEmpty)
    }

    func testMetadataFiltersToCoinbaseRowsPresentInActiveWallet() {
        let includedHash = Data([0x01])
        let staleHash = Data([0x02])
        let otherServiceHash = Data([0x03])
        let stored = [
            makeMetadata(txHash: includedHash, service: ServiceName.coinbase.rawValue),
            makeMetadata(txHash: staleHash, service: ServiceName.coinbase.rawValue),
            makeMetadata(txHash: otherServiceHash, service: "other"),
        ]
        let snapshot = CoinbaseWalletTransactionSnapshot(
            walletId: Data([0x01]),
            transactions: [
                makeRecord(id: 1, txHashData: includedHash),
                makeRecord(id: 3, txHashData: otherServiceHash),
            ])

        let resolved = CoinbaseMetadataProvider.resolveMetadata(
            storedMetadata: stored,
            walletSnapshot: snapshot)

        XCTAssertEqual(Set(resolved.keys), Set([includedHash]))
        XCTAssertEqual(
            resolved[includedHash]?.iconName,
            .custom("transaction-coinbase.received", bundle: .dashUIKit))
    }

    func testMetadataUsesSentAndReceivedSecondaryIcons() {
        let receivedHash = Data([0x01])
        let sentHash = Data([0x02])
        let stored = [
            makeMetadata(txHash: receivedHash, service: ServiceName.coinbase.rawValue),
            makeMetadata(txHash: sentHash, service: ServiceName.coinbase.rawValue),
        ]
        let snapshot = CoinbaseWalletTransactionSnapshot(
            walletId: Data([0x01]),
            transactions: [
                makeRecord(id: 1, txHashData: receivedHash, direction: .received),
                makeRecord(id: 2, txHashData: sentHash, direction: .sent),
            ])

        let resolved = CoinbaseMetadataProvider.resolveMetadata(
            storedMetadata: stored,
            walletSnapshot: snapshot)

        XCTAssertEqual(
            resolved[receivedHash]?.secondaryIcon,
            .custom("additional-info-received", bundle: .dashUIKit))
        XCTAssertEqual(
            resolved[sentHash]?.secondaryIcon,
            .custom("additional-info-sent", bundle: .dashUIKit))
    }

    func testMetadataIsEmptyWithoutAnActiveWalletSnapshot() {
        let metadata = makeMetadata(
            txHash: Data([0x01]),
            service: ServiceName.coinbase.rawValue)

        XCTAssertTrue(
            CoinbaseMetadataProvider.resolveMetadata(
                storedMetadata: [metadata],
                walletSnapshot: nil)
                .isEmpty)
    }

    private func makePending(
        walletId: Data = Data([0x01]),
        address: String = "Xreceive",
        amount: UInt64 = 100,
        minimumTimestamp: TimeInterval = 100
    ) -> CoinbasePendingReceiveTransfer {
        CoinbasePendingReceiveTransfer(
            walletId: walletId,
            address: address,
            amount: amount,
            minimumTimestamp: minimumTimestamp)
    }

    private func makeRecord(
        id: UInt8,
        txHashData: Data? = nil,
        displayHash: String? = nil,
        direction: CoinbaseWalletTransactionDirection = .received,
        timestamp: TimeInterval = 150,
        address: String = "Xreceive",
        amount: UInt64 = 100
    ) -> CoinbaseWalletTransactionRecord {
        CoinbaseWalletTransactionRecord(
            txHashData: txHashData ?? Data([id]),
            txHashHexString: displayHash ?? String(format: "%02x", id),
            direction: direction,
            timestamp: timestamp,
            outputReceiveAddresses: [address],
            dashAmount: amount)
    }

    private func makeMetadata(txHash: Data, service: String) -> TransactionMetadata {
        var metadata = TransactionMetadata(txHash: txHash)
        metadata.service = service
        return metadata
    }
}
