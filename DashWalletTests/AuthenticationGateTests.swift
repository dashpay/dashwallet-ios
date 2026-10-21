//
//  AuthenticationGateTests.swift
//  DashWalletTests
//
//  `AuthenticationGate`'s watchdog over a prompt that stays up until the
//  test dismisses it: the gate, its timer and its cancellation are
//  production; only the presenting service is a stand-in.
//

import XCTest
@testable import dashpay

/// A prompt that suspends until `finishDismissal`, recording whether the
/// gate's watchdog cancelled it.
@MainActor
final class SuspendingAuthenticationPrompt: SendAuthenticationPrompting {
    var didAuthenticate = false
    private(set) var cancelled = false
    /// Fulfilled when the gate presents the prompt.
    let started = XCTestExpectation(description: "Prompt presented")
    /// Fulfilled when the gate's watchdog cancels the prompt.
    let cancellation = XCTestExpectation(description: "Prompt cancelled")
    private var continuation: CheckedContinuation<AuthenticationService.AuthOutcome, Never>?

    func authenticate(usingBiometrics: Bool, spendAmount: UInt64?) async -> AuthenticationService.AuthOutcome {
        started.fulfill()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            Task { @MainActor in
                self.cancelled = true
                self.cancellation.fulfill()
            }
        }
    }

    func finishDismissal(_ result: AuthenticationService.AuthOutcome) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: result)
    }
}

@MainActor
final class AuthenticationGateTests: XCTestCase {
    func testTimeoutCancelsRequestAndWaitsForPromptDismissal() async throws {
        let prompt = SuspendingAuthenticationPrompt()
        var returned = false
        let request = Task {
            let result = await AuthenticationGate.authenticate(biometric: false, timeout: 0.05, prompt: prompt)
            returned = true
            return result
        }
        await fulfillment(of: [prompt.started, prompt.cancellation], timeout: 5)
        XCTAssertFalse(returned, "The overlay must stay hidden until the PIN modal is dismissed")
        prompt.finishDismissal(.cancelled)
        let result = await request.value
        XCTAssertEqual(result, .timedOut)
    }

    func testSuccessfulRequestIsNotCancelledByItsOldWatchdog() async throws {
        let prompt = SuspendingAuthenticationPrompt()
        // A watchdog far beyond the test's own steps: the case is that a
        // completed request is not cancelled later, not that the timer races.
        let request = Task { await AuthenticationGate.authenticate(biometric: false, timeout: 5, prompt: prompt) }
        await fulfillment(of: [prompt.started], timeout: 5)
        prompt.finishDismissal(.authenticated(usedBiometrics: false))
        let result = await request.value
        XCTAssertEqual(result, .ok)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(prompt.cancelled)
    }
}
