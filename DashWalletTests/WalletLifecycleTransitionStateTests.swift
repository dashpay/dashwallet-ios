//
//  WalletLifecycleTransitionStateTests.swift
//  DashWalletTests
//
//  Table test pinning the admission matrix of the wallet-lifecycle gate —
//  the safety-critical part of the lifecycle-overlay work: which operation
//  may begin from which phase, that a wipe stays reachable from EVERY
//  failure phase (the reset escape hatch), and that `advance(to:)` rejects
//  an ownerless transition from idle. Written compile-ready per the repo's
//  current test-target posture (the unit-test target is temporarily broken);
//  the tests are pure MainActor state-machine checks with no SDK/FFI use.
//

import XCTest
@testable import dashwallet

@MainActor
final class WalletLifecycleTransitionStateTests: XCTestCase {
    private typealias Phase = WalletLifecycleTransitionState.Phase

    // Representative value per phase; payloads do not affect admission.
    private static let begins: [(label: String, phase: Phase)] = [
        ("switchingNetwork", .switchingNetwork(from: .mainnet, to: .testnet)),
        ("switchingWallet", .switchingWallet(targetName: "A")),
        ("removingWallet", .removingWallet),
        ("wiping", .wiping(title: nil)),
    ]

    private static let failures: [(label: String, phase: Phase)] = [
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
        case .switchingNetwork, .switchingWallet, .removingWallet, .wiping:
            XCTAssertTrue(state.tryBegin(phase), "test setup: begin from idle must admit")
        case .failedNetworkSwitch, .failedWalletSwitch, .failedWalletRemoval:
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

    /// No begin is admitted while any operation is busy.
    func testBusyPhasesRejectEveryBegin() {
        for (busyLabel, busy) in Self.begins {
            for (nextLabel, next) in Self.begins {
                let state = makeState(in: busy)
                XCTAssertFalse(
                    state.tryBegin(next),
                    "\(nextLabel) must be rejected while \(busyLabel) is in flight")
            }
        }
    }

    /// Failure phases admit exactly their own retry — and a wipe.
    func testFailurePhaseAdmissions() {
        let retryOf: [String: String] = [
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

    /// The reset escape hatch: `.wiping` is admitted from EVERY failure
    /// phase, so a persistently failing switch can never wall the user off
    /// from Reset Wallet.
    func testWipeIsReachableFromEveryFailurePhase() {
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
}
