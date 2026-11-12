//
//  ShieldedFreshAddressTimingTests.swift
//  DashWalletTests
//

@testable import dashpay
import SwiftDashSDK
import XCTest

#if targetEnvironment(simulator)
/// NFR (spec §6, public-api G1.6): a fresh shielded address — SDK derivation
/// plus Bech32m encoding — takes ≤ 500 ms at p95 over 100 calls. Runs the
/// real SDK offline: an in-memory store, a wallet from a freshly generated
/// throwaway phrase, and a bound shielded account. No address is printed.
@MainActor
final class ShieldedFreshAddressTimingTests: XCTestCase {
    func testFreshAddressDerivationP95IsWithin500ms() async throws {
        let manager = PlatformWalletManager()
        try manager.configure(
            sdk: SDK(network: .testnet),
            modelContainer: ShieldedWithdrawalHistoryFixture.makeContainer())
        let mnemonic = try Mnemonic.generate(wordCount: 12)
        let walletId = try await manager.createWallet(mnemonic: mnemonic, network: .testnet).walletId

        let storage = WalletStorage()
        try storage.storeMnemonic(mnemonic, for: walletId)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fresh-address-timing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? storage.deleteMnemonic(for: walletId)
            _ = await manager.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }

        try manager.configureShielded(dbPath: directory.appendingPathComponent("shielded.sqlite").path)
        try manager.bindShielded(walletId: walletId, resolver: MnemonicResolver(storage: storage))

        let source = SDKShieldedReceiveAddressSource(
            freshAddress: { try manager.shieldedFreshAddress(walletId: $0) },
            defaultAddress: { _ in nil },
            isMainnet: { false })

        var durations: [TimeInterval] = []
        var addresses = Set<String>()
        for _ in 0..<100 {
            let start = Date()
            let result = await source.receiveAddress(walletId: walletId)
            durations.append(Date().timeIntervalSince(start))
            guard case .fresh(let address) = result else {
                return XCTFail("every call yields a fresh address")
            }
            addresses.insert(address)
        }

        XCTAssertEqual(addresses.count, 100, "every fresh address is distinct")
        let p95 = durations.sorted()[94]
        XCTAssertLessThanOrEqual(p95, 0.5, String(format: "p95 = %.1f ms", p95 * 1000))
    }
}
#endif
