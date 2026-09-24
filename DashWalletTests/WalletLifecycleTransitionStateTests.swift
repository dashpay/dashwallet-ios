//
//  WalletLifecycleTransitionStateTests.swift
//  DashWalletTests
//
//  Table test pinning the admission matrix of the wallet-lifecycle gate —
//  the safety-critical part of the lifecycle-overlay work: which operation
//  may begin from which phase, that an authorized wipe is admitted after
//  every failure phase, and that `advance(to:)` rejects
//  an ownerless transition from idle. Written compile-ready per the repo's
//  current test-target posture (the unit-test target is temporarily broken);
//  the tests are pure MainActor state-machine checks with no SDK/FFI use.
//

import XCTest
#if canImport(dashpay)
@testable import dashpay
#elseif canImport(dashwallet)
@testable import dashpay
#else
@testable import WalletPreparationHarness
#endif

@MainActor
final class WalletLifecycleTransitionStateTests: XCTestCase {
    private typealias Phase = WalletLifecycleTransitionState.Phase

    // Representative value per phase; payloads do not affect admission.
    private static let begins: [(label: String, phase: Phase)] = [
        ("openingWallet", .openingWallet),
        ("migratingLegacyWallet", .migratingLegacyWallet),
        ("switchingNetwork", .switchingNetwork(from: .mainnet, to: .testnet)),
        ("switchingWallet", .switchingWallet(targetName: "A")),
        ("removingWallet", .removingWallet),
        ("addingWallet", .addingWallet(isImport: false)),
        ("wiping", .wiping(title: nil)),
    ]

    private static let failures: [(label: String, phase: Phase)] = [
        ("failedWalletOpen", .failedWalletOpen(WalletPreparationFailure(error: NSError(domain: NSCocoaErrorDomain, code: 134100)))),
        ("failedLegacyMigration", .failedLegacyMigration(WalletPreparationFailure(legacyMigration: .failed))),
        ("failedNetworkSwitch", .failedNetworkSwitch(from: .mainnet, target: .testnet, message: nil)),
        ("failedWalletSwitch", .failedWalletSwitch(targetId: Data([1]), targetName: nil, previousId: nil, message: nil)),
        ("failedWalletRemoval", .failedWalletRemoval(message: nil)),
    ]

    /// Busy → begin pairs admitted besides the plain from-idle rule: the add
    /// flow's composite continuation, and the runtime taking the launch
    /// window over from the legacy-migration hold once the wallet landed.
    private static let busyContinuations: Set<String> = [
        "addingWallet→switchingWallet",
        "migratingLegacyWallet→openingWallet",
    ]

    /// Drive a fresh instance into `phase` using only the production API.
    private func makeState(in phase: Phase) -> WalletLifecycleTransitionState {
        let state = WalletLifecycleTransitionState()
        switch phase {
        case .idle:
            break
        case .openingWallet, .migratingLegacyWallet, .switchingNetwork, .switchingWallet, .removingWallet,
             .addingWallet, .wiping:
            XCTAssertTrue(state.tryBegin(phase), "test setup: begin from idle must admit")
        case .failedWalletOpen, .failedLegacyMigration, .failedNetworkSwitch, .failedWalletSwitch,
             .failedWalletRemoval:
            state.fail(phase)
        }
        return state
    }

    // MARK: - Admission matrix

    /// Every begin is admitted from idle.
    func testEveryOperationBeginsFromIdle() {
        for (label, begin) in Self.begins {
            let state = makeState(in: .idle)
            XCTAssertTrue(state.tryBegin(begin), "\(label) must begin from idle")
        }
    }

    /// No begin is admitted while any operation is busy — except the add
    /// flow's own composite continuation into its post-add switch, and the
    /// runtime's takeover of the legacy-migration hold.
    func testBusyPhasesRejectEveryBegin() {
        for (busyLabel, busy) in Self.begins {
            for (nextLabel, next) in Self.begins {
                let state = makeState(in: busy)
                let expected = Self.busyContinuations.contains("\(busyLabel)→\(nextLabel)")
                XCTAssertEqual(
                    state.tryBegin(next), expected,
                    "\(busyLabel) → \(nextLabel): expected admitted=\(expected)")
            }
        }
    }

    /// The add flow's window advances Creating → Switching without dropping
    /// through idle.
    func testAddFlowCompositeAdvancesToSwitch() {
        let state = makeState(in: .addingWallet(isImport: false))
        XCTAssertTrue(state.tryBegin(.switchingWallet(targetName: "A")))
        XCTAssertEqual(state.phase, .switchingWallet(targetName: "A"))
    }

    /// Failure phases admit exactly their own retry — and a wipe. The
    /// legacy-migration card additionally admits the runtime's wallet open,
    /// because a late import can land while the card is showing.
    func testFailurePhaseAdmissions() {
        let retryOf: [String: [String]] = [
            "failedWalletOpen": ["openingWallet"],
            "failedLegacyMigration": ["migratingLegacyWallet", "openingWallet"],
            "failedNetworkSwitch": ["switchingNetwork"],
            "failedWalletSwitch": ["switchingWallet"],
            "failedWalletRemoval": [],  // dismiss-only; no retry begin
        ]
        for (failureLabel, failure) in Self.failures {
            for (nextLabel, next) in Self.begins {
                let state = makeState(in: failure)
                let expected = retryOf[failureLabel, default: []].contains(nextLabel) || nextLabel == "wiping"
                XCTAssertEqual(
                    state.tryBegin(next), expected,
                    "\(failureLabel) → \(nextLabel): expected admitted=\(expected)")
            }
        }
    }

    /// This tests admission only, not the existence of a destructive UI action.
    func testAuthorizedWipeIsAdmittedFromEveryFailurePhase() {
        for (failureLabel, failure) in Self.failures {
            let state = makeState(in: failure)
            XCTAssertTrue(
                state.tryBegin(.wiping(title: nil)),
                "wipe must be admitted from \(failureLabel)")
        }
    }

    /// A rejected begin leaves the phase untouched.
    func testRejectedBeginDoesNotMutatePhase() {
        let busy = Phase.switchingWallet(targetName: "A")
        let state = makeState(in: busy)
        _ = state.tryBegin(.wiping(title: nil))
        XCTAssertEqual(state.phase, busy)
    }

    // MARK: - advance / finish / fail

    /// The composite remove flow's phase change never drops through idle.
    func testAdvanceMovesBetweenBusyPhases() {
        let state = makeState(in: .switchingWallet(targetName: "A"))
        state.advance(to: .removingWallet)
        XCTAssertEqual(state.phase, .removingWallet)
    }

    /// (`advance` from idle is deliberately not exercised here: its hard
    /// guard also raises `assertionFailure`, which would crash a Debug test
    /// run. The Release behavior — reject and keep `.idle` — is documented
    /// at the implementation.)
    func testFinishAndFailRoundTrip() {
        let state = makeState(in: .switchingNetwork(from: .mainnet, to: .testnet))
        state.fail(.failedNetworkSwitch(from: .mainnet, target: .testnet, message: "x"))
        XCTAssertEqual(
            state.phase,
            .failedNetworkSwitch(from: .mainnet, target: .testnet, message: "x"))
        XCTAssertTrue(state.tryBegin(.switchingNetwork(from: .mainnet, to: .testnet)))
        state.finish()
        XCTAssertEqual(state.phase, .idle)
    }

    func testWalletOpenBlocksCompetingOperationsUntilDataIsReady() async throws {
        let state = WalletLifecycleTransitionState()
        let result = try await state.prepareWallet {
            XCTAssertEqual(state.phase, .openingWallet)
            XCTAssertFalse(state.tryBegin(.switchingWallet(targetName: "Other wallet")))
            await Task.yield()
            XCTAssertEqual(state.phase, .openingWallet)
            return 42
        } failure: { WalletPreparationFailure(error: $0) }
        XCTAssertEqual(result, 42)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.preparationFailure)
    }

    func testFailedOpenStaysBlockedAndSuccessfulRetryClearsDiagnostic() async throws {
        let state = WalletLifecycleTransitionState()
        let original = NSError(domain: NSCocoaErrorDomain, code: 134100)
        do {
            try await state.prepareWallet { throw original } failure: { WalletPreparationFailure(error: $0) }
            XCTFail("The original failure must reach runtime teardown")
        } catch {
            XCTAssertTrue(error as NSError === original)
        }
        guard case let .failedWalletOpen(detail) = state.phase else { return XCTFail("Expected blocking failure") }
        XCTAssertEqual(detail, state.preparationFailure)
        XCTAssertFalse(state.tryBegin(.removingWallet))

        try await state.prepareWallet {
            XCTAssertEqual(state.phase, .openingWallet)
            XCTAssertNil(state.preparationFailure)
        } failure: { WalletPreparationFailure(error: $0) }
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.preparationFailure)
    }

    func testOpenFailurePreservesInteractiveSwitchOwnerAndRecoveryDestination() async {
        let phases: [Phase] = [
            .switchingNetwork(from: .mainnet, to: .testnet),
            .switchingWallet(targetName: "Destination")
        ]
        for phase in phases {
            let state = makeState(in: phase)
            do {
                try await state.prepareWallet {
                    XCTAssertEqual(state.phase, phase)
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
                } failure: { WalletPreparationFailure(error: $0) }
                XCTFail("Expected error")
            } catch {}
            XCTAssertEqual(state.phase, phase)
            XCTAssertEqual(state.preparationFailure?.kind, .storage)
            state.finish()
            XCTAssertNil(state.preparationFailure)
        }
    }

    func testSuccessfulOpenDoesNotDismissInteractiveSwitch() async throws {
        let phase = Phase.switchingNetwork(from: .mainnet, to: .testnet)
        let state = makeState(in: phase)
        try await state.prepareWallet {} failure: { WalletPreparationFailure(error: $0) }
        XCTAssertEqual(state.phase, phase)
    }

    func testUnrelatedStartupFailureKeepsExistingRecoveryFlow() async {
        let state = WalletLifecycleTransitionState()
        do {
            try await state.prepareWallet { throw NSError(domain: NSURLErrorDomain, code: -1009) } failure: { _ in nil }
            XCTFail("Expected error")
        } catch {}
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.preparationFailure)
    }

    // MARK: - Legacy-migration launch hold

    /// The failure record is taken only from the hold's own phase, and
    /// `finish()` clears it with the phase.
    func testFailLegacyMigrationRecordsDiagnosticOnlyFromItsOwnPhase() {
        let failure = WalletPreparationFailure(legacyMigration: .unknownChain)
        let idle = WalletLifecycleTransitionState()
        idle.failLegacyMigration(failure)
        XCTAssertEqual(idle.phase, .idle)
        XCTAssertNil(idle.preparationFailure)

        let state = makeState(in: .migratingLegacyWallet)
        state.setLegacyLaunchHold(active: true)
        state.failLegacyMigration(failure)
        XCTAssertEqual(state.phase, .failedLegacyMigration(failure))
        XCTAssertEqual(state.preparationFailure, failure)
        XCTAssertEqual(failure.codes, ["KeyMigrator:unknownChain"])
        XCTAssertTrue(state.tryBegin(.migratingLegacyWallet))
        XCTAssertNil(state.preparationFailure)
        state.finish()
        XCTAssertEqual(state.phase, .idle)
    }

    /// Scriptable stand-in for the migrator, wallet gate and presenter.
    @MainActor
    private final class HoldProbe {
        var settled = false
        var presence: WalletEnvironment.WalletPresence = .absent
        var legacy: LegacyWalletMigrationLaunchCoordinator.LegacyMaterialState = .pending
        var reason: WalletPreparationFailure.LegacyMigrationReason = .failed
        var migrationStarts = 0
        var overlayActivations = 0
        var outcomes: [Bool] = []
        /// What a retry's migrator run does once it actually starts; nil
        /// leaves the run pending until the test scripts its outcome.
        var onMigrationRun: (() -> Void)?
        /// Announces a material change to the card's watcher.
        var materialChanged: AsyncStream<Void>.Continuation?

        func makeCoordinator(state: WalletLifecycleTransitionState,
                             settleTimeout: TimeInterval = 5,
                             lateSuccessInterval: TimeInterval = 0.005) -> LegacyWalletMigrationLaunchCoordinator {
            LegacyWalletMigrationLaunchCoordinator(state: state, dependencies: .init(
                isSettled: { self.settled },
                walletPresence: { self.presence },
                legacyMaterial: { self.legacy },
                deferralReason: { self.reason },
                startMigration: {
                    // The production contract (`restartMigration`): terminal
                    // flags are cleared synchronously; the run itself lands
                    // later on its own queue.
                    self.migrationStarts += 1
                    self.settled = false
                    if let run = self.onMigrationRun {
                        Task { @MainActor in run() }
                    }
                },
                activateOverlay: { self.overlayActivations += 1 },
                walletMaterialChanges: { AsyncStream { self.materialChanged = $0 } },
                pollInterval: 0.005,
                settleTimeout: settleTimeout,
                lateSuccessInterval: lateSuccessInterval))
        }
    }

    private func settle(_ condition: @autoclosure @escaping @MainActor () -> Bool, within seconds: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func testHoldPresentsWalletOnceTheMigratorDeliversIt() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        let coordinator = probe.makeCoordinator(state: state)
        coordinator.begin { probe.outcomes.append($0) }
        XCTAssertEqual(state.phase, .migratingLegacyWallet)
        XCTAssertEqual(probe.overlayActivations, 1)
        coordinator.begin { probe.outcomes.append($0) }  // ignored: a hold is active
        await Task.yield()
        XCTAssertEqual(probe.outcomes, [])

        probe.presence = .present
        probe.legacy = .absent
        probe.settled = true
        await settle(probe.outcomes == [true])
        XCTAssertEqual(probe.outcomes, [true])
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(probe.migrationStarts, 0)
    }

    func testNothingToMigrateReportsSetupWithoutACard() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        probe.legacy = .absent
        let coordinator = probe.makeCoordinator(state: state)
        coordinator.begin { probe.outcomes.append($0) }
        probe.settled = true
        await settle(probe.outcomes == [false])
        XCTAssertEqual(probe.outcomes, [false])
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.preparationFailure)
    }

    /// A settled failure with legacy material still present never reports:
    /// the card blocks, Try Again re-runs the migrator, and only a wallet
    /// releases the launch.
    func testFailedImportHoldsOnTheCardUntilARetryLandsTheWallet() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        probe.reason = .unknownChain
        let coordinator = probe.makeCoordinator(state: state)
        coordinator.begin { probe.outcomes.append($0) }
        probe.settled = true
        await settle({ if case .failedLegacyMigration = state.phase { return true } else { return false } }())
        guard case let .failedLegacyMigration(failure) = state.phase else { return XCTFail("expected the failure card") }
        XCTAssertEqual(failure.codes, ["KeyMigrator:unknownChain"])
        XCTAssertEqual(state.preparationFailure, failure)
        XCTAssertEqual(probe.outcomes, [])
        XCTAssertFalse(state.tryBegin(.switchingWallet(targetName: "A")), "the card blocks other operations")

        coordinator.retry()
        XCTAssertEqual(probe.migrationStarts, 1)
        XCTAssertEqual(state.phase, .migratingLegacyWallet)
        XCTAssertNil(state.preparationFailure)
        coordinator.retry()  // ignored while progress is showing
        XCTAssertEqual(probe.migrationStarts, 1)

        probe.presence = .present
        probe.legacy = .absent
        probe.settled = true
        await settle(probe.outcomes == [true])
        XCTAssertEqual(probe.outcomes, [true])
        XCTAssertEqual(state.phase, .idle)
    }

    /// The migrator only enqueues a retry; its run starts later. Between the
    /// two, the previous run's verdict must not be read as the new run's:
    /// the card stays down, a second Try Again is rejected, and the run's
    /// eventual success completes the launch.
    func testRetryWithAsynchronousMigratorStartDoesNotReShowThePreviousFailure() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        let coordinator = probe.makeCoordinator(state: state)
        coordinator.begin { probe.outcomes.append($0) }
        probe.settled = true
        await settle({ if case .failedLegacyMigration = state.phase { return true } else { return false } }())

        var releaseRun: (() -> Void)?
        probe.onMigrationRun = {
            // The queued run is in flight; nothing terminal is written yet.
            releaseRun = {
                probe.presence = .present
                probe.legacy = .absent
                probe.settled = true
            }
        }
        coordinator.retry()
        XCTAssertEqual(probe.migrationStarts, 1)
        for _ in 0..<20 { await Task.yield(); try? await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertEqual(state.phase, .migratingLegacyWallet, "stale terminal flags must not re-show the card")
        XCTAssertEqual(probe.outcomes, [])
        coordinator.retry()
        XCTAssertEqual(probe.migrationStarts, 1, "no second Try Again while the retry is queued")

        releaseRun?()
        await settle(probe.outcomes == [true])
        XCTAssertEqual(probe.outcomes, [true])
        XCTAssertEqual(state.phase, .idle)
    }

    /// Legacy material was seen at launch; a later keychain read error must
    /// keep the card (with its own code), never release into setup.
    func testUnreadableKeychainAfterInitialDetectionHoldsOnTheCard() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        let coordinator = probe.makeCoordinator(state: state)
        coordinator.begin { probe.outcomes.append($0) }
        probe.legacy = .unreadable
        probe.settled = true
        await settle({ if case .failedLegacyMigration = state.phase { return true } else { return false } }())
        guard case let .failedLegacyMigration(failure) = state.phase else { return XCTFail("expected the failure card") }
        XCTAssertEqual(failure.codes, ["KeyMigrator:unreadableKeychain"])
        XCTAssertEqual(probe.outcomes, [], "an unreadable keychain never releases the hold")

        // Once the keychain reads again and confirms there is nothing, a
        // retry may release into setup.
        probe.onMigrationRun = {
            probe.legacy = .absent
            probe.settled = true
        }
        coordinator.retry()
        await settle(probe.outcomes == [false])
        XCTAssertEqual(probe.outcomes, [false])
        XCTAssertEqual(state.phase, .idle)
    }

    /// An SDK wallet inventory that cannot be read while the app is active
    /// is a failure to show, not "nothing to migrate": the card blocks
    /// instead of setup, and a later successful read completes the launch.
    func testUnreadableWalletInventoryShowsTheCardNotSetup() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        probe.presence = .unknown
        probe.legacy = .absent
        probe.settled = true
        let coordinator = probe.makeCoordinator(state: state, lateSuccessInterval: 30)
        coordinator.begin { probe.outcomes.append($0) }
        await settle({ if case .failedLegacyMigration = state.phase { return true } else { return false } }())
        guard case let .failedLegacyMigration(failure) = state.phase else { return XCTFail("expected the failure card") }
        XCTAssertEqual(failure.kind, .keychain)
        XCTAssertEqual(failure.codes, ["Keychain:unreadableWalletInventory"])
        XCTAssertEqual(probe.outcomes, [], "an unreadable inventory never releases into setup")

        await settle(probe.materialChanged != nil)
        probe.presence = .present
        probe.materialChanged?.yield()
        await settle(probe.outcomes == [true], within: 1)
        XCTAssertEqual(probe.outcomes, [true])
        XCTAssertEqual(state.phase, .idle)
    }

    /// Successive reads that answer unknown, unknown, present — the first
    /// two fail, the third sees the wallet — with the migration already
    /// done. Every verdict comes from one snapshot: the settled verdict is
    /// the card, never setup, and the next read that sees the wallet
    /// completes the launch into it.
    func testUnknownUnknownPresentReadsNeverReleaseIntoSetup() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        var reads: [WalletEnvironment.WalletPresence] = [.unknown, .unknown, .present]
        let coordinator = LegacyWalletMigrationLaunchCoordinator(state: state, dependencies: .init(
            isSettled: { true },
            walletPresence: { reads.count > 1 ? reads.removeFirst() : reads[0] },
            legacyMaterial: { .absent },
            deferralReason: { .failed },
            startMigration: { probe.migrationStarts += 1 },
            activateOverlay: {},
            walletMaterialChanges: { AsyncStream { probe.materialChanged = $0 } },
            pollInterval: 0.005,
            settleTimeout: 5,
            lateSuccessInterval: 0.005))
        coordinator.begin { probe.outcomes.append($0) }
        await settle(probe.outcomes == [true], within: 1)
        XCTAssertEqual(probe.outcomes, [true], "an unreadable read must never be taken for an absent wallet")
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(probe.migrationStarts, 0)
    }

    /// A takeover whose open fails for an unrelated reason (the failure
    /// mapper returns nil — e.g. no selectable wallet yet) must hand the
    /// window back to the hold, which is still waiting, rather than clear it.
    func testPrepareWalletReturnsTheWindowToTheHoldOnAnUnrelatedFailure() async {
        for viaCard in [false, true] {
            let state = WalletLifecycleTransitionState()
            let probe = HoldProbe()
            let coordinator = probe.makeCoordinator(state: state)
            coordinator.begin { probe.outcomes.append($0) }
            if viaCard {
                probe.settled = true
                await settle({ if case .failedLegacyMigration = state.phase { return true } else { return false } }())
            }
            let holdPhase = state.phase
            let held = state.preparationFailure
            XCTAssertEqual(viaCard, held != nil)

            do {
                try await state.prepareWallet {
                    XCTAssertEqual(state.phase, .openingWallet)
                    throw NSError(domain: "WalletNotFound", code: 1)
                } failure: { _ in nil }
                XCTFail("expected the open failure")
            } catch {}
            XCTAssertEqual(state.phase, holdPhase, "the hold must get its window back after \(holdPhase.logLabel)")
            XCTAssertEqual(state.preparationFailure, held, "the card's diagnostic comes back with the card")
            XCTAssertEqual(probe.outcomes, [], "the hold is still waiting for a wallet")

            // Late success is noticed from either phase without Try Again.
            probe.presence = .present
            probe.settled = true
            await settle(probe.outcomes == [true])
            XCTAssertEqual(probe.outcomes, [true])
            XCTAssertEqual(state.phase, .idle)
        }
    }

    /// If the hold reports while the takeover's open is running, it has no
    /// watcher, timeout or Try Again left. An unrelated open failure must
    /// then release the window, not restore a hold phase nothing can clear.
    func testPrepareWalletDoesNotRestoreAHoldThatReportedDuringTheOpen() async {
        for viaCard in [false, true] {
            let state = WalletLifecycleTransitionState()
            let probe = HoldProbe()
            let coordinator = probe.makeCoordinator(state: state)
            coordinator.begin { probe.outcomes.append($0) }
            if viaCard {
                probe.settled = true
                await settle({ if case .failedLegacyMigration = state.phase { return true } else { return false } }())
            }
            XCTAssertTrue(state.legacyLaunchHoldActive)

            do {
                try await state.prepareWallet {
                    XCTAssertEqual(state.phase, .openingWallet)
                    probe.presence = .present
                    probe.settled = true
                    await self.settle(probe.outcomes == [true])
                    XCTAssertFalse(state.legacyLaunchHoldActive)
                    throw NSError(domain: "SDKInit", code: 1)
                } failure: { _ in nil }
                XCTFail("expected the open failure")
            } catch {}
            XCTAssertEqual(state.phase, .idle, "a reported hold must not be restored (viaCard=\(viaCard))")
            XCTAssertNil(state.preparationFailure)
            XCTAssertEqual(probe.outcomes, [true])
        }
    }

    /// The migrator can settle with a failure while the runtime owns the
    /// window (SDK material present, none selectable). The hold's verdict
    /// is deferred, not lost: an unrelated open failure then hands back the
    /// failure card with Try Again, never a progress card nothing clears.
    func testVerdictReachedDuringTheTakeoverComesBackAsTheFailureCard() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        probe.reason = .unknownChain
        let coordinator = probe.makeCoordinator(state: state)
        coordinator.begin { probe.outcomes.append($0) }

        do {
            try await state.prepareWallet {
                XCTAssertEqual(state.phase, .openingWallet)
                probe.settled = true  // hasWallet stays false, legacy stays pending
                await self.settle(state.deferredLegacyFailure != nil)
                XCTAssertEqual(state.phase, .openingWallet, "the verdict must wait behind the open")
                XCTAssertEqual(state.deferredLegacyFailure?.codes, ["KeyMigrator:unknownChain"])
                throw NSError(domain: "SDKInit", code: 1)
            } failure: { _ in nil }
            XCTFail("expected the open failure")
        } catch {}
        guard case let .failedLegacyMigration(failure) = state.phase else {
            return XCTFail("expected the failure card, got \(state.phase.logLabel)")
        }
        XCTAssertEqual(failure.codes, ["KeyMigrator:unknownChain"])
        XCTAssertEqual(state.preparationFailure, failure)
        XCTAssertNil(state.deferredLegacyFailure)
        XCTAssertEqual(probe.outcomes, [])

        // Try Again works from the handed-back card and discards the verdict.
        coordinator.retry()
        XCTAssertEqual(probe.migrationStarts, 1)
        XCTAssertEqual(state.phase, .migratingLegacyWallet)
        probe.presence = .present
        probe.legacy = .absent
        probe.settled = true
        await settle(probe.outcomes == [true])
        XCTAssertEqual(probe.outcomes, [true])
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.deferredLegacyFailure)
    }

    /// A verdict deferred behind an open that then succeeds is dropped with
    /// the hold: the wallet is present and the runtime owns recovery.
    func testDeferredVerdictIsDroppedWhenTheHoldReports() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        let coordinator = probe.makeCoordinator(state: state)
        coordinator.begin { probe.outcomes.append($0) }
        let result = try? await state.prepareWallet {
            probe.settled = true
            await self.settle(state.deferredLegacyFailure != nil)
            probe.presence = .present
            await self.settle(probe.outcomes == [true])
            return 1
        } failure: { _ in nil }
        XCTAssertEqual(result, 1)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.deferredLegacyFailure)
    }

    /// A wallet that landed releases the hold before the migrator settles
    /// (several DashSync wallets: the first import is open while a later
    /// one is still wedged).
    func testWalletPresenceReleasesTheHoldBeforeSettlement() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        let coordinator = probe.makeCoordinator(state: state)
        coordinator.begin { probe.outcomes.append($0) }
        probe.presence = .present  // settled stays false
        await settle(probe.outcomes == [true])
        XCTAssertEqual(probe.outcomes, [true])
        XCTAssertEqual(state.phase, .idle)
    }

    /// A verdict reached while another operation owns the window is shown
    /// when that operation releases it, with Try Again available.
    func testVerdictReachedBehindABusyWindowIsShownWhenItFrees() async {
        let state = WalletLifecycleTransitionState()
        XCTAssertTrue(state.tryBegin(.switchingNetwork(from: .mainnet, to: .testnet)))
        let probe = HoldProbe()
        let coordinator = probe.makeCoordinator(state: state)
        coordinator.begin { probe.outcomes.append($0) }
        probe.settled = true
        await settle(state.deferredLegacyFailure != nil)
        XCTAssertEqual(state.phase, .switchingNetwork(from: .mainnet, to: .testnet), "the verdict waits for the switch")
        state.finish()
        guard case let .failedLegacyMigration(failure) = state.phase else { return XCTFail("expected the card, got \(state.phase.logLabel)") }
        XCTAssertEqual(state.preparationFailure, failure)
        XCTAssertNil(state.deferredLegacyFailure)
        XCTAssertEqual(probe.outcomes, [])
        coordinator.retry()
        XCTAssertEqual(probe.migrationStarts, 1)
        XCTAssertEqual(state.phase, .migratingLegacyWallet)
    }

    /// Without an active hold, `finish()` still goes to idle and a stray
    /// verdict is rejected.
    func testFinishWithoutAHoldGoesIdle() {
        let state = WalletLifecycleTransitionState()
        XCTAssertTrue(state.tryBegin(.switchingNetwork(from: .mainnet, to: .testnet)))
        state.failLegacyMigration(WalletPreparationFailure(legacyMigration: .failed))
        XCTAssertNil(state.deferredLegacyFailure)
        state.finish()
        XCTAssertEqual(state.phase, .idle)
    }

    /// A window busy at begin does not lose the card: the verdict takes the
    /// window once it is free.
    func testVerdictTakesTheWindowWhenBeginCouldNot() async {
        let state = WalletLifecycleTransitionState()
        XCTAssertTrue(state.tryBegin(.switchingNetwork(from: .mainnet, to: .testnet)))
        let probe = HoldProbe()
        let coordinator = probe.makeCoordinator(state: state)
        coordinator.begin { probe.outcomes.append($0) }
        XCTAssertEqual(state.phase, .switchingNetwork(from: .mainnet, to: .testnet), "the hold must not steal a busy window")
        state.finish()
        probe.settled = true
        await settle({ if case .failedLegacyMigration = state.phase { return true } else { return false } }())
        guard case .failedLegacyMigration = state.phase else { return XCTFail("expected the card, got \(state.phase.logLabel)") }
        XCTAssertEqual(probe.outcomes, [])
    }

    /// While the card is up, a material-change announcement re-checks the
    /// wallet immediately; the slow fallback poll is not what completes it.
    func testMaterialChangeAnnouncementCompletesTheLaunchFromTheCard() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        let coordinator = probe.makeCoordinator(state: state, lateSuccessInterval: 30)
        coordinator.begin { probe.outcomes.append($0) }
        probe.settled = true
        await settle({ if case .failedLegacyMigration = state.phase { return true } else { return false } }())
        await settle(probe.materialChanged != nil)
        probe.presence = .present
        probe.materialChanged?.yield()
        await settle(probe.outcomes == [true], within: 1)
        XCTAssertEqual(probe.outcomes, [true], "the announcement, not the 30 s fallback, must complete the launch")
        XCTAssertEqual(state.phase, .idle)
    }

    /// The runtime's real entry point takes the launch window over from
    /// either hold phase, so the hold's release cannot dismiss an open in
    /// progress and an open failure lands on the usual blocking card.
    func testPrepareWalletTakesOverFromEitherHoldPhaseAndKeepsItsFailure() async {
        for holdPhase in [Phase.migratingLegacyWallet, .failedLegacyMigration(WalletPreparationFailure(legacyMigration: .failed))] {
            let state = WalletLifecycleTransitionState()
            let probe = HoldProbe()
            let coordinator = probe.makeCoordinator(state: state)
            coordinator.begin { probe.outcomes.append($0) }
            if case .failedLegacyMigration = holdPhase {
                probe.settled = true
                await settle({ if case .failedLegacyMigration = state.phase { return true } else { return false } }())
            }

            let original = NSError(domain: NSCocoaErrorDomain, code: 134100)
            do {
                try await state.prepareWallet {
                    XCTAssertEqual(state.phase, .openingWallet, "takeover from \(holdPhase.logLabel)")
                    // The imported wallet exists; the hold notices and releases
                    // while the open is still running.
                    probe.presence = .present
                    probe.settled = true
                    await self.settle(probe.outcomes == [true])
                    XCTAssertEqual(state.phase, .openingWallet, "the hold's release must not dismiss the runtime's window")
                    throw original
                } failure: { WalletPreparationFailure(error: $0) }
                XCTFail("expected the open failure")
            } catch {
                XCTAssertTrue(error as NSError === original)
            }
            XCTAssertEqual(probe.outcomes, [true])
            guard case .failedWalletOpen = state.phase else {
                return XCTFail("open failure after takeover from \(holdPhase.logLabel) must block on failedWalletOpen, got \(state.phase.logLabel)")
            }
        }
    }

    /// Past the timeout the card shows with its own code, but a run that
    /// finishes afterwards still completes the launch without Try Again.
    func testOverdueMigratorShowsTheCardAndALateSuccessStillCompletesTheLaunch() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        let coordinator = probe.makeCoordinator(state: state, settleTimeout: 0.02)
        coordinator.begin { probe.outcomes.append($0) }
        await settle({ if case .failedLegacyMigration = state.phase { return true } else { return false } }())
        guard case let .failedLegacyMigration(failure) = state.phase else { return XCTFail("expected the failure card") }
        XCTAssertEqual(failure.codes, ["KeyMigrator:timedOut"])

        probe.presence = .present
        await settle(probe.outcomes == [true])
        XCTAssertEqual(probe.outcomes, [true])
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(probe.migrationStarts, 0)
    }

    /// When the runtime has already taken the window over for the imported
    /// wallet, the hold reports without clearing the runtime's phase.
    func testHoldDoesNotClearAWindowTheRuntimeTookOver() async {
        let state = WalletLifecycleTransitionState()
        let probe = HoldProbe()
        let coordinator = probe.makeCoordinator(state: state)
        coordinator.begin { probe.outcomes.append($0) }
        XCTAssertTrue(state.tryBegin(.openingWallet), "runtime takeover from the hold")
        probe.presence = .present
        probe.settled = true
        await settle(probe.outcomes == [true])
        XCTAssertEqual(probe.outcomes, [true])
        XCTAssertEqual(state.phase, .openingWallet)
    }
}
