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
    var cancelled = false
    var started = false
    private var continuation: CheckedContinuation<AuthenticationService.AuthOutcome, Never>?

    func authenticate(usingBiometrics: Bool, spendAmount: UInt64?) async -> AuthenticationService.AuthOutcome {
        started = true
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            Task { @MainActor in self.cancelled = true }
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
            let result = await AuthenticationGate.authenticate(biometric: false, timeout: 0.01, prompt: prompt)
            returned = true
            return result
        }
        while !prompt.cancelled { await Task.yield() }
        XCTAssertTrue(prompt.started)
        XCTAssertFalse(returned, "The overlay must stay hidden until the PIN modal is dismissed")
        prompt.finishDismissal(.cancelled)
        let result = await request.value
        XCTAssertEqual(result, .timedOut)
    }

    func testSuccessfulRequestIsNotCancelledByItsOldWatchdog() async throws {
        let prompt = SuspendingAuthenticationPrompt()
        let request = Task { await AuthenticationGate.authenticate(biometric: false, timeout: 0.01, prompt: prompt) }
        while !prompt.started { await Task.yield() }
        prompt.finishDismissal(.authenticated(usedBiometrics: false))
        let result = await request.value
        XCTAssertEqual(result, .ok)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(prompt.cancelled)
    }
}
