//
//  SwiftDashSDKTransactionSender.swift
//  DashWallet
//
//  Wraps SwiftDashSDK's two-step send flow (build+sign → broadcast) in a
//  thin adapter that the rest of dashwallet-ios can call without importing
//  SwiftDashSDK directly.
//
//  Build+sign is atomic in SwiftDashSDK — `WalletManager.buildSignedTransaction`
//  signs the transaction using keys already loaded in FFI memory from app
//  launch. No PIN or biometric auth is needed at this layer; authentication
//  is a UI-level gate that callers enforce before calling `broadcast`.
//
//  This file intentionally does NOT import DashSync.
//

import CommonCrypto
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@objc(DWSwiftDashSDKTransactionSender)
final class SwiftDashSDKTransactionSender: NSObject {

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.transaction-sender")

    // MARK: - Build & Sign

    /// Build and sign a transaction that sends `amount` duffs to `address`.
    ///
    /// Uses the first `HDWallet` in SwiftData and account index 0 (primary
    /// BIP44 account). Fee is calculated automatically by the FFI at
    /// 1000 duffs/kB.
    ///
    /// The returned transaction is signed but NOT broadcast — call
    /// `broadcast(_:)` separately after the caller has authenticated the
    /// user.
    ///
    /// - Parameters:
    ///   - address: Destination Dash address (Base58Check).
    ///   - amount: Amount to send in duffs (1 DASH = 100_000_000 duffs).
    /// - Returns: Tuple of (serialized signed tx bytes, fee in duffs, 32-byte txHash).
    static func buildAndSign(address: String, amount: UInt64) throws -> (txData: Data, fee: UInt64, txHash: Data) {
        guard !address.isEmpty else {
            throw SendError.invalidInput("Empty address")
        }
        guard amount > 0 else {
            throw SendError.invalidInput("Amount must be greater than zero")
        }

        // 1. Fetch the HDWallet from SwiftData.
        let wallet = try fetchWallet()

        // 2. Get WalletManager from the running SPV coordinator.
        let walletManager = try SwiftDashSDKSPVCoordinator.shared.getWalletManager()

        // 3. Build + sign (atomic — keys already in FFI memory).
        let output = TxOutput(address: address, amount: amount)
        let (txData, fee) = try walletManager.buildSignedTransaction(
            for: wallet,
            accIndex: 0,
            outputs: [output])

        // 4. Compute txHash (double SHA-256, reversed — standard Bitcoin/Dash).
        let txHash = computeTxHash(from: txData)

        logger.info("💸 TXSEND :: built and signed tx: fee=\(fee, privacy: .public) txHash=\(txHash.map { String(format: "%02x", $0) }.joined(), privacy: .public)")

        return (txData: txData, fee: fee, txHash: txHash)
    }

    // MARK: - Broadcast

    /// Broadcast a previously-signed transaction via the SPV network.
    ///
    /// Callers must authenticate the user (PIN / biometric) before calling
    /// this method. The signed transaction bytes come from `buildAndSign`.
    ///
    /// - Parameter txData: Serialized signed transaction bytes.
    static func broadcast(_ txData: Data) throws {
        logger.info("💸 TXSEND :: broadcasting \(txData.count, privacy: .public)-byte transaction")
        try SwiftDashSDKSPVCoordinator.shared.broadcastTransaction(txData)
        logger.info("💸 TXSEND :: broadcast succeeded")
    }

    // MARK: - Helpers

    /// Fetch the first `HDWallet` record from SwiftData.
    private static func fetchWallet() throws -> HDWallet {
        guard let modelContainer = SwiftDashSDKContainer.modelContainer else {
            throw SendError.walletNotReady("SwiftData container not initialized")
        }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<HDWallet>()
        let wallets = try context.fetch(descriptor)
        guard let wallet = wallets.first else {
            throw SendError.walletNotReady("No HDWallet record found")
        }
        return wallet
    }

    /// Compute txHash from raw transaction bytes.
    ///
    /// Standard Bitcoin/Dash txid: double SHA-256, byte-reversed.
    /// Matches `SendViewModel.computeTxid` in the SwiftDashSDK example app.
    private static func computeTxHash(from txData: Data) -> Data {
        var hash1 = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        var hash2 = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        txData.withUnsafeBytes { ptr in
            hash1.withUnsafeMutableBytes { out in
                _ = CC_SHA256(ptr.baseAddress, CC_LONG(txData.count), out.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        hash1.withUnsafeBytes { ptr in
            hash2.withUnsafeMutableBytes { out in
                _ = CC_SHA256(ptr.baseAddress, CC_LONG(hash1.count), out.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return Data(hash2.reversed())
    }

    // MARK: - Obj-C bridge

    /// Build+sign accessible from Obj-C. Returns a dictionary with keys
    /// "txData" (Data), "fee" (NSNumber), "txHash" (Data).
    @objc(objcBuildAndSignWithAddress:amount:error:)
    static func objcBuildAndSign(address: String, amount: UInt64) throws -> NSDictionary {
        let (txData, fee, txHash) = try buildAndSign(address: address, amount: amount)
        return [
            "txData": txData,
            "fee": NSNumber(value: fee),
            "txHash": txHash
        ]
    }

    /// Broadcast accessible from Obj-C.
    @objc(objcBroadcast:error:)
    static func objcBroadcast(_ txData: Data) throws {
        try broadcast(txData)
    }

    // MARK: - Errors

    enum SendError: LocalizedError {
        case invalidInput(String)
        case walletNotReady(String)

        var errorDescription: String? {
            switch self {
            case .invalidInput(let reason):
                return "Invalid transaction input: \(reason)"
            case .walletNotReady(let reason):
                return "Wallet not ready: \(reason)"
            }
        }
    }
}
