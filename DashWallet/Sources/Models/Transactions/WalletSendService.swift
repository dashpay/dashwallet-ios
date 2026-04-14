//
//  WalletSendService.swift
//  DashWallet
//
//  Shared send boundary for standard SwiftDashSDK sends and the remaining
//  DashSync-only selected-input fallback.
//

import Foundation
import OSLog

@objc(DWPreparedStandardSend)
final class PreparedStandardSend: NSObject {
    @objc let txData: Data
    @objc let txHash: Data
    @objc let fee: UInt64
    @objc let transaction: DSTransaction
    @objc let address: String
    @objc let amount: UInt64

    init(
        txData: Data,
        txHash: Data,
        fee: UInt64,
        transaction: DSTransaction,
        address: String,
        amount: UInt64
    ) {
        self.txData = txData
        self.txHash = txHash
        self.fee = fee
        self.transaction = transaction
        self.address = address
        self.amount = amount
    }

    @objc(broadcastAndReturnError:)
    func broadcast() throws {
        try SwiftDashSDKTransactionSender.broadcast(txData)
    }
}

@objc(DWWalletSendService)
final class WalletSendService: NSObject {
    @objc(sharedService) static let shared = WalletSendService()

    fileprivate static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-send-service")

    private let sendAuthorizer = SendAuthorizer()
    private let legacySelectedInputSendExecutor = LegacySelectedInputSendExecutor()

    private override init() {
        super.init()
    }

    func prepareStandardSendForConfirmation(address: String, amount: UInt64) async throws -> PreparedStandardSend {
        Self.logger.info("💸 TXSEND :: preparing standard send to \(address, privacy: .public) amount=\(amount, privacy: .public)")
        try await sendAuthorizer.authorizeSend()
        let prepared = try buildPreparedStandardSend(address: address, amount: amount)
        Self.logger.info("💸 TXSEND :: standard send prepared, fee=\(prepared.fee, privacy: .public)")
        return prepared
    }

    func send(
        address: String,
        amount: UInt64,
        inputSelector: SingleInputAddressSelector? = nil,
        adjustAmountDownwards: Bool = false
    ) async throws -> DSTransaction {
        if let inputSelector {
            Self.logger.info("💸 TXSEND :: routing to selected-input (DashSync) path for \(address, privacy: .public)")
            try await sendAuthorizer.authorizeSend()
            return try await legacySelectedInputSendExecutor.send(
                address: address,
                amount: amount,
                inputSelector: inputSelector,
                adjustAmountDownwards: adjustAmountDownwards
            )
        }

        let preparedSend = try await prepareStandardSendForConfirmation(address: address, amount: amount)
        try preparedSend.broadcast()
        return preparedSend.transaction
    }

    @objc(prepareStandardSendForConfirmationWithAddress:amount:completion:)
    func prepareStandardSendForConfirmation(
        address: String,
        amount: UInt64,
        completion: @escaping (PreparedStandardSend?, NSError?) -> Void
    ) {
        Task {
            do {
                let preparedSend = try await prepareStandardSendForConfirmation(address: address, amount: amount)
                await MainActor.run {
                    completion(preparedSend, nil)
                }
            } catch {
                await MainActor.run {
                    completion(nil, error as NSError)
                }
            }
        }
    }

    @objc(isAuthenticationCancelledError:)
    static func isAuthenticationCancelledError(_ error: NSError) -> Bool {
        error.domain == errorDomain && error.code == ErrorCode.authenticationCancelled.rawValue
    }

    private func buildPreparedStandardSend(address: String, amount: UInt64) throws -> PreparedStandardSend {
        let (txData, fee, txHash) = try SwiftDashSDKTransactionSender.buildAndSign(address: address, amount: amount)
        let chain = DWEnvironment.sharedInstance().currentChain
        let transaction = DSTransaction(message: txData, on: chain)

        return PreparedStandardSend(
            txData: txData,
            txHash: txHash,
            fee: fee,
            transaction: transaction,
            address: address,
            amount: amount
        )
    }
}

private final class SendAuthorizer {
    @MainActor
    func authorizeSend() async throws {
        let result = await withCheckedContinuation { continuation in
            DSAuthenticationManager.sharedInstance().authenticate(
                withPrompt: nil,
                usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
                alertIfLockout: true
            ) { authenticatedOrSuccess, _, cancelled in
                if cancelled {
                    continuation.resume(returning: AuthorizationResult.cancelled)
                } else if authenticatedOrSuccess {
                    continuation.resume(returning: AuthorizationResult.authorized)
                } else {
                    continuation.resume(returning: AuthorizationResult.failed)
                }
            }
        }

        switch result {
        case .authorized:
            WalletSendService.logger.info("💸 TXSEND :: user authorized send")
            return
        case .cancelled:
            WalletSendService.logger.info("💸 TXSEND :: user cancelled authentication")
            throw WalletSendService.makeError(
                code: .authenticationCancelled,
                description: "Authentication cancelled"
            )
        case .failed:
            WalletSendService.logger.error("💸 TXSEND :: authentication failed")
            throw WalletSendService.makeError(
                code: .authenticationFailed,
                description: "Authentication failed"
            )
        }
    }

    private enum AuthorizationResult {
        case authorized
        case cancelled
        case failed
    }
}

private final class LegacySelectedInputSendExecutor {
    func send(
        address: String,
        amount: UInt64,
        inputSelector: SingleInputAddressSelector,
        adjustAmountDownwards: Bool
    ) async throws -> DSTransaction {
        let chain = DWEnvironment.sharedInstance().currentChain
        let account = DWEnvironment.sharedInstance().currentAccount
        let transactionManager = DWEnvironment.sharedInstance().currentChainManager.transactionManager
        let transaction = DSTransaction(on: chain)

        let balance = inputSelector.selectFor(tx: transaction)
        transaction.addOutputAddress(address, amount: amount)
        let feeAmount = chain.fee(forTxSize: UInt(transaction.size) + UInt(TX_OUTPUT_SIZE))

        if amount + feeAmount > balance {
            if adjustAmountDownwards && amount > feeAmount {
                return try await send(
                    address: address,
                    amount: amount - feeAmount,
                    inputSelector: inputSelector,
                    adjustAmountDownwards: false
                )
            }

            throw WalletSendService.makeError(
                code: .insufficientSelectedFunds,
                description: "Not enough funds. Selected: \(balance), Amount: \(amount), Fee: \(feeAmount)"
            )
        }

        let change = balance - (amount + feeAmount)
        if change > 0 {
            transaction.addOutputAddress(inputSelector.address, amount: change)
            transaction.sortOutputsAccordingToBIP69()
        }

        account.sign(transaction)
        account.register(transaction, saveImmediately: false)
        WalletSendService.logger.info("💸 TXSEND :: publishing selected-input tx via DashSync")
        try await transactionManager.publishTransaction(transaction)
        return transaction
    }
}

private extension WalletSendService {
    enum ErrorCode: Int {
        case authenticationCancelled = 1
        case authenticationFailed = 2
        case insufficientSelectedFunds = 3
    }

    static let errorDomain = "org.dashfoundation.dash.wallet-send-service"

    static func makeError(code: ErrorCode, description: String) -> NSError {
        NSError(
            domain: errorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}
