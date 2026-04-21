//
//  PlatformSendConfirmScreen.swift
//  DashWallet
//
//  Minimal Platform send confirm. Collects amount, authenticates via
//  DSAuthenticationManager (parity with Core send), then hands off to
//  `PlatformSendExecutor` for the actual transferFunds call.
//

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
            Text(NSLocalizedString("Amount (credits)", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("0", text: $amountText)
                .keyboardType(.numberPad)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .background(Color.secondaryBackground)
                .cornerRadius(10)
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
        guard let amount = UInt64(amountText), amount > 0 else { return false }
        return Bech32m.isValidPlatformAddress(destination)
    }

    private func send() {
        guard let amount = UInt64(amountText), amount > 0 else { return }
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
