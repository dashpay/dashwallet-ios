//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
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


import AuthenticationServices
import Combine
import Foundation

let kDashAccount = "DASH"

let kCoinbaseContactURL = URL(string: "https://help.coinbase.com/en/contact-us")!
let kCoinbaseAddPaymentMethodsURL = URL(string: "https://www.coinbase.com/settings/linked-accounts")!
let kCoinbaseFeeInfoURL = URL(string: "https://help.coinbase.com/en/coinbase/trading-and-funding/pricing-and-fees/fees")!
let kMaxDashAmountToTransfer: UInt64 = kOneDash
let kMinUSDAmountOrder: Decimal = 1.99
let kMinDashAmountToTransfer: UInt64 = 10_000

// MARK: - CoinbaseObjcWrapper

@objc
class CoinbaseObjcWrapper: NSObject {
    private static var wrapped = Coinbase.shared

    @objc
    static func start() {
        wrapped.initialize()
    }

    @objc
    static func reset() {
        wrapped.reset()
    }
}

// MARK: - Coinbase

class Coinbase {
    public var currencyExchanger: CurrencyExchanger = .init(dataProvider: CoinbaseRatesProvider())

    private lazy var coinbaseService = CoinbaseService()

    private var auth: CBAuth!
    private var accountService: AccountService!
    private var paymentMethodsService: PaymentMethods!

    func initialize() {
        CoinbaseAPI.initialize(with: self)

        auth = CBAuth()
        accountService = AccountService(authInterop: auth)
        paymentMethodsService = PaymentMethods(authInterop: auth)

        currencyExchanger.startExchangeRateFetching()
        prefetchData()
    }

    func reset() {
        Task {
            try await signOut()
        }
    }

    private func prefetchData() {
        Task {
            try await accountService.refreshAccount(kDashAccount)
            _ = try await paymentMethodsService.fetchPaymentMethods()
        }
    }

    static func initialize() {
        shared.initialize()
    }

    public static let shared = Coinbase()
}

extension Coinbase {
    var isAuthorized: Bool { auth.currentUser != nil }

    var currentUserAddressCacheScope: String? {
        guard let accountId = accountService?.dashAccount?.accountId.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountId.isEmpty else {
            return nil
        }

        return accountId
    }

    var paymentMethods: [CoinbasePaymentMethod] {
        get async throws {
            try await paymentMethodsService.fetchPaymentMethods()
        }
    }

    var lastKnownBalance: UInt64? {
        dashAccount?.balance
    }

    var sendLimit: Decimal {
        auth.currentUser?.sendLimit ?? Coinbase.sendLimitAmount
    }

    var dashAccount: CBAccount? {
        accountService.dashAccount
    }
    
    public func getUsdAccount() async -> CBAccount? {
        do {
            return try await accountService.account(by: Coinbase.defaultFiat)
        } catch {
            return nil
        }
    }
}

extension Coinbase {
    @MainActor
    public func signIn(with presentationContext: ASWebAuthenticationPresentationContextProviding) async throws {
        try await auth.signIn(with: presentationContext)
        try await accountService.refreshAccount(kDashAccount)
    }

    public func createNewCoinbaseDashAddress() async throws -> String {
        do {
            let address = try await accountService.retrieveAddress(for: kDashAccount)
            Taxes.shared.mark(address: address, with: .transferOut)
            return address
        } catch Coinbase.Error.userSessionRevoked {
            try await signOut()
            throw Coinbase.Error.userSessionRevoked
        } catch {
            throw error
        }
    }

    public func getDashExchangeRate() async throws -> CoinbaseExchangeRate? {
        do {
            return try await coinbaseService.getCoinbaseExchangeRates(currency: kDashCurrency)
        } catch Coinbase.Error.userSessionRevoked {
            try await signOut()
            throw Coinbase.Error.userSessionRevoked
        } catch {
            throw error
        }
    }

    public func transferFromCoinbaseToDashWallet(amount: UInt64,
                                                 verificationCode: String?,
                                                 idem: UUID?) async throws -> CoinbaseTransaction {
        do {
            let tx = try await accountService.send(from: kDashAccount, amount: amount, verificationCode: verificationCode, idem: idem)

            CoinbaseTransactionMetadataTagger.shared.track(receivedTransfer: tx)

            if let address = tx.to?.address {
                Taxes.shared.mark(address: address, with: .transferIn)
            }
            return tx
        } catch Coinbase.Error.userSessionRevoked {
            try await signOut()
            throw Coinbase.Error.userSessionRevoked
        } catch {
            throw error
        }
    }

    /// Place Buy Order
    ///
    /// - Parameters:
    ///   - amount: Plain amount in Dash
    ///
    /// - Returns: CoinbasePlaceBuyOrder
    ///
    /// - Throws: Coinbase.Error
    ///
    func placeCoinbaseBuyOrder(amount: UInt64) async throws -> CoinbasePlaceBuyOrder {
        do {
            return try await accountService.placeBuyOrder(for: kDashAccount, amount: amount)
        } catch Coinbase.Error.userSessionRevoked {
            try await signOut()
            throw Coinbase.Error.userSessionRevoked
        }
    }
    
    /// Deposit to the fiat account
    ///
    /// - Parameters:
    ///   - paymentMethodId: Id of the payment method with which to make the deposit
    ///   - amount: Plain amount in Dash
    ///
    /// - Throws: Coinbase.Error
    ///
    func depositToFiatAccount(from paymentMethodId: String, amount: UInt64) async throws {
        do {
            try await accountService.deposit(to: Coinbase.defaultFiat, from: paymentMethodId, amount: amount)
        } catch Coinbase.Error.userSessionRevoked {
            try await signOut()
            throw Coinbase.Error.userSessionRevoked
        }
    }

    /// Place trade order
    ///
    /// This method creates an on order to trade between accounts
    ///
    /// - Parameters:
    ///   - origin: Account we use to covert from
    ///   - destination: Account we use to convert to
    ///   - amount: Plain amount in crypto. The amount should be in the same currency as origin's account currency
    ///
    /// - Returns: Order `CoinbaseSwapeTrade`
    ///
    /// - Throws: `Coinbase.Error`
    ///
    ///
    func placeTradeOrder(from origin: CBAccount, to destination: CBAccount, amount: String) async throws -> CoinbaseSwapeTrade {
        do {
            return try await accountService.placeTradeOrder(from: origin, to: destination, amount: amount)
        } catch Coinbase.Error.userSessionRevoked {
            try await signOut()
            throw Coinbase.Error.userSessionRevoked
        } catch {
            throw error
        }
    }

    /// Commit Trade Order
    ///
    /// - Parameters:
    ///   - origin: Instance of `CBAccount` you used in `placeTradeOrder` method to convert from
    ///   - orderID: Order id from `CoinbaseSwapeTrade` you receive by calling `placeTradeOrder`
    ///
    /// - Returns: CoinbasePlaceBuyOrder
    ///
    /// - Throws: Coinbase.Error
    ///
    func commitTradeOrder(origin: CBAccount, orderID: String) async throws -> CoinbaseSwapeTrade {
        do {
            return try await accountService.commitTradeOrder(origin: origin, orderID: orderID)
        } catch Coinbase.Error.userSessionRevoked {
            try await signOut()
            throw Coinbase.Error.userSessionRevoked
        } catch {
            throw error
        }
    }

    public func signOut() async throws {
        guard isAuthorized else {
            return
        }

        try await auth.signOut()
        accountService.removeStoredAccount()
        await MainActor.run {
            ExchangeAddressProvider.clearCoinbaseCache()
        }
    }

    public func accounts() async throws -> [CBAccount] {
        try await accountService.allAccounts()
    }

    /// Returns all crypto accounts regardless of balance.
    /// Used by Maya to find accounts for currencies with zero balance.
    public func accountsIncludingEmpty() async throws -> [CBAccount] {
        try await accountService.allAccountsIncludingEmpty()
    }

    /// Fetches a specific account by currency code (e.g., "BTC", "ETH").
    /// Uses direct `GET /v2/accounts/{currencyCode}` lookup which is more reliable
    /// than listing all accounts when you know the currency you need.
    public func account(byCurrencyCode currencyCode: String) async throws -> CBAccount {
        try await accountService.account(by: currencyCode)
    }

    public func addUserDidChangeListener(_ listener: @escaping UserDidChangeListenerBlock) -> UserDidChangeListenerHandle {
        auth.addUserDidChangeListener(listener)
    }

    public func removeUserDidChangeListener(handle: UserDidChangeListenerHandle) {
        auth.removeUserDidChangeListener(handle: handle)
    }
}

// MARK: - CoinbaseTransactionMetadataTagger

final class CoinbaseTransactionMetadataTagger {
    static let shared = CoinbaseTransactionMetadataTagger()

    private struct PendingReceiveTransfer: Equatable {
        let address: String
        let amount: UInt64
        let minimumTimestamp: TimeInterval
    }

    private let metadataDao = TransactionMetadataDAOImpl.shared
    private let queue = DispatchQueue(label: "CoinbaseTransactionMetadataTagger.queue", qos: .utility)
    // A wallet receive can land before Coinbase's response completes; if createdAt is missing,
    // look back a bounded window so we do not permanently miss the matching transaction.
    private static let receiveLookbackWindow: TimeInterval = 15 * 60
    private var pendingReceiveTransfers: [PendingReceiveTransfer] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resolvePendingReceiveTransfers()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .DSTransactionManagerTransactionStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resolvePendingReceiveTransfers()
            }
            .store(in: &cancellables)
    }

    func track(receivedTransfer transaction: CoinbaseTransaction) {
        if let walletTxHash = walletTxHashData(from: transaction.network?.hash) {
            markCoinbaseTransaction(txHash: walletTxHash)
            return
        }

        guard let address = transaction.to?.address?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty,
              let amount = coinbaseDashAmount(from: transaction.amount),
              amount > 0 else {
            return
        }

        let minimumTimestamp = coinbaseTimestamp(from: transaction.createdAt)
            ?? (Date().timeIntervalSince1970 - Self.receiveLookbackWindow)

        queue.async { [weak self] in
            self?.pendingReceiveTransfers.append(
                PendingReceiveTransfer(address: address, amount: amount, minimumTimestamp: minimumTimestamp)
            )
            self?.resolvePendingReceiveTransfers()
        }
    }

    // txidWire follows the `Transaction.txHashData` convention (wire-order txid),
    // which is exactly what markCoinbaseTransaction keys on.
    func track(sentTransactionTxidWire txidWire: Data) {
        markCoinbaseTransaction(txHash: txidWire)
    }

    private func resolvePendingReceiveTransfers() {
        queue.async { [weak self] in
            guard let self else { return }

            var availableTransactions = DWEnvironment.sharedInstance().currentWallet.allTransactions
            guard !availableTransactions.isEmpty, !self.pendingReceiveTransfers.isEmpty else {
                return
            }

            var unresolved: [PendingReceiveTransfer] = []

            for pending in self.pendingReceiveTransfers {
                guard let match = self.matchingTransaction(
                    for: pending,
                    in: availableTransactions
                ) else {
                    unresolved.append(pending)
                    continue
                }

                self.markCoinbaseTransaction(txHash: match.txHashData)
                if let index = availableTransactions.firstIndex(where: { $0.txHashData == match.txHashData }) {
                    availableTransactions.remove(at: index)
                }
            }

            self.pendingReceiveTransfers = unresolved
        }
    }

    private func matchingTransaction(
        for pending: PendingReceiveTransfer,
        in transactions: [DSTransaction]
    ) -> DSTransaction? {
        let matches = transactions.filter { tx in
            tx.direction == .received
                && tx.timestamp >= pending.minimumTimestamp
                && tx.outputReceiveAddresses.contains(pending.address)
                && tx.dashAmount == pending.amount
        }

        return matches.min(by: { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }

            return lhs.txHashHexString < rhs.txHashHexString
        })
    }

    private func markCoinbaseTransaction(txHash: Data) {
        var metadata = metadataDao.get(by: txHash) ?? TransactionMetadata(txHash: txHash)
        metadata.service = ServiceName.coinbase.rawValue
        metadataDao.update(dto: metadata)
    }

    private func walletTxHashData(from hash: String?) -> Data? {
        guard let hash = hash?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hash.isEmpty,
              let data = Data(hex: hash) else {
            return nil
        }

        return Data(data.reversed())
    }

    private func coinbaseDashAmount(from amount: Amount?) -> UInt64? {
        guard let amountString = amount?.amount,
              let decimal = Decimal(string: amountString, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }

        return decimal.plainDashAmount
    }

    private func coinbaseTimestamp(from createdAt: String?) -> TimeInterval? {
        guard let createdAt = createdAt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !createdAt.isEmpty else {
            return nil
        }

        if let date = Self.iso8601Formatter.date(from: createdAt) {
            return date.timeIntervalSince1970
        }

        return Self.iso8601FractionalFormatter.date(from: createdAt)?.timeIntervalSince1970
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()

    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension String {
    func coinbaseAmount() -> String {
        let locale = Locale(identifier: "en_US")

        guard locale.decimalSeparator != Locale.current.decimalSeparator else {
            return self
        }

        return localizedAmount(locale: locale)
    }
}

// MARK: - Coinbase + CoinbaseAPIAccessTokenProvider

extension Coinbase: CoinbaseAPIAccessTokenProvider {
    var accessToken: String? {
        auth.accessToken
    }

    func refreshTokenIfNeeded() async throws {
        try await auth.refreshTokenIfNeeded()
    }
}
