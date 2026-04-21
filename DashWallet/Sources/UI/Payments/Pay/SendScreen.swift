//
//  SendScreen.swift
//  DashWallet
//

import SwiftUI
import UIKit

struct SendScreen: View {
    @ObservedObject var viewModel: SendViewModel
    var onClose: () -> Void
    var onScanQR: () -> Void
    var onContinueCore: (String) -> Void
    var onContinuePlatform: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            header

            ChainNetworkToggle(selection: $viewModel.network)
                .padding(.horizontal, 20)

            addressField

            if let suggestion = viewModel.clipboardSuggestion {
                clipboardChip(for: suggestion)
            }

            scanRow

            Spacer()

            continueButton
        }
        .padding(.bottom, 20)
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
            }
            Spacer()
            Text(NSLocalizedString("Send", comment: ""))
                .font(.headline)
                .foregroundColor(.primaryText)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("Address", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $viewModel.addressText, axis: .vertical)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.primaryText)
                .padding(12)
                .background(Color.secondaryBackground)
                .cornerRadius(10)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .lineLimit(2...4)
        }
        .padding(.horizontal, 20)
    }

    private var placeholder: String {
        switch viewModel.network {
        case .core: return NSLocalizedString("XpEBa5... or BIP21 URI", comment: "")
        case .platform: return NSLocalizedString("tdashevo1... / dashevo1...", comment: "")
        }
    }

    private func clipboardChip(for suggestion: SendViewModel.ClipboardSuggestion) -> some View {
        Button(action: { viewModel.useClipboardSuggestion() }) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Send to copied address", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(truncate(suggestion.address))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(suggestion.network.title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray300.opacity(0.3))
                    .cornerRadius(8)
            }
            .padding(12)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(10)
        }
        .padding(.horizontal, 20)
    }

    private var scanRow: some View {
        HStack(spacing: 12) {
            Button(action: onScanQR) {
                HStack(spacing: 6) {
                    Image(systemName: "qrcode.viewfinder")
                    Text(NSLocalizedString("Scan QR", comment: ""))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(10)
            }
        }
        .padding(.horizontal, 20)
    }

    private var continueButton: some View {
        Button(action: {
            let trimmed = viewModel.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch viewModel.network {
            case .core: onContinueCore(trimmed)
            case .platform: onContinuePlatform(trimmed)
            }
        }) {
            Text(NSLocalizedString("Continue", comment: ""))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(viewModel.canContinue ? Color.blue : Color.gray300)
                .cornerRadius(10)
        }
        .disabled(!viewModel.canContinue)
        .padding(.horizontal, 20)
    }

    private func truncate(_ s: String, visible: Int = 8) -> String {
        guard s.count > visible * 2 + 3 else { return s }
        let head = s.prefix(visible)
        let tail = s.suffix(visible)
        return "\(head)…\(tail)"
    }
}
