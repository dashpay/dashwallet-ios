//
//  CoreToPlatformSendRouteTests.swift
//  DashWalletTests
//
//  Coverage for the Core → Platform external send route: the source/destination
//  routing table, the fee-on-top amount policy, P2SH recipient rejection, and
//  the durable-recipient round trip that keeps a cold resume pointed at the
//  third party the user actually confirmed.
//

import XCTest
@testable import dashpay

@MainActor
final class CoreToPlatformSendRouteTests: XCTestCase {

    // MARK: - Routing table

    /// Every (source, destination) pair the Send screen admits, including the
    /// newly-legal `.core → .platform`. Written as a table so a route added
    /// later has to declare its source set here too.
    func testValidSourcesAndRouteAgreeForEveryDestination() {
        let expected: [(SendViewModel.DestinationKind, [ChainNetwork], [SendViewModel.Route])] = [
            (.core, [.core, .platform, .shielded],
             [.coreToCore, .platformToCore, .shieldedToCore]),
            (.platform, [.platform, .shielded, .core],
             [.platformToPlatform, .shieldedToPlatform, .coreToPlatform]),
            (.shielded(raw43: Data(repeating: 7, count: 43)), [.shielded, .core, .platform],
             [.shieldedToShielded, .coreToShielded, .platformToShielded]),
        ]

        for (destination, sources, routes) in expected {
            XCTAssertEqual(
                SendViewModel.validSources(for: destination), sources,
                "validSources for \(destination)")

            for (source, route) in zip(sources, routes) {
                XCTAssertEqual(
                    SendViewModel.route(source: source, destination: destination), route,
                    "route for \(source) → \(destination)")
            }
        }
    }

    /// No destination means no sources and no route — the screen's initial
    /// state must not resolve to a spendable route.
    func testNilDestinationHasNoSourcesAndNoRoute() {
        XCTAssertEqual(SendViewModel.validSources(for: nil), [])
        for source in [ChainNetwork.core, .platform, .shielded] {
            XCTAssertNil(SendViewModel.route(source: source, destination: nil))
        }
    }

    /// The regression this route fixes: a Platform address pasted while the
    /// Transparent balance row is pinned used to dead-end as a mismatch,
    /// because `.core` was not a valid source for a `.platform` destination.
    func testCoreSourceCanPayAPlatformDestination() {
        XCTAssertTrue(SendViewModel.validSources(for: .platform).contains(.core))
        XCTAssertEqual(
            SendViewModel.route(source: .core, destination: .platform),
            .coreToPlatform)
    }

    // MARK: - Amount policy

    /// The headroom is the protocol floor for a two-output address funding:
    /// the asset-lock base processing cost, both outputs' minimum fee, and the
    /// change output's own minimum amount.
    func testExternalHeadroomMatchesTheProtocolFloor() {
        let expectedCredits =
            AssetLockFundingCostPolicy.baseProcessingCostCredits            // 50_000_000
                + AssetLockFundingCostPolicy.addressFundsTransferOutputCostCredits * 2 // 12_000_000
                + AssetLockFundingCostPolicy.minOutputAmountCredits          //    500_000

        XCTAssertEqual(CoreToPlatformAmountPolicy.externalHeadroomCredits, expectedCredits)
        XCTAssertEqual(CoreToPlatformAmountPolicy.externalHeadroomCredits, 62_500_000)
        XCTAssertEqual(CoreToPlatformAmountPolicy.externalHeadroomDuffs, 62_500)
    }

    /// The base processing cost is the ADDRESS-funding constant, so the
    /// shielded policy must read the very same number rather than its own copy.
    func testShieldedPolicyReadsTheSharedBaseProcessingCost() {
        XCTAssertEqual(
            CoreToShieldedAmountPolicy.assetLockBaseCostCredits,
            AssetLockFundingCostPolicy.baseProcessingCostCredits)
    }

    /// Fee-on-top: the lock is amount + headroom, so the payee's explicit
    /// output can carry exactly the typed amount.
    func testExternalLockValueIsAmountPlusHeadroom() {
        let amountDuffs: UInt64 = 1_000_000
        XCTAssertEqual(
            CoreToPlatformAmountPolicy.externalLockValueDuffs(forAmountDuffs: amountDuffs),
            amountDuffs + CoreToPlatformAmountPolicy.externalHeadroomDuffs)
    }

    func testExternalLockValueFailsClosedOnOverflow() {
        XCTAssertNil(CoreToPlatformAmountPolicy.externalLockValueDuffs(forAmountDuffs: UInt64.max))
    }

    /// The payee's output must clear the same `min_output_amount` every other
    /// transition output does.
    func testMinimumAmountMatchesTheMinimumOutputAmount() {
        XCTAssertEqual(CoreToPlatformAmountPolicy.minimumAmountDuffs, 500)
        XCTAssertEqual(
            CoreToPlatformAmountPolicy.payeeCredits(forAmountDuffs: 500),
            AssetLockFundingCostPolicy.minOutputAmountCredits)
    }

    func testPayeeCreditsFailsClosedOnOverflow() {
        XCTAssertNil(CoreToPlatformAmountPolicy.payeeCredits(forAmountDuffs: UInt64.max))
    }

    /// Rounding is UP, so a duff-denominated lock never under-covers a
    /// credit-denominated requirement.
    func testCreditsToDuffsRoundsUp() {
        XCTAssertEqual(AssetLockFundingCostPolicy.duffsRoundingUp(credits: 1000), 1)
        XCTAssertEqual(AssetLockFundingCostPolicy.duffsRoundingUp(credits: 1001), 2)
        XCTAssertEqual(AssetLockFundingCostPolicy.duffsRoundingUp(credits: 0), 0)
    }

    // MARK: - P2SH rejection

    /// `parsePlatformRecipient` decodes both DIP-0018 wire types, so the P2SH
    /// discriminant has to reach the caller intact — that is what lets the Send
    /// screen reject it at input time instead of at confirm time.
    func testParsePlatformRecipientSurfacesTheP2SHDiscriminant() throws {
        let hash = Data((0..<20).map { UInt8($0) })

        let p2pkh = try XCTUnwrap(encodePlatformAddress(wireType: 0xb0, hash: hash))
        let decodedP2PKH = try XCTUnwrap(
            PlatformAddressSyncCoordinator.parsePlatformRecipient(bech32m: p2pkh))
        XCTAssertEqual(decodedP2PKH.ffiAddressType, 0)
        XCTAssertEqual(decodedP2PKH.hash, hash)

        let p2sh = try XCTUnwrap(encodePlatformAddress(wireType: 0x80, hash: hash))
        let decodedP2SH = try XCTUnwrap(
            PlatformAddressSyncCoordinator.parsePlatformRecipient(bech32m: p2sh))
        XCTAssertEqual(decodedP2SH.ffiAddressType, 1, "P2SH must decode as type 1, not be silently accepted as P2PKH")
    }

    /// A P2SH destination is named on the ADDRESS step and blocks Continue,
    /// rather than being confirmed and then failing in execution.
    func testP2SHPlatformDestinationIsRejectedBeforeTheAmountStep() throws {
        let hash = Data(repeating: 0xAB, count: 20)
        let model = SendViewModel()

        model.addressText = try XCTUnwrap(encodePlatformAddress(wireType: 0x80, hash: hash))
        try XCTSkipIf(model.destination != .platform, "P2SH address did not classify on this network")

        XCTAssertNotNil(model.unsupportedDestinationMessage)
        XCTAssertFalse(model.canAdvanceToAmount)
    }

    func testP2PKHPlatformDestinationAdvances() throws {
        let hash = Data(repeating: 0xCD, count: 20)
        let model = SendViewModel()

        model.addressText = try XCTUnwrap(encodePlatformAddress(wireType: 0xb0, hash: hash))
        try XCTSkipIf(model.destination != .platform, "P2PKH address did not classify on this network")

        XCTAssertNil(model.unsupportedDestinationMessage)
        XCTAssertTrue(model.canAdvanceToAmount)
    }

    // MARK: - Durable recipient round trip

    /// Write then read back: a resume must recover the SAME third party, not
    /// the sender's own address.
    func testRecipientRoundTripsThroughTheStore() {
        let store = PlatformFundingRecipientStore.shared
        store.resetForWipe()
        defer { store.resetForWipe() }

        let outPointHex = String(repeating: "ab", count: 32) + ":0"
        let recipient = PlatformFundingRecipient(
            addressType: 0,
            hash: Data(repeating: 0x11, count: 20),
            isExternal: true,
            credits: 2_000_000_000)

        store.stamp(outPointHex: outPointHex, recipient: recipient)

        XCTAssertEqual(store.recipient(forOutPointHex: outPointHex), recipient)
    }

    /// The pre-submit intent covers the window where the lock is broadcast but
    /// its outpoint has not been observed yet — a kill there must not lose the
    /// destination.
    func testPendingIntentIsServedForAnUnstampedOutPoint() {
        let store = PlatformFundingRecipientStore.shared
        store.resetForWipe()
        defer { store.resetForWipe() }

        let recipient = PlatformFundingRecipient(
            addressType: 0,
            hash: Data(repeating: 0x22, count: 20),
            isExternal: true,
            credits: 5_000_000)
        store.recordIntent(recipient)

        let unseenOutPoint = String(repeating: "cd", count: 32) + ":0"
        XCTAssertEqual(store.recipient(forOutPointHex: unseenOutPoint), recipient)

        store.clearIntent()
        XCTAssertNil(store.recipient(forOutPointHex: unseenOutPoint))
    }

    /// The legacy fallback: a lock with NO recorded recipient must read back as
    /// `nil` so the resume keeps own-next-address behavior. Returning anything
    /// else here is exactly the misdirection the record exists to prevent.
    func testMissingRecipientReadsBackAsNil() {
        let store = PlatformFundingRecipientStore.shared
        store.resetForWipe()
        defer { store.resetForWipe() }

        let outPointHex = String(repeating: "ef", count: 32) + ":0"
        XCTAssertNil(store.recipient(forOutPointHex: outPointHex))
    }

    /// First stamp wins: a later resume can never rewrite the destination the
    /// user originally confirmed.
    func testStampIsFirstWriteWins() {
        let store = PlatformFundingRecipientStore.shared
        store.resetForWipe()
        defer { store.resetForWipe() }

        let outPointHex = String(repeating: "12", count: 32) + ":0"
        let original = PlatformFundingRecipient(
            addressType: 0, hash: Data(repeating: 0x33, count: 20), isExternal: true, credits: 100)
        let usurper = PlatformFundingRecipient(
            addressType: 0, hash: Data(repeating: 0x44, count: 20), isExternal: false, credits: nil)

        store.stamp(outPointHex: outPointHex, recipient: original)
        store.stamp(outPointHex: outPointHex, recipient: usurper)

        XCTAssertEqual(store.recipient(forOutPointHex: outPointHex), original)
    }

    /// The outpoint key must be the SDK's display-order form, or nothing
    /// written under it is ever found again.
    func testOutPointHexIsDisplayOrder() {
        var wire = Data(repeating: 0x00, count: 32)
        wire[0] = 0xAA
        wire[31] = 0xBB

        let hex = PlatformFundingRecipientStore.outPointHex(txidWire: wire, vout: 3)
        XCTAssertEqual(hex, "bb" + String(repeating: "00", count: 30) + "aa:3")
        XCTAssertNil(PlatformFundingRecipientStore.outPointHex(txidWire: Data([0x01]), vout: 0))
    }

    // MARK: - Helpers

    /// DIP-0018 display form for a Platform address on the CURRENT network:
    /// bech32m over `[wireType] + 20-byte hash`.
    private func encodePlatformAddress(wireType: UInt8, hash: Data) -> String? {
        let hrp = Bech32m.platformHrp(mainnet: !WalletEnvironment.isTestnet)
        return Bech32m.encode(hrp: hrp, data: Data([wireType]) + hash)
    }
}
