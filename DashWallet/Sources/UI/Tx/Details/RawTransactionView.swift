//
//  RawTransactionView.swift
//  DashWallet
//

import SwiftUI
import DashUIKit
import UIKit

// MARK: - RawTransactionViewModel

/// Loads and holds the consensus-decoded transaction for the inspector.
@MainActor
final class RawTransactionViewModel: ObservableObject {
    enum State {
        case loading
        case loaded(RawTransactionDetails)
        /// Row missing or bytes unparseable — shown honestly, never guessed.
        case unavailable
    }

    @Published private(set) var state: State = .loading

    private let txidWire: Data

    init(txidWire: Data) {
        self.txidWire = txidWire
    }

    func load() {
        guard case .loading = state else { return }
        if let details = RawTransactionInspector.load(txidWire: txidWire) {
            state = .loaded(details)
        } else {
            state = .unavailable
        }
    }

    func copyToPasteboard(_ value: String) {
        UIPasteboard.general.string = value
    }
}

// MARK: - RawTransactionView

/// Full transaction inspector: every consensus field of the stored raw
/// transaction — version/type, locktime, all inputs (outpoints, scriptSigs,
/// sequences), all outputs (values, addresses, OP_RETURN contents, scripts),
/// the DIP-2 special payload when present, and the raw hex. Every hex blob
/// is tap-to-copy.
struct RawTransactionView: View {
    @StateObject private var viewModel: RawTransactionViewModel
    @State private var copiedFeedback = false

    init(txidWire: Data) {
        _viewModel = StateObject(wrappedValue: RawTransactionViewModel(txidWire: txidWire))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                SwiftUI.ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                unavailableBody
            case .loaded(let details):
                loadedBody(details)
            }
        }
        .background(Color.dash.primaryBackground)
        .onAppear { viewModel.load() }
        .overlay(alignment: .bottom) {
            if copiedFeedback {
                Text(NSLocalizedString("Copied", comment: ""))
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color.dash.whiteText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.dash.black.opacity(0.75)))
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
    }

    private var unavailableBody: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 34))
                .foregroundColor(Color.dash.secondaryText)
            Text(NSLocalizedString("Raw transaction unavailable", comment: "Raw transaction inspector"))
                .font(.subheadline)
                .foregroundColor(.dash.secondaryText)
            Text(NSLocalizedString("This transaction's raw bytes are not stored on this device.", comment: "Raw transaction inspector"))
                .font(.caption)
                .foregroundColor(.dash.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadedBody(_ details: RawTransactionDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overviewCard(details)

                sectionHeader(String(format: NSLocalizedString("Inputs (%d)", comment: "Raw transaction inspector"), details.inputs.count))
                ForEach(details.inputs, id: \.index) { input in
                    inputCard(input)
                }

                sectionHeader(String(format: NSLocalizedString("Outputs (%d)", comment: "Raw transaction inspector"), details.outputs.count))
                ForEach(details.outputs, id: \.index) { output in
                    outputCard(output)
                }

                if let payload = details.extraPayload {
                    sectionHeader(NSLocalizedString("Special payload", comment: "Raw transaction inspector"))
                    payloadCard(details: details, payload: payload)
                }

                sectionHeader(NSLocalizedString("Raw transaction", comment: "Raw transaction inspector"))
                hexCard(details.rawHex)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Cards

    private func overviewCard(_ details: RawTransactionDetails) -> some View {
        card {
            copyableRow(label: NSLocalizedString("Transaction ID", comment: "Raw transaction inspector"), value: details.txidDisplayHex, monospaced: true)
            divider
            plainRow(label: NSLocalizedString("Version", comment: "Raw transaction inspector"), value: "\(details.version)")
            if let typeName = details.typeName {
                divider
                plainRow(label: NSLocalizedString("Type", comment: "Raw transaction inspector"), value: "\(typeName) (\(details.typeRaw))")
            }
            divider
            plainRow(label: NSLocalizedString("Size", comment: "Raw transaction inspector"),
                     value: String(format: NSLocalizedString("%d bytes", comment: "Raw transaction inspector"), details.sizeBytes))
            divider
            plainRow(label: NSLocalizedString("Locktime", comment: "Raw transaction inspector"), value: "\(details.lockTime)")
            if let height = details.blockHeight {
                divider
                plainRow(label: NSLocalizedString("Block height", comment: "Raw transaction inspector"), value: "\(height)")
            }
            if let fee = details.feeDuffs {
                divider
                plainRow(label: NSLocalizedString("Network fee", comment: ""), value: fee.formattedDashAmountWithoutCurrencySymbol)
            }
        }
    }

    private func inputCard(_ input: RawTransactionDetails.Input) -> some View {
        card {
            if input.isCoinbase {
                plainRow(label: String(format: NSLocalizedString("Input %d", comment: "Raw transaction inspector"), input.index),
                         value: NSLocalizedString("Coinbase (new coins)", comment: "Raw transaction inspector"))
            } else {
                copyableRow(
                    label: String(format: NSLocalizedString("Input %d — outpoint", comment: "Raw transaction inspector"), input.index),
                    value: "\(input.prevTxidDisplayHex):\(input.prevVout)",
                    monospaced: true)
            }
            if let address = input.address {
                divider
                copyableRow(label: NSLocalizedString("Address", comment: ""), value: address, monospaced: true)
            }
            if let amount = input.amountDuffs {
                divider
                plainRow(label: NSLocalizedString("Amount", comment: ""), value: amount.formattedDashAmountWithoutCurrencySymbol)
            }
            divider
            plainRow(label: NSLocalizedString("Sequence", comment: "Raw transaction inspector"),
                     value: String(format: "0x%08x", input.sequence))
            if !input.scriptSig.isEmpty {
                divider
                copyableRow(label: NSLocalizedString("Script signature", comment: "Raw transaction inspector"),
                            value: input.scriptSig.map { String(format: "%02x", $0) }.joined(),
                            monospaced: true)
            }
        }
    }

    private func outputCard(_ output: RawTransactionDetails.Output) -> some View {
        card {
            plainRow(label: String(format: NSLocalizedString("Output %d", comment: "Raw transaction inspector"), output.index),
                     value: output.valueDuffs.formattedDashAmountWithoutCurrencySymbol)
            switch output.kind {
            case .standard(let address):
                divider
                copyableRow(label: NSLocalizedString("Address", comment: ""), value: address, monospaced: true)
            case .opReturn(let data):
                divider
                copyableRow(label: "OP_RETURN",
                            value: data.map { String(format: "%02x", $0) }.joined(),
                            monospaced: true)
                if let text = Self.printableASCII(data) {
                    divider
                    plainRow(label: NSLocalizedString("As text", comment: "Raw transaction inspector"), value: text)
                }
            case .nonStandard:
                divider
                plainRow(label: NSLocalizedString("Script type", comment: "Raw transaction inspector"),
                         value: NSLocalizedString("Non-standard", comment: "Raw transaction inspector"))
            }
            divider
            copyableRow(label: NSLocalizedString("Script", comment: "Raw transaction inspector"),
                        value: output.scriptPubKey.map { String(format: "%02x", $0) }.joined(),
                        monospaced: true)
        }
    }

    private func payloadCard(details: RawTransactionDetails, payload: Data) -> some View {
        card {
            if let typeName = details.typeName {
                plainRow(label: NSLocalizedString("Type", comment: "Raw transaction inspector"), value: typeName)
                divider
            }
            plainRow(label: NSLocalizedString("Size", comment: "Raw transaction inspector"),
                     value: String(format: NSLocalizedString("%d bytes", comment: "Raw transaction inspector"), payload.count))
            ForEach(Array(details.payloadFields.enumerated()), id: \.offset) { _, field in
                divider
                plainRow(label: field.label, value: field.value)
            }
            divider
            copyableRow(label: NSLocalizedString("Payload hex", comment: "Raw transaction inspector"),
                        value: payload.map { String(format: "%02x", $0) }.joined(),
                        monospaced: true)
        }
    }

    private func hexCard(_ hex: String) -> some View {
        card {
            Button(action: { copy(hex) }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("Tap to copy", comment: ""))
                            .font(.caption)
                            .foregroundColor(.dash.secondaryText)
                        Spacer()
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(.dash.blue)
                    }
                    Text(hex)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.dash.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Row pieces

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.dash.gray300.opacity(0.3))
            .frame(height: 1)
    }

    private func plainRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
            Text(value)
                .font(.footnote)
                .foregroundColor(.dash.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyableRow(label: String, value: String, monospaced: Bool) -> some View {
        Button(action: { copy(value) }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.dash.secondaryText)
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.dash.blue)
                }
                Text(value)
                    .font(monospaced ? .system(size: 12, design: .monospaced) : .footnote)
                    .foregroundColor(.dash.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundColor(.dash.secondaryText)
            .padding(.top, 4)
    }

    // MARK: - Actions

    private func copy(_ value: String) {
        viewModel.copyToPasteboard(value)
        withAnimation { copiedFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copiedFeedback = false }
        }
    }

    /// The data rendered as ASCII when every byte is printable — shown for
    /// OP_RETURN payloads that are actually text. Nil otherwise (no lossy
    /// best-effort rendering of binary data).
    static func printableASCII(_ data: Data) -> String? {
        guard !data.isEmpty, data.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { return nil }
        return String(bytes: data, encoding: .ascii)
    }
}
