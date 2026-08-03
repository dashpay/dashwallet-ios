//
//  SwiftDashSDKCoreLifecycleTests.swift
//  DashWalletTests
//
//  Regression coverage for SDK lifecycle and freshness policies.
//

import XCTest
@testable import dashpay

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
        XCTAssertTrue(PlatformAddressActivityUnitPolicy.unshieldMatches(
            creditedAmountCredits: creditedAmount,
            observedDeltaDuffs: 10_000_000))
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.unshieldMatches(
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
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.exactUnshieldMatches(
            destinationAddress: "tdash1own",
            observedAddress: "tdash1external",
            creditedAmountCredits: 10_000_000_000,
            observedDeltaDuffs: 10_000_000))
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.exactUnshieldMatches(
            destinationAddress: "tdash1own",
            observedAddress: "tdash1own",
            creditedAmountCredits: 10_000_000_000,
            observedDeltaDuffs: 9_999_999))
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
            ShieldedSpendAmountPolicy.spendableCredits(
                balanceCredits: 10_000_000_000,
                feeReserveCredits: 2_000_000_000),
            8_000_000_000)
        XCTAssertEqual(
            ShieldedSpendAmountPolicy.spendableCredits(
                balanceCredits: 1_000_000_000,
                feeReserveCredits: 2_000_000_000),
            0)
    }

    func testShieldedInsufficientBalanceMessageUsesSpendableAmount() {
        let message = ShieldedSpendAmountPolicy.insufficientBalanceMessage(
            requestedCredits: 8_000_000_001,
            balanceCredits: 10_000_000_000,
            feeReserveCredits: 2_000_000_000)

        XCTAssertNotNil(message)
        XCTAssertTrue(
            message?.contains("0.08 DASH") == true
                || message?.contains("0,08 DASH") == true)
        XCTAssertNil(
            ShieldedSpendAmountPolicy.insufficientBalanceMessage(
                requestedCredits: 8_000_000_000,
                balanceCredits: 10_000_000_000,
                feeReserveCredits: 2_000_000_000))
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
