//
//  ShieldedReceiveAddressSourceTests.swift
//  DashWalletTests
//

@testable import dashpay
import XCTest

/// The SDK-backed source maps the SDK's fresh / default address results to
/// `ShieldedReceiveAddress` and encodes for the running network. Addresses
/// here are random bytes, never a real wallet's address.
final class ShieldedReceiveAddressSourceTests: XCTestCase {
    private struct Failure: Error {}

    private let walletId = Data(repeating: 7, count: 32)

    private static func randomRaw() -> Data {
        Data((0..<43).map { _ in UInt8.random(in: 0...255) })
    }

    private func source(
        fresh: @escaping (Data) throws -> Data?,
        defaultAddress: @escaping (Data) throws -> Data? = { _ in XCTFail("default not expected"); return nil },
        isMainnet: @escaping () -> Bool? = { false }
    ) -> SDKShieldedReceiveAddressSource {
        SDKShieldedReceiveAddressSource(
            freshAddress: fresh,
            defaultAddress: defaultAddress,
            isMainnet: isMainnet)
    }

    func testFreshBytesMapToFreshEncodedAddress() async {
        let raw = Self.randomRaw()
        let result = await source(fresh: { _ in raw }).receiveAddress(walletId: walletId)
        let expected = SDKShieldedReceiveAddressSource.encode(raw: raw, mainnet: false)
        XCTAssertEqual(result, expected.map(ShieldedReceiveAddress.fresh))
        XCTAssertNotEqual(result, .unavailable)
    }

    func testUnboundFreshMapsToNotReadyWithoutFallback() async {
        let result = await source(fresh: { _ in nil }).receiveAddress(walletId: walletId)
        XCTAssertEqual(result, .notReady)
    }

    func testFreshThrowFallsBackToDefaultAddress() async {
        let raw = Self.randomRaw()
        let result = await source(
            fresh: { _ in throw Failure() },
            defaultAddress: { _ in raw }).receiveAddress(walletId: walletId)
        let expected = SDKShieldedReceiveAddressSource.encode(raw: raw, mainnet: false)
        XCTAssertEqual(result, expected.map(ShieldedReceiveAddress.fallback))
        XCTAssertNotEqual(result, .unavailable)
    }

    func testFreshThrowAndNoDefaultMapsToUnavailable() async {
        let result = await source(
            fresh: { _ in throw Failure() },
            defaultAddress: { _ in nil }).receiveAddress(walletId: walletId)
        XCTAssertEqual(result, .unavailable)
    }

    func testFreshThrowAndDefaultThrowMapsToUnavailable() async {
        let result = await source(
            fresh: { _ in throw Failure() },
            defaultAddress: { _ in throw Failure() }).receiveAddress(walletId: walletId)
        XCTAssertEqual(result, .unavailable)
    }

    func testUnknownNetworkMapsToNotReady() async {
        let raw = Self.randomRaw()
        let result = await source(fresh: { _ in raw }, isMainnet: { nil }).receiveAddress(walletId: walletId)
        XCTAssertEqual(result, .notReady)
    }

    func testEncodingUsesTheRunningNetworkHrp() async {
        let raw = Self.randomRaw()
        let mainnet = await source(fresh: { _ in raw }, isMainnet: { true }).receiveAddress(walletId: walletId)
        let testnet = await source(fresh: { _ in raw }, isMainnet: { false }).receiveAddress(walletId: walletId)
        guard case .fresh(let main) = mainnet, case .fresh(let test) = testnet else {
            return XCTFail("expected fresh addresses, got \(mainnet) / \(testnet)")
        }
        XCTAssertTrue(main.hasPrefix("dash1"), "mainnet HRP")
        XCTAssertTrue(test.hasPrefix("tdash1"), "testnet HRP")
    }

    func testCallsTheSDKWithTheGivenWalletId() async {
        var seen: Data?
        _ = await source(fresh: { id in seen = id; return nil }).receiveAddress(walletId: walletId)
        XCTAssertEqual(seen, walletId)
    }
}
