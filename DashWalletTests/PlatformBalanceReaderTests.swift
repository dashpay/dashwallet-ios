import Foundation
import SwiftData
import SwiftDashSDK
import XCTest
#if canImport(dashwallet)
@testable import dashwallet
#elseif canImport(dashpay)
@testable import dashpay
#else
@testable import ShieldedBalanceHarness
#endif

@MainActor
final class PlatformBalanceReaderTests: XCTestCase {
    private let walletId = Data(repeating: 1, count: 32)

    private func addWallet(to container: ModelContainer, id: Data, network: Network = .testnet, hasAccount: Bool = true) -> PersistentWallet {
        let wallet = PersistentWallet(walletId: id, network: network)
        container.mainContext.insert(wallet)
        if hasAccount {
            let account = PersistentAccount(wallet: wallet, accountType: 14, accountIndex: 0, accountTypeName: "PlatformPayment")
            container.mainContext.insert(account)
            wallet.accounts = [account]
        }
        return wallet
    }

    private func addAddress(to container: ModelContainer, wallet: PersistentWallet, index: UInt32, credits: UInt64) {
        let address = PersistentPlatformAddress(
            address: "test-\(wallet.walletId.first!)-\(index)", addressType: 0,
            addressHash: Data([wallet.walletId.first!, UInt8(index)]),
            accountIndex: 0, addressIndex: index, derivationPath: "test",
            balance: credits, walletId: wallet.walletId)
        address.account = wallet.accounts.first
        container.mainContext.insert(address)
    }

    func testReadsOnlySelectedWalletAndIncludesZeroRows() throws {
        let container = try DashModelContainer.createInMemory()
        let selected = addWallet(to: container, id: walletId)
        let other = addWallet(to: container, id: Data(repeating: 2, count: 32))
        addAddress(to: container, wallet: selected, index: 2, credits: 70)
        addAddress(to: container, wallet: selected, index: 0, credits: 0)
        addAddress(to: container, wallet: selected, index: 1, credits: 30)
        addAddress(to: container, wallet: other, index: 0, credits: 999)
        try container.mainContext.save()
        let snapshot = try XCTUnwrap(PlatformBalanceReader.read(container: container, walletId: walletId, network: .testnet))
        XCTAssertEqual(snapshot.credits, 100)
        XCTAssertEqual(snapshot.activeAddressCount, 2)
        XCTAssertEqual(snapshot.addresses.map(\.addressIndex), [0, 1, 2])
    }

    func testEmptyAccountIsKnownZero() throws {
        let container = try DashModelContainer.createInMemory()
        _ = addWallet(to: container, id: walletId)
        let snapshot = try XCTUnwrap(PlatformBalanceReader.read(container: container, walletId: walletId, network: .testnet))
        XCTAssertEqual(snapshot.credits, 0)
        XCTAssertEqual(snapshot.activeAddressCount, 0)
    }

    func testMissingWalletOrAccountIsUnavailable() throws {
        let container = try DashModelContainer.createInMemory()
        XCTAssertNil(try PlatformBalanceReader.read(container: container, walletId: walletId, network: .testnet))
        _ = addWallet(to: container, id: walletId, hasAccount: false)
        XCTAssertNil(try PlatformBalanceReader.read(container: container, walletId: walletId, network: .testnet))
    }

    func testSameWalletIdWithWrongNetworkIsUnavailable() throws {
        let container = try DashModelContainer.createInMemory()
        let wallet = addWallet(to: container, id: walletId)
        addAddress(to: container, wallet: wallet, index: 0, credits: 99)
        XCTAssertNil(try PlatformBalanceReader.read(container: container, walletId: walletId, network: .mainnet))
    }

    func testSameWalletIdAcrossNetworkContainersKeepsAmountsAndAddressesSeparate() throws {
        // SwiftDashSDKHost uses a separate DashModel.sqlite per network.
        let mainnet = try DashModelContainer.createInMemory()
        let testnet = try DashModelContainer.createInMemory()
        let mainWallet = addWallet(to: mainnet, id: walletId, network: .mainnet)
        let testWallet = addWallet(to: testnet, id: walletId, network: .testnet)
        addAddress(to: mainnet, wallet: mainWallet, index: 1, credits: 100)
        addAddress(to: testnet, wallet: testWallet, index: 2, credits: 900)
        try mainnet.mainContext.save()
        try testnet.mainContext.save()
        let main = try XCTUnwrap(PlatformBalanceReader.read(container: mainnet, walletId: walletId, network: .mainnet))
        let test = try XCTUnwrap(PlatformBalanceReader.read(container: testnet, walletId: walletId, network: .testnet))
        XCTAssertEqual(main.credits, 100)
        XCTAssertEqual(main.addresses.map(\.addressIndex), [1])
        XCTAssertEqual(test.credits, 900)
        XCTAssertEqual(test.addresses.map(\.addressIndex), [2])
        XCTAssertNil(try PlatformBalanceReader.read(container: mainnet, walletId: walletId, network: .testnet))
        XCTAssertNil(try PlatformBalanceReader.read(container: testnet, walletId: walletId, network: .mainnet))
    }

    func testUpdatedPersistedZeroReplacesPreviousAmount() throws {
        let container = try DashModelContainer.createInMemory()
        let wallet = addWallet(to: container, id: walletId)
        addAddress(to: container, wallet: wallet, index: 0, credits: 99)
        let first = try XCTUnwrap(PlatformBalanceReader.read(container: container, walletId: walletId, network: .testnet))
        XCTAssertEqual(first.credits, 99)
        first.addresses[0].balance = 0
        try container.mainContext.save()
        XCTAssertEqual(try PlatformBalanceReader.read(container: container, walletId: walletId, network: .testnet)?.credits, 0)
    }

    func testOverflowFailsInsteadOfPublishingWrappedAmount() throws {
        let container = try DashModelContainer.createInMemory()
        let wallet = addWallet(to: container, id: walletId)
        addAddress(to: container, wallet: wallet, index: 0, credits: UInt64.max)
        addAddress(to: container, wallet: wallet, index: 1, credits: 1)
        XCTAssertThrowsError(try PlatformBalanceReader.read(container: container, walletId: walletId, network: .testnet))
    }
}
