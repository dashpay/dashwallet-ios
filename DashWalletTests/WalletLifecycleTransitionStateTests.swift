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
@testable import dashwallet
#else
@testable import WalletPreparationHarness
#endif

@MainActor
final class WalletLifecycleTransitionStateTests: XCTestCase {
    private typealias Phase = WalletLifecycleTransitionState.Phase

    // Representative value per phase; payloads do not affect admission.
    private static let begins: [(label: String, phase: Phase)] = [
        ("openingWallet", .openingWallet),
        ("switchingNetwork", .switchingNetwork(from: .mainnet, to: .testnet)),
        ("switchingWallet", .switchingWallet(targetName: "A")),
        ("removingWallet", .removingWallet),
        ("addingWallet", .addingWallet(isImport: false)),
        ("wiping", .wiping(title: nil)),
    ]

    private static let failures: [(label: String, phase: Phase)] = [
        ("failedWalletOpen", .failedWalletOpen(WalletPreparationFailure(error: NSError(domain: NSCocoaErrorDomain, code: 134100)))),
        ("failedNetworkSwitch", .failedNetworkSwitch(from: .mainnet, target: .testnet, message: nil)),
        ("failedWalletSwitch", .failedWalletSwitch(targetId: Data([1]), targetName: nil, previousId: nil, message: nil)),
        ("failedWalletRemoval", .failedWalletRemoval(message: nil)),
    ]

    /// Drive a fresh instance into `phase` using only the production API.
    private func makeState(in phase: Phase) -> WalletLifecycleTransitionState {
        let state = WalletLifecycleTransitionState()
        switch phase {
        case .idle:
            break
        case .openingWallet, .switchingNetwork, .switchingWallet, .removingWallet, .addingWallet, .wiping:
            XCTAssertTrue(state.tryBegin(phase), "test setup: begin from idle must admit")
        case .failedWalletOpen, .failedNetworkSwitch, .failedWalletSwitch, .failedWalletRemoval:
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
    /// flow's own composite continuation into its post-add switch.
    func testBusyPhasesRejectEveryBegin() {
        for (busyLabel, busy) in Self.begins {
            for (nextLabel, next) in Self.begins {
                let state = makeState(in: busy)
                let expected = busyLabel == "addingWallet" && nextLabel == "switchingWallet"
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

    /// Failure phases admit exactly their own retry — and a wipe.
    func testFailurePhaseAdmissions() {
        let retryOf: [String: String] = [
            "failedWalletOpen": "openingWallet",
            "failedNetworkSwitch": "switchingNetwork",
            "failedWalletSwitch": "switchingWallet",
            "failedWalletRemoval": "",  // dismiss-only; no retry begin
        ]
        for (failureLabel, failure) in Self.failures {
            for (nextLabel, next) in Self.begins {
                let state = makeState(in: failure)
                let expected = nextLabel == retryOf[failureLabel] || nextLabel == "wiping"
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
}
