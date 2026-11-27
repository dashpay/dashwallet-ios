//
//  Created by Roman Chornyi
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

@testable import dashpay
import SwiftDashSDK
import SwiftData
import XCTest

/// Every asset lock that records whom it pays reads by whose the recipient is, as a Core → Shielded send already
/// does: a Core → Identity top-up (type 2) and a Core → Platform payment (type 4) to someone else read as "Sent" with
/// the recipient, an own recipient keeps the own-transfer reading, and one whose owner cannot be told now is named
/// neither.
final class ExternalAssetLockSendHistoryTests: XCTestCase {
    private typealias Info = ShieldedTxLookup.ShieldedLockInfo

    private let txidWire = Data((0..<32).map { UInt8(0x90 + $0) })
    private let walletId = Data(repeating: 1, count: 32)
    private let identityId = Data(repeating: 9, count: 32)
    private static let platformStorage = Data([0]) + Data(repeating: 0xEE, count: 20)
    private let amount: UInt64 = 1_050_500

    private var txidHex: String { Transaction.displayHex(txidWire).lowercased() }
    private var identityAddress: String { ScriptAddressCodec.base58Encode(identityId) }
    private var platformAddress: String {
        Bech32m.bech32mPayload(fromStorageBytes: Self.platformStorage)
            .flatMap { Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: false), data: $0) } ?? ""
    }

    private func identityLock(_ identity: Data?, fundingType: Int = 2,
                              status: Int = AssetLockRecoveryService.consumedStatus) -> Info {
        Info(amountDuffs: amount, statusRaw: status, vout: 0,
             fundingTypeRaw: fundingType, walletId: walletId, drainOperation: nil, identityRecipient: identity)
    }

    private func platformLock(recorded: Bool, status: Int = AssetLockRecoveryService.consumedStatus) -> Info {
        Info(amountDuffs: amount, statusRaw: status, vout: 0,
             fundingTypeRaw: 4, walletId: walletId, drainOperation: nil, hasPlatformAddressRecipients: recorded)
    }

    /// `isOwn` answers for the identity and the Platform address alike; `platform` is what the lock's recorded
    /// Platform recipients read as (nil: unreadable now).
    @MainActor
    private func resolved(
        _ info: Info, isOwn: Bool?, platform: [Data]? = [ExternalAssetLockSendHistoryTests.platformStorage]
    ) -> Info {
        let recipients = platform
        let map = ShieldedTxLookup.resolvingIdentityAndPlatformRecipients(
            of: [txidHex: info], mainnet: false,
            isOwnIdentity: { _, _ in isOwn },
            platformRecipients: { _, _ in recipients },
            isOwnPlatformAddress: { _, _ in isOwn })
        return map[txidHex] ?? info
    }

    @MainActor
    private func withLock(_ info: Info, _ body: (Transaction) -> Void) {
        let lookup = ShieldedTxLookup.shared
        let saved = Dictionary(uniqueKeysWithValues: lookup.allEntries().map { ($0.txidHex, $0.info) })
        defer { lookup.store(saved) }
        lookup.store([txidHex: info])
        body(Transaction(syntheticTxid: txidWire, directionRaw: 2, netAmount: -1_000, fee: 1_000, contextRaw: 3,
                         date: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    // MARK: - The choke point

    @MainActor
    func testAnIdentityRecipientIsOwnExternalOrUndecided() {
        XCTAssertEqual(resolved(identityLock(identityId), isOwn: true).recipient, .own)
        XCTAssertEqual(resolved(identityLock(identityId), isOwn: false).recipient,
                       .external(address: identityAddress))
        XCTAssertEqual(resolved(identityLock(identityId), isOwn: nil).recipient,
                       .undecided(address: identityAddress))
    }

    @MainActor
    func testAPlatformRecipientIsOwnExternalOrUndecided() {
        XCTAssertEqual(resolved(platformLock(recorded: true), isOwn: true).recipient, .own)
        XCTAssertEqual(resolved(platformLock(recorded: true), isOwn: false).recipient,
                       .external(address: platformAddress))
        XCTAssertEqual(resolved(platformLock(recorded: true), isOwn: nil).recipient,
                       .undecided(address: platformAddress))
    }

    @MainActor
    func testALockThatRecordedNoRecipientKeepsNoAnswer() {
        XCTAssertNil(resolved(identityLock(nil), isOwn: false).recipient)
        XCTAssertNil(resolved(identityLock(identityId, fundingType: 1), isOwn: false).recipient, "a bound top-up")
        XCTAssertNil(resolved(platformLock(recorded: false), isOwn: false).recipient)
        XCTAssertNil(resolved(platformLock(recorded: true), isOwn: false, platform: []).recipient)
        XCTAssertNil(resolved(platformLock(recorded: true), isOwn: false, platform: nil).recipient,
                     "recipients that cannot be read now")
    }

    // MARK: - Transaction: every reader takes the same fact

    @MainActor
    func testAPaymentToSomeoneElseReadsAsSent() {
        for (info, address) in [(resolved(identityLock(identityId), isOwn: false), identityAddress),
                                (resolved(platformLock(recorded: true), isOwn: false), platformAddress)] {
            withLock(info) { tx in
                XCTAssertEqual(tx.assetLockRecipientAddress, address)
                XCTAssertNil(tx.internalTransferRoute)
                XCTAssertEqual(tx.direction, .sent)
                XCTAssertEqual(tx.stateTitle, String(localized: "Sent", comment: ""))
                XCTAssertEqual(tx.signedDashAmount, -Int64(amount))
                XCTAssertEqual(tx.defaultTaxCategory, .transferOut)
                XCTAssertEqual(HomeTransactionRoute.details(of: tx), ShieldedActivityItem.shortAddress(address))
            }
        }
    }

    /// Platform credits the recipient when it consumes the lock: until then the payment is sending.
    @MainActor
    func testAPaymentWhoseLockIsNotConsumedReadsAsSending() {
        for info in [identityLock(identityId, status: 2), platformLock(recorded: true, status: 2)] {
            withLock(resolved(info, isOwn: false)) { tx in
                XCTAssertEqual(tx.direction, .sent)
                XCTAssertEqual(tx.stateTitle, String(localized: "Sending", comment: ""))
            }
        }
    }

    /// An owner that cannot be told now is named neither a payment nor an own transfer.
    @MainActor
    func testAnUndecidedIdentityOrPlatformRecipientIsNamedNeither() {
        withLock(resolved(identityLock(identityId), isOwn: nil)) { tx in
            XCTAssertEqual(tx.assetLockRecipientAddress, identityAddress)
            XCTAssertNil(tx.internalTransferRoute)
            XCTAssertEqual(tx.stateTitle, String(localized: "Identity transfer", comment: ""))
        }
        withLock(resolved(platformLock(recorded: true), isOwn: nil)) { tx in
            XCTAssertEqual(tx.assetLockRecipientAddress, platformAddress)
            XCTAssertNil(tx.internalTransferRoute)
            XCTAssertEqual(tx.stateTitle, String(localized: "Platform transfer", comment: ""))
        }
    }

    @MainActor
    func testOwnFundingsKeepTheirReading() {
        for info in [resolved(identityLock(identityId), isOwn: true),
                     resolved(identityLock(identityId, fundingType: 1), isOwn: false)] {
            withLock(info) { tx in
                XCTAssertNil(tx.assetLockRecipientAddress)
                XCTAssertEqual(tx.internalTransferRoute, .coreToIdentity)
                XCTAssertEqual(tx.stateTitle, String(localized: "Identity top-up", comment: ""))
            }
        }
        for info in [resolved(platformLock(recorded: true), isOwn: true), platformLock(recorded: false)] {
            withLock(info) { tx in
                XCTAssertNil(tx.assetLockRecipientAddress)
                XCTAssertEqual(tx.internalTransferRoute, .coreToPlatform)
                XCTAssertEqual(tx.defaultTaxCategory, .internalTransfer)
            }
        }
    }

    // MARK: - The lookup reads a lock from its own save

    /// The pair run's order: the SDK saves the lock row with its recipient before it broadcasts, the funding
    /// transaction's History row appears at the broadcast, and the next shielded sync, until now the only refresh
    /// that read the new lock, comes up to a minute later. The lock's own save must make the lookup read it.
    @MainActor
    func testEachExternalLockReadsAsASendFromItsOwnSave() async throws {
        let schema = DashModelContainer.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let storage = Self.platformStorage
        let lookup = ShieldedTxLookup(source: .init(
            activeContainer: { container },
            buildSnapshot: ShieldedTxLookup.RefreshSource.live.buildSnapshot,
            isMainnet: { false },
            isOwnIdentity: { _, _ in false },
            platformRecipients: { _, _ in [storage] },
            isOwnPlatformAddress: { _, _ in false }))
        lookup.refreshOnAssetLockSaves()
        defer { lookup.stopRefreshingOnAssetLockSaves() }
        await lookup.refresh(reason: "test-start")

        let platformTxid = String(repeating: "a1", count: 32)
        let identityTxid = String(repeating: "b2", count: 32)
        for (txid, row) in [
            (platformTxid, PersistentAssetLock(
                outPointHex: "\(platformTxid):0", walletId: walletId, transactionBytes: Data(), fundingTypeRaw: 4,
                identityIndexRaw: 0, amountDuffs: Int64(amount), statusRaw: 1, platformAddressRecipients: Data([1]))),
            (identityTxid, PersistentAssetLock(
                outPointHex: "\(identityTxid):0", walletId: walletId, transactionBytes: Data(), fundingTypeRaw: 2,
                identityIndexRaw: 0, amountDuffs: Int64(amount), statusRaw: 1, identityRecipient: identityId)),
        ] {
            XCTAssertNil(lookup.allEntries().first { $0.txidHex == txid }, "not tracked before its save")
            let published = expectation(forNotification: .shieldedTxLookupDidChange, object: lookup)
            container.mainContext.insert(row)
            try container.mainContext.save()
            await fulfillment(of: [published], timeout: 2)
        }

        XCTAssertEqual(lookup.platformFundingInfo(forTxidHex: platformTxid)?.recipient,
                       .external(address: platformAddress))
        XCTAssertEqual(lookup.identityFundingInfo(forTxidHex: identityTxid)?.recipient,
                       .external(address: identityAddress))
    }

    // MARK: - The remainder of a payment to someone else's Platform address

    private typealias Recipient = ManagedPlatformAddressWallet.FundFromAssetLockRecipient

    /// The pair run's numbers: a 0.01 DASH payment in a 0.01062 lock, of which 0.00046 came back.
    private let lockDuffs: Int64 = 1_062_000
    private let paidCredits: UInt64 = 1_000_000 * 1_000
    private let remainderCredits: UInt64 = 46_000 * 1_000
    /// Two of the wallet's own P2PKH Platform addresses, encoded the way the wallet derives them.
    private let ownAddresses = [UInt8(0xA1), 0xA2].map { byte in
        Bech32m.bech32mPayload(fromStorageBytes: Data([0]) + Data(repeating: byte, count: 20))
            .flatMap { Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: false), data: $0) } ?? ""
    }

    private func storage(_ address: String) throws -> Data {
        try XCTUnwrap(AddressTransformer.parseAddress(address))
    }

    /// Someone else's address gets the amount, `remainderTo` the rest.
    private func recipients(remainderTo address: String) throws -> [Recipient] {
        let own = try storage(address)
        return [Recipient(addressType: 0, hash: Data(repeating: 0xEE, count: 20), credits: paidCredits),
                Recipient(addressType: own[0], hash: own.dropFirst(), credits: nil)]
    }

    private struct RemainderWallet {
        let walletId = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let container: ModelContainer
        var balances: [String: UInt64] = [:]
        var lockRecipients: [String: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient]] = [:]

        var received: [Int64] {
            PlatformAddressActivityDAO.shared
                .activities(walletId: walletId, networkRaw: Int64(Network.testnet.rawValue))
                .map(\.amountDuffs).sorted()
        }
    }

    @MainActor
    private func remainderWallet(addresses: [String]) throws -> RemainderWallet {
        let schema = DashModelContainer.schema
        var wallet = RemainderWallet(container: try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]))
        for address in addresses { wallet.balances[address] = 0 }
        observe(&wallet, [:]) // seeds the baseline
        return wallet
    }

    /// A lock that paid someone else's Platform address and recorded `recipients`.
    @MainActor
    private func addLock(_ wallet: inout RemainderWallet, txidByte: UInt8, recipients: [Recipient]) throws {
        let txidWire = Data(repeating: txidByte, count: 32)
        let outPoint = "\(Transaction.displayHex(txidWire)):0"
        wallet.container.mainContext.insert(PersistentAssetLock(
            outPointHex: outPoint, walletId: wallet.walletId, transactionBytes: Data(), fundingTypeRaw: 4,
            identityIndexRaw: 0, amountDuffs: lockDuffs, statusRaw: 4, platformAddressRecipients: Data([1])))
        try wallet.container.mainContext.save()
        wallet.lockRecipients[txidWire.base64EncodedString()] = recipients
    }

    /// One BLAST pass that adds `increases` (credits) to the wallet's addresses.
    @MainActor
    private func observe(_ wallet: inout RemainderWallet, _ increases: [String: UInt64]) {
        for (address, credits) in increases { wallet.balances[address, default: 0] += credits }
        let lockRecipients = wallet.lockRecipients
        PlatformAddressActivityRecorder.observe(
            addresses: wallet.balances.map { address, balance in
                DerivedPlatformAddress(
                    address: address, accountIndex: 0, addressIndex: 0, isUsed: true, balance: balance)
            },
            walletId: wallet.walletId, network: .testnet, container: wallet.container,
            recordedLockRecipients: { txid, _ in lockRecipients[txid.base64EncodedString()] })
    }

    @MainActor
    func testTheRemainderOfAPaymentToAnotherPlatformAddressIsNoReceipt() throws {
        var wallet = try remainderWallet(addresses: [ownAddresses[0]])
        try addLock(&wallet, txidByte: 0x41, recipients: recipients(remainderTo: ownAddresses[0]))
        observe(&wallet, [ownAddresses[0]: remainderCredits])
        XCTAssertEqual(wallet.received, [], "the lock's own remainder adds no Received row")
    }

    @MainActor
    func testTheRecipientOfSuchAPaymentStillReceivesIt() throws {
        // The receiving wallet holds no lock of the payment.
        var wallet = try remainderWallet(addresses: [ownAddresses[1]])
        observe(&wallet, [ownAddresses[1]: paidCredits])
        XCTAssertEqual(wallet.received, [1_000_000])

        // Nor does a lock whose remainder went to another address explain it.
        var sender = try remainderWallet(addresses: ownAddresses)
        try addLock(&sender, txidByte: 0x42, recipients: recipients(remainderTo: ownAddresses[0]))
        observe(&sender, [ownAddresses[1]: remainderCredits])
        XCTAssertEqual(sender.received, [46_000])
    }

    @MainActor
    func testAnUnrelatedIncreaseOnTheRemainderAddressIsStillReceived() throws {
        var wallet = try remainderWallet(addresses: [ownAddresses[0]])
        try addLock(&wallet, txidByte: 0x43, recipients: recipients(remainderTo: ownAddresses[0]))
        observe(&wallet, [ownAddresses[0]: 100_000 * 1_000])
        XCTAssertEqual(wallet.received, [100_000], "more than the lock kept beyond the payment")

        observe(&wallet, [ownAddresses[0]: remainderCredits])
        observe(&wallet, [ownAddresses[0]: remainderCredits])
        XCTAssertEqual(wallet.received, [46_000, 100_000], "one remainder hides one increase")
    }

    @MainActor
    func testTwoLocksHideTheirOwnRemaindersOnly() throws {
        var wallet = try remainderWallet(addresses: ownAddresses)
        try addLock(&wallet, txidByte: 0x44, recipients: recipients(remainderTo: ownAddresses[0]))
        try addLock(&wallet, txidByte: 0x45, recipients: recipients(remainderTo: ownAddresses[1]))
        observe(&wallet, [ownAddresses[0]: remainderCredits, ownAddresses[1]: remainderCredits + 1_000])
        observe(&wallet, [ownAddresses[0]: remainderCredits])
        XCTAssertEqual(wallet.received, [46_000], "each lock hides one remainder; the third increase is received")
    }
}
