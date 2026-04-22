//
//  PlatformSendConfirmScreen.swift
//  DashWallet
//
//  Minimal Platform send confirm. Collects amount, authenticates via
//  DSAuthenticationManager (parity with Core send), then hands off to
//  `PlatformSendExecutor` for the actual transferFunds call.
//

import SwiftDashSDK
import SwiftUI

struct PlatformSendConfirmScreen: View {
    let destination: String
    var onFinish: () -> Void

    @State private var amountText: String = ""
    @State private var isWorking: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            Group {
                Text(NSLocalizedString("Destination", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(destination)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.primaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondaryBackground)
                    .cornerRadius(10)
            }

            amountField

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
            if let successMessage {
                Text(successMessage)
                    .font(.footnote)
                    .foregroundColor(.green)
            }

            Spacer()

            sendButton
        }
        .padding(20)
        .background(Color.primaryBackground)
    }

    private var header: some View {
        HStack {
            Text(NSLocalizedString("Confirm Platform Send", comment: ""))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primaryText)
            Spacer()
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("Amount (DASH)", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("0.0", text: $amountText)
                .keyboardType(.decimalPad)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .background(Color.secondaryBackground)
                .cornerRadius(10)
            if let credits = parsedAmountCredits(), credits > 0 {
                Text("\(credits) credits")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var sendButton: some View {
        Button(action: send) {
            HStack {
                if isWorking {
                    SwiftUI.ProgressView().tint(.white)
                }
                Text(NSLocalizedString("Send", comment: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSend ? Color.blue : Color.gray300)
            .cornerRadius(10)
        }
        .disabled(!canSend || isWorking)
    }

    private var canSend: Bool {
        guard let credits = parsedAmountCredits(), credits > 0 else { return false }
        let lower = destination.lowercased()
        let hasPlatformPrefix = lower.hasPrefix("tdashevo1")
            || lower.hasPrefix("dashevo1")
            || lower.hasPrefix("tdash1")
            || lower.hasPrefix("dash1")
        return hasPlatformPrefix && Bech32m.decode(destination) != nil
    }

    /// Accept either a `.` or `,` decimal separator; convert DASH → credits
    /// (1 DASH = 100_000_000_000 credits). Returns nil when the text is empty
    /// or unparseable, or when the product overflows UInt64.
    private func parsedAmountCredits() -> UInt64? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty,
              let dash = Decimal(string: normalized) else { return nil }
        let credits = dash * Decimal(PlatformCreditsFormatter.creditsPerDash)
        var rounded = Decimal()
        var source = credits
        NSDecimalRound(&rounded, &source, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        guard number.compare(NSDecimalNumber.zero) == .orderedDescending else { return nil }
        guard number.compare(NSDecimalNumber(value: UInt64.max)) != .orderedDescending else {
            return nil
        }
        return number.uint64Value
    }

    private func send() {
        guard let amount = parsedAmountCredits(), amount > 0 else { return }
        isWorking = true
        errorMessage = nil
        successMessage = nil

        DSAuthenticationManager.sharedInstance()
            .authenticate(
                withPrompt: NSLocalizedString("Authorize Platform transfer", comment: ""),
                usingBiometricAuthentication: false,
                alertIfLockout: true
            ) { authenticated, _, _ in
                guard authenticated else {
                    isWorking = false
                    return
                }
                Task { @MainActor in
                    await executeTransfer(amount: amount)
                }
            }
    }

    @MainActor
    private func executeTransfer(amount: UInt64) async {
        defer { isWorking = false }
        do {
            try await PlatformSendExecutor.shared.transfer(
                destination: destination,
                amount: amount)
            successMessage = NSLocalizedString("Transfer submitted", comment: "")
            PlatformAddressSyncCoordinator.shared.start(
                for: currentAppNetwork() ?? .testnet)
            Task { await PlatformAddressSyncCoordinator.shared.syncNow() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func currentAppNetwork() -> AppNetwork? {
        let chain = DWEnvironment.sharedInstance().currentChain
        if chain.isMainnet() { return .mainnet }
        if chain.isTestnet() { return .testnet }
        return nil
    }
}
