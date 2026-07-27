//
//  DWRegistrationPhaseAdapterTests.swift
//  DashWalletTests
//
//  Unit tests for the SDK 5-phase → dashwallet 3-state mapping used
//  by the SwiftDashSDK-backed identity registration flow.
//
//  Pure function — no SwiftDashSDK / wallet / SwiftData mocking
//  needed.
//

import XCTest
@testable import dashwallet

// NOTE: DashWalletTests links against the `dashwallet` target, but the
// types under test (`DWIdentityRegistrationController`,
// `DWRegistrationPhaseAdapter`, `DWIdentityFundingSource`) are
// registered on the `dashpay` target only. The test bundle is
// pre-existing broken — `TodayExtension` `DSDynamicOptions` link
// failure stops the test run before these tests compile. Fixing the
// bundle requires the test target to depend on `dashpay` (or the
// types to also be on `dashwallet`); both are out of scope for the
// identity-migration stage. Adapter is a pure function; the cases
// here are documentation-as-tests until the test bundle is repaired.
final class DWRegistrationPhaseAdapterTests: XCTestCase {

    typealias Phase = DWIdentityRegistrationController.Phase

    // MARK: - .idle / .preparingKeys always map to ProcessingPayment

    func test_idle_anyAssetLockStatus_isProcessingPayment() {
        for status in 0...4 {
            XCTAssertEqual(
                DWRegistrationPhaseAdapter.map(phase: .idle, assetLockStatus: status),
                .processingPayment,
                "idle with assetLockStatus=\(status) should map to processingPayment")
        }
    }

    func test_preparingKeys_anyAssetLockStatus_isProcessingPayment() {
        for status in 0...4 {
            XCTAssertEqual(
                DWRegistrationPhaseAdapter.map(phase: .preparingKeys, assetLockStatus: status),
                .processingPayment,
                "preparingKeys with assetLockStatus=\(status) should map to processingPayment")
        }
    }

    // MARK: - .inFlight depends on assetLockStatus

    func test_inFlight_assetLockBuilt_isProcessingPayment() {
        // statusRaw=0 (Built) — asset-lock tx built but not broadcast
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(phase: .inFlight, assetLockStatus: 0),
            .processingPayment)
    }

    func test_inFlight_assetLockBroadcast_isProcessingPayment() {
        // statusRaw=1 (Broadcast) — broadcast, waiting for IS/CL
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(phase: .inFlight, assetLockStatus: 1),
            .processingPayment)
    }

    func test_inFlight_instantSendLocked_isCreatingID() {
        // statusRaw=2 (InstantSendLocked) — IS proof received,
        // IdentityCreate ST about to / in flight
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(phase: .inFlight, assetLockStatus: 2),
            .creatingID)
    }

    func test_inFlight_chainLocked_isCreatingID() {
        // statusRaw=3 (ChainLocked) — CL fallback received
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(phase: .inFlight, assetLockStatus: 3),
            .creatingID)
    }

    func test_inFlight_consumed_isRegistrationUsername() {
        // statusRaw=4 (Consumed) — asset lock used by IdentityCreate,
        // DPNS register ST in flight
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(phase: .inFlight, assetLockStatus: 4),
            .registrationUsername)
    }

    // MARK: - .completed always maps to .done

    func test_completed_anyAssetLockStatus_isDone() {
        let dummyId = Data(count: 32)
        for status in 0...4 {
            XCTAssertEqual(
                DWRegistrationPhaseAdapter.map(
                    phase: .completed(identityId: dummyId),
                    assetLockStatus: status),
                .done,
                "completed with assetLockStatus=\(status) should map to done")
        }
    }

    // MARK: - .failed honors failedAtPhase when provided

    func test_failed_withFailedAtPhase_usesIt() {
        // When the coordinator records which sub-step failed, the
        // adapter must surface that exact state — error copy is
        // tied to the phase.
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(
                phase: .failed("auth cancelled"),
                assetLockStatus: 0,
                failedAtPhase: .processingPayment),
            .processingPayment)

        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(
                phase: .failed("IdentityCreate failed"),
                assetLockStatus: 3,
                failedAtPhase: .creatingID),
            .creatingID)

        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(
                phase: .failed("DPNS register failed"),
                assetLockStatus: 4,
                failedAtPhase: .registrationUsername),
            .registrationUsername)
    }

    func test_failed_withoutFailedAtPhase_defaultsToCreatingID() {
        // When the coordinator didn't record a sub-step (e.g. an
        // unexpected pre-submit failure), default to CreatingID so
        // the UI shows a generic "couldn't create identity" copy.
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(
                phase: .failed("some unexpected error"),
                assetLockStatus: 0,
                failedAtPhase: nil),
            .creatingID)
    }

    // MARK: - Boundary / sanity

    func test_inFlight_unknownAssetLockStatus_treatedAsHighest() {
        // Defensive: if Rust ships a new statusRaw value (e.g. 5+),
        // treat as past-consumed (registrationUsername) — better
        // than under-reporting progress.
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(phase: .inFlight, assetLockStatus: 5),
            .registrationUsername)
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(phase: .inFlight, assetLockStatus: 99),
            .registrationUsername)
    }

    // MARK: - Platform Payment funding source

    // PR 5: when the coordinator routes through
    // `registerIdentityFromAddresses` there is no Core-chain asset-
    // lock — the adapter must collapse the in-flight phase straight
    // onto `.creatingID` (skipping the `.processingPayment` window
    // that would normally cover the IS/CL wait).

    func test_platformPayment_idle_isProcessingPayment() {
        // Pre-FFI is identical for both funding sources — keys are
        // still being derived, no on-chain activity yet.
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(
                phase: .idle,
                assetLockStatus: 0,
                fundingSource: .platformPayment),
            .processingPayment)
    }

    func test_platformPayment_preparingKeys_isProcessingPayment() {
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(
                phase: .preparingKeys,
                assetLockStatus: 0,
                fundingSource: .platformPayment),
            .processingPayment)
    }

    func test_platformPayment_inFlight_anyAssetLockStatus_isCreatingID() {
        // Platform Payment path ignores assetLockStatus entirely —
        // there is no PersistentAssetLock row to poll, so whatever
        // stale value `assetLockStatus` carries (most likely 0 from
        // the prior `.idle` state) must not pull the UI back to
        // `.processingPayment`.
        for status in 0...4 {
            XCTAssertEqual(
                DWRegistrationPhaseAdapter.map(
                    phase: .inFlight,
                    assetLockStatus: status,
                    fundingSource: .platformPayment),
                .creatingID,
                "Platform Payment .inFlight with assetLockStatus=\(status) should map to creatingID")
        }
    }

    func test_platformPayment_completed_isDone() {
        let dummyId = Data(count: 32)
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(
                phase: .completed(identityId: dummyId),
                assetLockStatus: 0,
                fundingSource: .platformPayment),
            .done)
    }

    func test_platformPayment_failed_usesFailedAtPhase() {
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(
                phase: .failed("registerIdentityFromAddresses failed"),
                assetLockStatus: 0,
                fundingSource: .platformPayment,
                failedAtPhase: .creatingID),
            .creatingID)
    }

    // MARK: - Shielded (Type-20) funding path

    // Like Platform Payment, the shielded path has no Core-chain
    // asset-lock — the whole spend (Halo 2 proof + submit) is one
    // opaque FFI call, so `.inFlight` must map straight to
    // `.creatingID` regardless of any stale `assetLockStatus`.

    func test_shielded_inFlight_anyAssetLockStatus_isCreatingID() {
        for status in 0...4 {
            XCTAssertEqual(
                DWRegistrationPhaseAdapter.map(
                    phase: .inFlight,
                    assetLockStatus: status,
                    fundingSource: .shielded),
                .creatingID,
                "Shielded .inFlight with assetLockStatus=\(status) should map to creatingID")
        }
    }

    func test_shielded_completed_isDone() {
        let dummyId = Data(count: 32)
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(
                phase: .completed(identityId: dummyId),
                assetLockStatus: 0,
                fundingSource: .shielded),
            .done)
    }

    func test_shielded_failed_usesFailedAtPhase() {
        XCTAssertEqual(
            DWRegistrationPhaseAdapter.map(
                phase: .failed("shieldedIdentityCreateFromPool failed"),
                assetLockStatus: 0,
                fundingSource: .shielded,
                failedAtPhase: .creatingID),
            .creatingID)
    }

    // MARK: - Registration interruption recovery

    func test_registrationRecoveryOutPoint_decodesDisplayTxidToWireOrder() {
        let displayTxid = "e8b43025641eea4fd21190f01bd870ef90f1a8b199d8fc3376c5b62c0b1a179d"
        let parsed = DWIdentityRegistrationCoordinator.parseOutPointHex(
            "\(displayTxid):1")

        XCTAssertEqual(
            parsed?.txidWire.map { String(format: "%02x", $0) }.joined(),
            "9d171a0b2cb6c57633fcd899b1a8f190ef70d81bf09011d24fea1e642530b4e8")
        XCTAssertEqual(parsed?.vout, 1)
    }

    func test_registrationRecoveryOutPoint_rejectsMalformedValues() {
        XCTAssertNil(DWIdentityRegistrationCoordinator.parseOutPointHex("missing-vout"))
        XCTAssertNil(DWIdentityRegistrationCoordinator.parseOutPointHex("00:1"))
        XCTAssertNil(DWIdentityRegistrationCoordinator.parseOutPointHex(
            "\(String(repeating: "z", count: 64)):1"))
        XCTAssertNil(DWIdentityRegistrationCoordinator.parseOutPointHex(
            "\(String(repeating: "0", count: 64)):not-a-number"))
    }

    func test_registrationRecoveryIdentityIdentifier_matchesDIP27Vector() {
        let parsed = DWIdentityRegistrationCoordinator.parseOutPointHex(
            "e8b43025641eea4fd21190f01bd870ef90f1a8b199d8fc3376c5b62c0b1a179d:1")
        let identifier = parsed.flatMap {
            DWIdentityRegistrationCoordinator.identityIdentifier(
                txidWire: $0.txidWire,
                vout: $0.vout)
        }

        XCTAssertEqual(
            identifier?.map { String(format: "%02x", $0) }.joined(),
            "993e6ac24139e41ea9a4541bca4e1642bd0832321754c2b4ff60dc4e8b340633")
    }
}

final class PlatformPaymentIdentityFundingPolicyTests: XCTestCase {

    private let standardFundingDuffs: UInt64 = 3_000_000

    private func candidate(
        type: UInt8 = 0,
        hashByte: UInt8,
        balance: UInt64
    ) -> PlatformPaymentIdentityFundingPolicy.Candidate {
        PlatformPaymentIdentityFundingPolicy.Candidate(
            addressType: type,
            hash: Data(repeating: hashByte, count: 20),
            balance: balance)
    }

    func test_standardRegistrationRequiresFundingPlusFeeHeadroom() {
        XCTAssertEqual(
            PlatformPaymentIdentityFundingPolicy.requiredAvailableCredits(
                fundingDuffs: standardFundingDuffs),
            4_000_000_000)
    }

    func test_exactFundingWithoutFeeHeadroomIsRejectedBeforeSDKCall() {
        XCTAssertThrowsError(
            try PlatformPaymentIdentityFundingPolicy.makeInputs(
                candidates: [
                    candidate(hashByte: 1, balance: 3_000_000_000)
                ],
                targetCredits: 3_000_000_000)
        ) { error in
            XCTAssertEqual(
                error as? PlatformPaymentIdentityFundingPolicy.PlanningError,
                .insufficient(
                    required: 4_000_000_000,
                    available: 3_000_000_000))
        }
    }

    func test_fragmentedAggregateBalanceDoesNotProduceEligibilityFalsePositive() {
        let candidates = [
            candidate(hashByte: 1, balance: 500_000_000),
            candidate(hashByte: 2, balance: 3_500_000_000)
        ]

        XCTAssertFalse(
            PlatformPaymentIdentityFundingPolicy.canFund(
                candidates: candidates,
                fundingDuffs: standardFundingDuffs))
    }

    func test_candidateAwareEligibilityMatchesSuccessfulMultiInputPlan() {
        let candidates = [
            candidate(hashByte: 1, balance: 1_500_000_000),
            candidate(hashByte: 2, balance: 2_500_000_000)
        ]

        XCTAssertTrue(
            PlatformPaymentIdentityFundingPolicy.canFund(
                candidates: candidates,
                fundingDuffs: standardFundingDuffs))
    }

    func test_singleInputLeavesFeeHeadroomUnclaimed() throws {
        let inputs = try PlatformPaymentIdentityFundingPolicy.makeInputs(
            candidates: [
                candidate(hashByte: 1, balance: 4_000_000_000)
            ],
            targetCredits: 3_000_000_000)

        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].hash, Data(repeating: 1, count: 20))
        XCTAssertEqual(inputs[0].credits, 3_000_000_000)
    }

    func test_leadingAddressWithoutHeadroomIsNotSelectedAsInputZero() throws {
        let inputs = try PlatformPaymentIdentityFundingPolicy.makeInputs(
            candidates: [
                candidate(hashByte: 1, balance: 500_000_000),
                candidate(hashByte: 2, balance: 4_000_000_000)
            ],
            targetCredits: 3_000_000_000)

        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].hash, Data(repeating: 2, count: 20))
        XCTAssertEqual(inputs[0].credits, 3_000_000_000)
    }

    func test_multipleInputsReserveHeadroomOnlyOnBTreeMapInputZero() throws {
        let inputs = try PlatformPaymentIdentityFundingPolicy.makeInputs(
            candidates: [
                candidate(hashByte: 2, balance: 2_500_000_000),
                candidate(hashByte: 1, balance: 1_500_000_000)
            ],
            targetCredits: 3_000_000_000)

        XCTAssertEqual(inputs.count, 2)
        XCTAssertEqual(inputs[0].hash, Data(repeating: 1, count: 20))
        XCTAssertEqual(inputs[0].credits, 500_000_000)
        XCTAssertEqual(inputs[1].hash, Data(repeating: 2, count: 20))
        XCTAssertEqual(inputs[1].credits, 2_500_000_000)
    }

    func test_sdkInsufficientFundsMessageIsRecognizedForFriendlyFallback() {
        let error = NSError(
            domain: "SwiftDashSDK",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Protocol error: Insufficient combined address balances: "
                    + "total available is less than required 41500000"
            ])

        XCTAssertTrue(
            DWIdentityRegistrationCoordinator
                .isPlatformAddressInsufficientFunds(error))
    }

    func test_unrelatedSDKErrorIsNotMisclassifiedAsFundingShortfall() {
        let error = NSError(
            domain: "SwiftDashSDK",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: "Address nonce mismatch"
            ])

        XCTAssertFalse(
            DWIdentityRegistrationCoordinator
                .isPlatformAddressInsufficientFunds(error))
    }
}
