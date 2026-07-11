//
//  WalletSwitchDialog.swift
//  DashWallet
//
//  Bottom-sheet picker for the Switch Wallet shortcut, shown when the device
//  has two to five OTHER wallets. Rows render the wallet name plus username /
//  balance when known. Selection only reports back to UIKit
//  (`HomeViewController.showSwitchWallet`), which shows the always-required
//  confirmation alert — the sheet never switches by itself.
//

import SwiftUI

struct WalletSwitchDialog: View {
    let rows: [WalletRow]
    var onSelect: (WalletRow) -> Void

    /// Sheet detent height for `rowCount` rows, matching the BottomSheet's
    /// title + row + padding metrics (same scheme as TransactionFilterDialog).
    static func height(rowCount: Int) -> CGFloat {
        CGFloat(134 + rowCount * 60)
    }

    var body: some View {
        BottomSheet(
            title: NSLocalizedString("Switch Wallet", comment: "Wallets"),
            showBackButton: .constant(false)
        ) {
            VStack(spacing: 4) {
                ForEach(rows) { row in
                    Button(action: { onSelect(row) }) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.displayName)
                                    .font(.subhead)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primaryText)
                                    .lineLimit(1)
                                if let username = row.username {
                                    Text("@\(username)")
                                        .font(.caption)
                                        .foregroundColor(.dashBlue)
                                        .lineLimit(1)
                                }
                                if let balance = row.balanceText {
                                    Text(balance)
                                        .font(.caption)
                                        .foregroundColor(.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondaryText)
                        }
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                        .frame(minHeight: 60)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 6)
            .background(Color.secondaryBackground)
            .clipShape(RoundedShape(corners: .allCorners, radii: 12))
            .padding(.horizontal, 20)
            .padding(.top, 25)
        }
        .background(Color.primaryBackground)
    }
}
