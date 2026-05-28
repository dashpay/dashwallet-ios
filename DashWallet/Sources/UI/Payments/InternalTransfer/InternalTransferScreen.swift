//
//  InternalTransferScreen.swift
//  DashWallet
//

import SwiftUI

struct InternalTransferScreen: View {
    @ObservedObject var viewModel: InternalTransferViewModel

    var onBack: () -> Void
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 10)

            VStack(spacing: 16) {
                amountRow
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                directionCards
                    .padding(.horizontal, 20)

                if viewModel.canContinue {
                    creditsPreview
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 8)

            Spacer(minLength: 0)

            NumericKeyboardView(
                value: keypadBinding,
                showDecimalSeparator: true,
                actionButtonText: NSLocalizedString("Continue", comment: ""),
                actionEnabled: viewModel.canContinue,
                inProgress: false,
                actionHandler: { onContinue() })
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
            }

            Text(NSLocalizedString("Internal transfer", comment: ""))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Amount row

    private var amountRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: { viewModel.fillMaxFromWallet() }) {
                Text(NSLocalizedString("Max", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondaryBackground)
                    .clipShape(Capsule())
            }

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(viewModel.amountText)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Image("icon_dash_currency")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                }

                Text(viewModel.fiatString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                unitPill(label: "DASH", selected: viewModel.unit == .dash) {
                    viewModel.unit = .dash
                }
                unitPill(label: "FIAT", selected: viewModel.unit == .fiat) {
                    viewModel.unit = .fiat
                }
            }
        }
    }

    private func unitPill(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(selected ? .primaryText : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selected ? Color.secondaryBackground : Color.clear)
                .clipShape(Capsule())
        }
    }

    // MARK: - From / To cards

    private var directionCards: some View {
        ZStack {
            VStack(spacing: 8) {
                fromCard
                toCard
            }

            swapBadge
        }
    }

    private var fromCard: some View {
        directionCard(
            iconSystemName: "d.circle.fill",
            iconColor: .blue,
            caption: NSLocalizedString("From", comment: ""),
            title: NSLocalizedString("Dash Wallet", comment: ""),
            balanceTrailing: AnyView(
                HStack(spacing: 2) {
                    Text(coreDashString(viewModel.coreBalance))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primaryText)
                    Image("icon_dash_currency")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                }))
    }

    private var toCard: some View {
        directionCard(
            iconSystemName: "shield.fill",
            iconColor: .blue,
            caption: NSLocalizedString("To", comment: ""),
            title: NSLocalizedString("Shielded balance", comment: ""),
            balanceTrailing: AnyView(
                Text(viewModel.platformBalanceFormatted)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)))
    }

    private func directionCard(
        iconSystemName: String,
        iconColor: Color,
        caption: String,
        title: String,
        balanceTrailing: AnyView
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: iconSystemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.08))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primaryText)
            }

            Spacer()

            balanceTrailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var swapBadge: some View {
        Image(systemName: "arrow.up.arrow.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.primaryText)
            .frame(width: 28, height: 28)
            .background(Color.primaryBackground)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Credits preview

    private var creditsPreview: some View {
        VStack(spacing: 2) {
            Text(NSLocalizedString("You will transfer", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Text("~ \(viewModel.creditsPreviewFormatted)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text(NSLocalizedString("credits", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var keypadBinding: Binding<String> {
        Binding(
            get: { viewModel.amountText == "0" ? "" : viewModel.amountText },
            set: { newValue in
                if newValue.isEmpty {
                    viewModel.amountText = "0"
                } else {
                    viewModel.amountText = newValue
                }
            })
    }

    private func coreDashString(_ duffs: UInt64) -> String {
        duffs.formattedDashAmountWithoutCurrencySymbol
    }
}
