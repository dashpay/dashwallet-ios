//
//  SwiftDashSDKCoreLifecycleTests.swift
//  DashWalletTests
//
//  Regression coverage for SDK lifecycle and freshness policies.
//

import XCTest
@testable import dashwallet

private enum CoreLifecycleTestError: Error {
    case start
}

@MainActor
final class SwiftDashSDKCoreLifecycleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testRestartRunsExactlyStopThenStartAndResetsBusyState() async throws {
        var events: [String] = []
        var restartingStates: [Bool] = []

        try await CoreSPVRestartOperation.run(
            setRestarting: { restartingStates.append($0) },
            stop: { events.append("stop") },
            start: { events.append("start") })

        XCTAssertEqual(events, ["stop", "start"])
        XCTAssertEqual(restartingStates, [true, false])
    }

    func testRestartPropagatesStartFailureAndAlwaysResetsBusyState() async {
        var events: [String] = []
        var restartingStates: [Bool] = []

        do {
            try await CoreSPVRestartOperation.run(
                setRestarting: { restartingStates.append($0) },
                stop: { events.append("stop") },
                start: {
                    events.append("start")
                    throw CoreLifecycleTestError.start
                })
            XCTFail("Expected restart failure")
        } catch CoreLifecycleTestError.start {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(events, ["stop", "start"])
        XCTAssertEqual(restartingStates, [true, false])
    }

    func testQueuedRestartsNeverOverlap() async {
        let queue = SerialAsyncLifecycleQueue()
        var events: [String] = []
        var operationsInFlight = 0
        var maximumOperationsInFlight = 0

        func operation(_ name: String) async {
            operationsInFlight += 1
            maximumOperationsInFlight = max(maximumOperationsInFlight, operationsInFlight)
            events.append("\(name)-stop")
            await Task.yield()
            events.append("\(name)-start")
            operationsInFlight -= 1
        }

        queue.enqueue { await operation("first") }
        let second = queue.enqueue { await operation("second") }
        await second.value

        XCTAssertEqual(maximumOperationsInFlight, 1)
        XCTAssertEqual(events, [
            "first-stop", "first-start",
            "second-stop", "second-start",
        ])
    }

    func testProcessCacheReusesValuesPerNetworkAndSeparatesNetworks() {
        final class Token {}

        let cache = ProcessNetworkValueCache<Token>()
        let mainnetFirst = cache.value(for: "mainnet") { Token() }
        let mainnetSecond = cache.value(for: "mainnet") { Token() }
        let testnet = cache.value(for: "testnet") { Token() }

        XCTAssertFalse(mainnetFirst.reused)
        XCTAssertTrue(mainnetSecond.reused)
        XCTAssertFalse(testnet.reused)
        XCTAssertTrue(mainnetFirst.value === mainnetSecond.value)
        XCTAssertFalse(mainnetFirst.value === testnet.value)
    }

    func testSameSeedIdentityRecoveryDiscoversRefreshesAndAdoptsInOneRun() async throws {
        let identityId = Data(repeating: 0x16, count: 32)
        var storedIdentityIds: [Data] = []
        var events: [String] = []

        let outcome = try await SameSeedIdentityRecoveryPipeline.run(
            localIdentityIds: { storedIdentityIds },
            discover: {
                events.append("discover")
                storedIdentityIds = [identityId]
                return [identityId]
            },
            refreshNames: { identityIds in
                XCTAssertEqual(identityIds, [identityId])
                events.append("refresh")
            },
            adopt: {
                events.append("adopt")
                return true
            })

        XCTAssertEqual(events, ["discover", "refresh", "adopt"])
        XCTAssertEqual(
            outcome,
            .init(discoveredCount: 1, identityCount: 1, adopted: true))
    }

    func testSameSeedIdentityRecoveryUsesPersistedIdentityWithoutRescanning() async throws {
        let identityId = Data(repeating: 0x17, count: 32)
        var discoveryCalls = 0
        var refreshedIdentityIds: [Data] = []

        let outcome = try await SameSeedIdentityRecoveryPipeline.run(
            localIdentityIds: { [identityId] },
            discover: {
                discoveryCalls += 1
                return []
            },
            refreshNames: { refreshedIdentityIds = $0 },
            adopt: { true })

        XCTAssertEqual(discoveryCalls, 0)
        XCTAssertEqual(refreshedIdentityIds, [identityId])
        XCTAssertEqual(
            outcome,
            .init(discoveredCount: 0, identityCount: 1, adopted: true))
    }

    func testWatchdogRefreshesOnlyAfterFullScanBecomesStale() {
        XCTAssertFalse(ShieldedSyncFreshnessPolicy.shouldRefreshForWatchdog(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-89),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: false,
            refreshInFlight: false))

        XCTAssertTrue(ShieldedSyncFreshnessPolicy.shouldRefreshForWatchdog(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-90),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: false,
            refreshInFlight: false))
    }

    func testWatchdogUsesMonitoringStartUntilFirstFullScan() {
        XCTAssertFalse(ShieldedSyncFreshnessPolicy.shouldRefreshForWatchdog(
            now: now,
            lastFullScanAt: nil,
            monitoringStartedAt: now.addingTimeInterval(-89),
            isSyncing: false,
            refreshInFlight: false))

        XCTAssertTrue(ShieldedSyncFreshnessPolicy.shouldRefreshForWatchdog(
            now: now,
            lastFullScanAt: nil,
            monitoringStartedAt: now.addingTimeInterval(-90),
            isSyncing: false,
            refreshInFlight: false))
    }

    func testForegroundRefreshSkipsRecentFullScan() {
        XCTAssertFalse(ShieldedSyncFreshnessPolicy.shouldRefreshOnForeground(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-29),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: false,
            refreshInFlight: false))

        XCTAssertTrue(ShieldedSyncFreshnessPolicy.shouldRefreshOnForeground(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-30),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: false,
            refreshInFlight: false))
    }

    func testRefreshesAreDeduplicatedAgainstActiveWork() {
        XCTAssertFalse(ShieldedSyncFreshnessPolicy.shouldRefreshForWatchdog(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-300),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: true,
            refreshInFlight: false))

        XCTAssertFalse(ShieldedSyncFreshnessPolicy.shouldRefreshOnForeground(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-300),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: false,
            refreshInFlight: true))
    }

    func testStoppedPlatformSyncRequiresRuntimeRearm() {
        XCTAssertTrue(
            PlatformSyncRearmPolicy.requiresRuntimeRearm(
                isRunning: false,
                hasWalletManager: false))
        XCTAssertTrue(
            PlatformSyncRearmPolicy.requiresRuntimeRearm(
                isRunning: true,
                hasWalletManager: false))
        XCTAssertFalse(
            PlatformSyncRearmPolicy.requiresRuntimeRearm(
                isRunning: true,
                hasWalletManager: true))
    }

    func testWalletWithoutPlatformPaymentAccountUsesNeutralState() {
        let availability = PlatformAccountAvailabilityPolicy.resolve(
            hasWalletRecord: true,
            hasPlatformPaymentAccount: false)

        XCTAssertEqual(availability, .unavailable)
        XCTAssertNil(
            PlatformSyncStatusPresentationPolicy.visibleError(
                availability: availability,
                lastError: "Platform wallet not configured"))
    }

    func testMissingWalletRecordRemainsUnknownInsteadOfClaimingNoPlatformWallet() {
        XCTAssertEqual(
            PlatformAccountAvailabilityPolicy.resolve(
                hasWalletRecord: false,
                hasPlatformPaymentAccount: false),
            .unknown)
    }

    func testPlatformActivityConvertsCreditsToDuffsBeforeMatchingUnshield() {
        let creditedAmount: UInt64 = 10_000_000_000

        XCTAssertEqual(
            PlatformAddressActivityUnitPolicy.duffs(fromCredits: creditedAmount),
            10_000_000)
        XCTAssertTrue(PlatformAddressActivityUnitPolicy.unshieldCoversDelta(
            creditedAmountCredits: creditedAmount,
            observedDeltaDuffs: 10_000_000))
        // Non-positive deltas are never own-operation residue.
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.unshieldCoversDelta(
            creditedAmountCredits: creditedAmount,
            observedDeltaDuffs: 0))
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.unshieldCoversDelta(
            creditedAmountCredits: creditedAmount,
            observedDeltaDuffs: -1))
        // A credits-vs-duffs unit mixup must never pass as a match.
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.unshieldCoversDelta(
            creditedAmountCredits: creditedAmount,
            observedDeltaDuffs: Int64(creditedAmount)))
    }

    func testOwnUnshieldSuppressionAcceptsOnlyLiveUnshieldWithPlatformCounterparty() {
        XCTAssertTrue(PlatformAddressActivityUnitPolicy.isOwnUnshieldCandidate(
            kindTag: ShieldedActivityItem.Kind.unshield.rawValue,
            counterpartyLength: 21))
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.isOwnUnshieldCandidate(
            kindTag: ShieldedActivityItem.Kind.shieldedSpend.rawValue,
            counterpartyLength: 21))
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.isOwnUnshieldCandidate(
            kindTag: ShieldedActivityItem.Kind.shieldedSpend.rawValue,
            counterpartyLength: 43))
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.isOwnUnshieldCandidate(
            kindTag: ShieldedActivityItem.Kind.received.rawValue,
            counterpartyLength: 21))
    }

    func testOwnUnshieldSuppressionDoesNotMatchAnExternalReceive() {
        // Different address: never suppressed, whatever the amount.
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.unshieldResidueMatches(
            destinationAddress: "tdash1own",
            observedAddress: "tdash1external",
            creditedAmountCredits: 10_000_000_000,
            observedDeltaDuffs: 10_000_000))
        // Same address, delta LARGER than the credited principal: more
        // money arrived than the own unshield explains — not residue.
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.unshieldResidueMatches(
            destinationAddress: "tdash1own",
            observedAddress: "tdash1own",
            creditedAmountCredits: 10_000_000_000,
            observedDeltaDuffs: 10_000_001))
    }

    func testOwnUnshieldSuppressionCoversTopUpResidue() {
        // Shielded identity top-up: unshield lands 0.05, the top-up claims
        // most of it before the next sync, so the observed delta is the
        // small remainder — still the own operation's residue.
        XCTAssertTrue(PlatformAddressActivityUnitPolicy.unshieldResidueMatches(
            destinationAddress: "tdash1own",
            observedAddress: "tdash1own",
            creditedAmountCredits: 5_000_000_000,
            observedDeltaDuffs: 198_000))
        // The full principal (no follow-on spend) still matches.
        XCTAssertTrue(PlatformAddressActivityUnitPolicy.unshieldResidueMatches(
            destinationAddress: "tdash1own",
            observedAddress: "tdash1own",
            creditedAmountCredits: 5_000_000_000,
            observedDeltaDuffs: 5_000_000))
    }

    func testPlatformActivityUnitMigrationKeepsPrereleaseVersion() {
        XCTAssertEqual(NormalizePlatformAddressActivityUnits().version, 20260727140000)
    }

    func testCoreToShieldedMinimumIsFirstWholeDuffStrictlyAbovePoolFee() {
        XCTAssertEqual(
            CoreToShieldedAmountPolicy.minimumAmountDuffs(
                poolFeeCredits: 212_851_200),
            212_852)
        XCTAssertEqual(
            CoreToShieldedAmountPolicy.minimumAmountDuffs(
                poolFeeCredits: 212_851_000),
            212_852)
    }

    func testShieldedSweepChoosesPrefixWithLargestNetPayout() {
        let fees: [Int: UInt64] = [2: 100, 3: 150]

        let candidate = ShieldedSweepPlanner.bestCandidate(
            noteValues: [1_000, 1_000, 1],
            feeForActions: { fees[$0] })

        XCTAssertEqual(
            candidate,
            ShieldedSweepCandidate(
                amountCredits: 1_900,
                inputCredits: 2_000,
                feeCredits: 100,
                noteCount: 2))
        XCTAssertEqual(
            ShieldedSweepPlanner.revalidate(
                noteValues: [1_000, 1_000, 1],
                amountCredits: 1_900,
                feeForActions: { fees[$0] }),
            candidate)
    }

    func testShieldedSweepUsesSpendablePrefixWhenFullPrefixCannotPayFee() {
        let notes = [UInt64(200), 100] + Array(repeating: UInt64(1), count: 14)

        let candidate = ShieldedSweepPlanner.bestCandidate(
            noteValues: notes,
            feeForActions: { actions in actions <= 2 ? 100 : 1_000 })

        XCTAssertEqual(
            candidate,
            ShieldedSweepCandidate(
                amountCredits: 200,
                inputCredits: 300,
                feeCredits: 100,
                noteCount: 2))
    }

    func testShieldedSpendableBalanceSubtractsFeeReserve() {
        XCTAssertEqual(
            TransferSpendAmountPolicy.spendableCredits(
                balanceCredits: 10_000_000_000,
                feeReserveCredits: 2_000_000_000),
            8_000_000_000)
        XCTAssertEqual(
            TransferSpendAmountPolicy.spendableCredits(
                balanceCredits: 1_000_000_000,
                feeReserveCredits: 2_000_000_000),
            0)
    }

    func testPlatformShieldScreenshotRegressionUsesSDKSelectableCapacity() {
        let capacity = PlatformShieldCapacity(
            canShield: true,
            accountBalanceCredits: 3_921_114_000,
            usableBalanceCredits: 3_623_849_220,
            feeReserveCredits: 1_000_000_000,
            maxShieldableCredits: 2_623_849_220)

        // Old aggregate-balance Max from the report must be rejected.
        XCTAssertFalse(PlatformShieldAmountPolicy.canSubmit(
            requestedCredits: 2_921_114_000,
            capacity: capacity))
        // The displayed Max is the SDK ceiling floored to whole duffs.
        XCTAssertEqual(
            PlatformShieldAmountPolicy.maximumDuffs(capacity: capacity),
            2_623_849)
        XCTAssertTrue(PlatformShieldAmountPolicy.canSubmit(
            requestedCredits: 2_623_849_000,
            capacity: capacity))
    }

    func testPlatformShieldRejectsOneDuffAboveDisplayedMax() {
        let capacity = PlatformShieldCapacity(
            canShield: true,
            accountBalanceCredits: 3_921_114_000,
            usableBalanceCredits: 3_623_849_220,
            feeReserveCredits: 1_000_000_000,
            maxShieldableCredits: 2_623_849_220)

        XCTAssertFalse(PlatformShieldAmountPolicy.canSubmit(
            requestedCredits: 2_623_850_000,
            capacity: capacity))
    }

    func testPlatformShieldMaxFloorsSubDuffCredits() {
        let capacity = PlatformShieldCapacity(
            canShield: true,
            accountBalanceCredits: 5_000,
            usableBalanceCredits: 5_000,
            feeReserveCredits: 1_000,
            maxShieldableCredits: 3_999)

        XCTAssertEqual(
            PlatformShieldAmountPolicy.maximumDuffs(capacity: capacity),
            3)
    }

    func testPlatformShieldHeldBackNoticeUsesDisplayedAggregateBalance() {
        XCTAssertEqual(
            PlatformShieldAmountPolicy.heldBackCredits(
                displayedPlatformCredits: 4_500_000_000,
                accountBalanceCredits: 3_921_114_000,
                submittedDuffs: 2_623_849),
            1_876_151_000)

        // If the published aggregate briefly lags, do not understate the
        // account-level remainder reported by the coherent SDK preflight.
        XCTAssertEqual(
            PlatformShieldAmountPolicy.heldBackCredits(
                displayedPlatformCredits: 3_000_000_000,
                accountBalanceCredits: 3_921_114_000,
                submittedDuffs: 2_623_849),
            1_297_265_000)
    }

    func testPlatformShieldFailsClosedWithoutResolvedPreflight() {
        XCTAssertFalse(PlatformShieldAmountPolicy.canSubmit(
            requestedCredits: 1_000,
            capacity: nil))
    }

    func testPlatformShieldStaleCacheWaitsForBalancePublication() {
        XCTAssertFalse(PlatformShieldAmountPolicy.shouldRefreshPreflight(
            after: .other,
            awaitingPlatformResync: true))
        XCTAssertTrue(PlatformShieldAmountPolicy.shouldRefreshPreflight(
            after: .balancePublished,
            awaitingPlatformResync: true))
        XCTAssertTrue(PlatformShieldAmountPolicy.shouldRefreshPreflight(
            after: .other,
            awaitingPlatformResync: false))
        XCTAssertTrue(PlatformShieldAmountPolicy.awaitingPlatformResync(
            current: true,
            after: .other))
        XCTAssertFalse(PlatformShieldAmountPolicy.awaitingPlatformResync(
            current: true,
            after: .balancePublished))
    }

    func testPlatformShieldCapacityChangeUpdatesOnlyMaxDerivedAmount() {
        XCTAssertEqual(
            PlatformShieldAmountPolicy.amountAfterCapacityChange(
                currentDuffs: 2_921_114,
                wasMaxDerived: true,
                maxShieldableCredits: 2_623_849_220),
            2_623_849)
        XCTAssertEqual(
            PlatformShieldAmountPolicy.amountAfterCapacityChange(
                currentDuffs: 2_700_000,
                wasMaxDerived: false,
                maxShieldableCredits: 2_623_849_220),
            2_700_000)
        // A typed insufficient-balance failure followed by a failed preflight
        // must not invent a zero Max or silently alter the confirmed value.
        XCTAssertEqual(
            PlatformShieldAmountPolicy.amountAfterCapacityChange(
                currentDuffs: 2_921_114,
                wasMaxDerived: true,
                maxShieldableCredits: nil),
            2_921_114)
    }

    func testShieldedInsufficientBalanceMessageUsesSpendableAmount() {
        let message = TransferSpendAmountPolicy.insufficientBalanceMessage(
            balanceName: "Shielded",
            requestedCredits: 8_000_000_001,
            balanceCredits: 10_000_000_000,
            feeReserveCredits: 2_000_000_000)

        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("Shielded") == true)
        XCTAssertTrue(
            message?.contains("0.08 DASH") == true
                || message?.contains("0,08 DASH") == true)
        XCTAssertNil(
            TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: "Shielded",
                requestedCredits: 8_000_000_000,
                balanceCredits: 10_000_000_000,
                feeReserveCredits: 2_000_000_000))
    }

    func testDuffDenominatedInsufficientBalanceMessageNamesTheBalance() {
        let message = TransferSpendAmountPolicy.insufficientBalanceMessage(
            balanceName: "Transparent",
            requestedDuffs: 50_000_000,
            spendableDuffs: 40_000_000)

        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("Transparent") == true)
        XCTAssertTrue(
            message?.contains("0.4 DASH") == true
                || message?.contains("0,4 DASH") == true)
        XCTAssertNil(
            TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: "Transparent",
                requestedDuffs: 40_000_000,
                spendableDuffs: 40_000_000))
    }

    func testUniqueWithdrawalAddressMatchesDespiteRestoreTimeAndAmountSkew() {
        let activityDate = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            CoreWithdrawalReceiptMatchPolicy.selectedIndex(
                expectedAmountDuffs: 2_000,
                activityDate: activityDate,
                candidates: [
                    CoreWithdrawalReceiptCandidate(
                        amountDuffs: 1_950,
                        date: activityDate.addingTimeInterval(-172_800)),
                ]),
            0)
    }

    func testReusedWithdrawalAddressUsesUniqueAmountAndTimeMatch() {
        let activityDate = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            CoreWithdrawalReceiptMatchPolicy.selectedIndex(
                expectedAmountDuffs: 2_000,
                activityDate: activityDate,
                candidates: [
                    CoreWithdrawalReceiptCandidate(
                        amountDuffs: 2_000,
                        date: activityDate.addingTimeInterval(-172_800)),
                    CoreWithdrawalReceiptCandidate(
                        amountDuffs: 2_000,
                        date: activityDate.addingTimeInterval(60)),
                ]),
            1)
    }

    func testAmbiguousReusedWithdrawalAddressRemainsPending() {
        let activityDate = Date(timeIntervalSince1970: 1_000_000)
        let candidates = [
            CoreWithdrawalReceiptCandidate(
                amountDuffs: 2_000,
                date: activityDate.addingTimeInterval(60)),
            CoreWithdrawalReceiptCandidate(
                amountDuffs: 2_000,
                date: activityDate.addingTimeInterval(120)),
        ]

        XCTAssertNil(
            CoreWithdrawalReceiptMatchPolicy.selectedIndex(
                expectedAmountDuffs: 2_000,
                activityDate: activityDate,
                candidates: candidates))
    }
}

final class JoinDashPayRegistrationPolicyTests: XCTestCase {
    func testSDKUsernameWinsWhenLegacyMirrorWasClearedByNetworkSwitch() {
        XCTAssertTrue(
            JoinDashPayRegistrationPolicy.hasRegisteredUsername(
                hasIdentity: true,
                sdkUsername: "alice",
                legacyRegistrationCompleted: false,
                legacyUsername: nil))
    }

    func testLegacyMirrorRemainsACompatibleFallback() {
        XCTAssertTrue(
            JoinDashPayRegistrationPolicy.hasRegisteredUsername(
                hasIdentity: true,
                sdkUsername: nil,
                legacyRegistrationCompleted: true,
                legacyUsername: "alice"))
    }

    func testIdentityWithoutOwnedUsernameStillShowsJoinFlow() {
        XCTAssertFalse(
            JoinDashPayRegistrationPolicy.hasRegisteredUsername(
                hasIdentity: false,
                sdkUsername: nil,
                legacyRegistrationCompleted: false,
                legacyUsername: nil))
    }

    func testLegacyUsernameWithoutCompletionDoesNotSuppressJoinFlow() {
        XCTAssertFalse(
            JoinDashPayRegistrationPolicy.hasRegisteredUsername(
                hasIdentity: true,
                sdkUsername: nil,
                legacyRegistrationCompleted: false,
                legacyUsername: "stale"))
    }

    func testLegacyMirrorCannotLeakAcrossNetworkWithoutIdentity() {
        XCTAssertFalse(
            JoinDashPayRegistrationPolicy.hasRegisteredUsername(
                hasIdentity: false,
                sdkUsername: nil,
                legacyRegistrationCompleted: true,
                legacyUsername: "testnet-alice"))
    }
}

final class JoinDashPayBannerPolicyTests: XCTestCase {
    func testDismissalHidesBannerBeforeIdentityExists() {
        XCTAssertFalse(
            JoinDashPayBannerPolicy.shouldShow(
                contextReady: true,
                syncDone: true,
                dismissed: true,
                hasRegisteredUsername: false,
                hasRegistrationInProgress: false))
    }

    func testEligibleUndismissedWalletShowsBanner() {
        XCTAssertTrue(
            JoinDashPayBannerPolicy.shouldShow(
                contextReady: true,
                syncDone: true,
                dismissed: false,
                hasRegisteredUsername: false,
                hasRegistrationInProgress: false))
    }

    func testDismissalStorageIsScopedByNetworkAndWallet() {
        let testnetWalletA = JoinDashPayDismissalScope.storageKey(
            networkRawValue: WalletEnvironment.NetworkKind.testnet.rawValue,
            walletIdHex: "wallet-a")
        let mainnetWalletA = JoinDashPayDismissalScope.storageKey(
            networkRawValue: WalletEnvironment.NetworkKind.mainnet.rawValue,
            walletIdHex: "wallet-a")
        let testnetWalletB = JoinDashPayDismissalScope.storageKey(
            networkRawValue: WalletEnvironment.NetworkKind.testnet.rawValue,
            walletIdHex: "wallet-b")

        XCTAssertNotEqual(testnetWalletA, mainnetWalletA)
        XCTAssertNotEqual(testnetWalletA, testnetWalletB)
        XCTAssertEqual(
            testnetWalletA,
            JoinDashPayDismissalScope.storageKey(
                networkRawValue: WalletEnvironment.NetworkKind.testnet.rawValue,
                walletIdHex: "wallet-a"))
    }
}
