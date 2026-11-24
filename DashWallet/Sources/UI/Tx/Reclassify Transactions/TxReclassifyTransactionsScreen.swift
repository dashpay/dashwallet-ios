//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import DashUIKit
import SwiftUI
import UIKit

// MARK: - TxReclassifyTransactionsInfoViewControllerDelegate

protocol TxReclassifyTransactionsInfoViewControllerDelegate: AnyObject {
    func txReclassifyTransactionsFlowDidClose(controller: TxReclassifyTransactionsInfoViewController,
                                              transaction: Transaction)
}

// MARK: - TxReclassifyTransactionsInfoViewController

/// The one-time "Reclassify Your Transactions" sheet, shown on Home after the
/// first new transaction. "I Understand" closes it and opens that
/// transaction's details.
final class TxReclassifyTransactionsInfoViewController: UIHostingController<TxReclassifyTransactionsInfoScreen> {
    let transaction: Transaction
    weak var delegate: TxReclassifyTransactionsInfoViewControllerDelegate?

    init(transaction: Transaction) {
        self.transaction = transaction
        super.init(rootView: TxReclassifyTransactionsInfoScreen(transaction: transaction, onClose: {}, onUnderstand: {}))
        rootView = TxReclassifyTransactionsInfoScreen(
            transaction: transaction,
            onClose: { [weak self] in self?.dismiss(animated: true) },
            onUnderstand: { [weak self] in self?.understand() })
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func understand() {
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.txReclassifyTransactionsFlowDidClose(controller: self, transaction: self.transaction)
        }
    }
}

// MARK: - TxReclassifyTransactionsInfoScreen

struct TxReclassifyTransactionsInfoScreen: View {
    let transaction: Transaction
    let onClose: () -> Void
    let onUnderstand: () -> Void

    @State private var showsWhereToChange = false

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(leading: { EmptyView() }, trailing: {
                DashUIKit.NavigationBarElement.close.button(action: onClose)
            })

            ScrollView {
                VStack(spacing: 0) {
                    Image("tx.reclassify.icon")
                        .accessibilityHidden(true)
                        .padding(.bottom, 20)

                    Text(NSLocalizedString("Reclassify Your Transactions", comment: "Reclassify transactions info screen"))
                        .font(Font(UIFont.dw_font(forTextStyle: .title1)).weight(.bold))
                        .foregroundColor(Color(uiColor: .dw_label()))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text(NSLocalizedString("These classifications will be reflected on the CSV export that can be used for import into tax reporting services.",
                                           comment: "Reclassify transactions info screen"))
                        .font(Font(UIFont.dw_font(forTextStyle: .subheadline)))
                        .foregroundColor(Color(uiColor: .dw_label()))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    Button {
                        showsWhereToChange = true
                    } label: {
                        Text(NSLocalizedString("Where can I change the transaction type?", comment: "Reclassify transactions info screen"))
                            .font(Font(UIFont.dw_font(forTextStyle: .footnote)).weight(.semibold))
                            .foregroundColor(.dash.blue)
                            .multilineTextAlignment(.center)
                            .frame(minHeight: 44)
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 28) {
                        ReclassifyRuleRow(
                            symbol: "arrow.up.circle", tint: .dash.blue,
                            title: NSLocalizedString("Outgoing transactions", comment: "Reclassify transactions info screen"),
                            defaultCategory: .expense, alternative: .transferOut)
                        ReclassifyRuleRow(
                            symbol: "arrow.down.circle", tint: .dash.green,
                            title: NSLocalizedString("Incoming transactions", comment: "Reclassify transactions info screen"),
                            defaultCategory: .income, alternative: .transferIn)
                        ReclassifyRuleRow(
                            symbol: "arrow.left.arrow.right.circle", tint: Color(uiColor: .systemGray),
                            title: NSLocalizedString("Linked accounts", comment: "Reclassify transactions info screen"),
                            note: NSLocalizedString("by default all transactions to or from your linked accounts (exchanges, staking, etc) will be marked as a transfer.",
                                                    comment: "Reclassify transactions info screen"))
                    }
                    .padding(.top, 28)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            DashUIKit.DashButton(
                text: NSLocalizedString("I Understand", comment: "Reclassify transactions info screen"),
                fillsWidth: true, size: .large, style: .filledBlue, action: onUnderstand)
                .padding(.horizontal, 15)
                .padding(.vertical, 15)
        }
        .background(Color(uiColor: .dw_secondaryBackground()).ignoresSafeArea())
        .sheet(isPresented: $showsWhereToChange) {
            TxReclassifyWhereToChangeScreen(transaction: transaction, onClose: { showsWhereToChange = false })
        }
    }
}

// MARK: - Rule row

/// One rule: an icon, a title, and either the default category with the one
/// it can change to, or a sentence.
private struct ReclassifyRuleRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var defaultCategory: TxMetadataTaxCategory? = nil
    var alternative: TxMetadataTaxCategory? = nil
    var note: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(systemName: symbol)
                .scaledSystemFont(size: 30, weight: .regular, relativeTo: .title)
                .foregroundColor(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Font(UIFont.dw_font(forTextStyle: .subheadline)).weight(.semibold))
                    .foregroundColor(Color(uiColor: .dw_label()))
                    .padding(.top, 4)

                if let defaultCategory {
                    sentence(NSLocalizedString("by default will be marked as",
                                               comment: "Reclassify info: sentence start; a tag with the default category follows it"),
                             tag: defaultCategory.stringValue, tagColor: tint, tagBackground: tint.opacity(0.12))
                }
                if let alternative {
                    sentence(NSLocalizedString("You can change it to",
                                               comment: "Reclassify info: sentence start; a tag with the category to pick follows it"),
                             tag: alternative.stringValue,
                             tagColor: Color(uiColor: .dw_label()), tagBackground: Color.primary.opacity(0.08))
                }
                if let note {
                    Text(note)
                        .font(Font(UIFont.dw_font(forTextStyle: .footnote)))
                        .foregroundColor(Color(uiColor: .dw_secondaryText()))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A sentence start followed by a category tag; the tag wraps below when
    /// they don't fit on one line.
    private func sentence(_ text: String, tag: String, tagColor: Color, tagBackground: Color) -> some View {
        let start = Text(text)
            .font(Font(UIFont.dw_font(forTextStyle: .footnote)))
            .foregroundColor(Color(uiColor: .dw_secondaryText()))
        let chip = Text(tag)
            .font(Font(UIFont.dw_font(forTextStyle: .footnote)))
            .foregroundColor(tagColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tagBackground, in: RoundedRectangle(cornerRadius: 6))
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { start; chip }
            VStack(alignment: .leading, spacing: 4) { start; chip }
        }
    }
}

// MARK: - TxReclassifyWhereToChangeScreen

/// Points at the Tax Category row on the transaction's own details, shown
/// live (and so in the current theme), scaled down.
struct TxReclassifyWhereToChangeScreen: View {
    let onClose: () -> Void
    @StateObject private var preview: TxDetailViewModel

    init(transaction: Transaction, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _preview = StateObject(wrappedValue: TxDetailViewModel(model: TxDetailModel(transaction: transaction)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashUIKit.NavigationBar(leading: { EmptyView() }, trailing: {
                DashUIKit.NavigationBarElement.close.button(action: onClose)
            })

            Text(NSLocalizedString("Where can I change the tax category?", comment: "Reclassify transactions: where to change the tax category screen"))
                .font(Font(UIFont.dw_font(forTextStyle: .title2)).weight(.bold))
                .foregroundColor(Color(uiColor: .dw_label()))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)

            Text(NSLocalizedString("These classifications will be reflected on the CSV export that can be used for import into tax reporting services.",
                                   comment: "Reclassify transactions: where to change the tax category screen"))
                .font(Font(UIFont.dw_font(forTextStyle: .subheadline)))
                .foregroundColor(Color(uiColor: .dw_secondaryText()))
                .padding(.horizontal, 20)
                .padding(.top, 8)

            GeometryReader { geometry in
                let width = geometry.size.width - 80
                let height = geometry.size.height - 40
                // Laid out at the full sheet width, as the screen itself is,
                // then scaled down to fit, so nothing truncates.
                let scale = width / (geometry.size.width + 40)
                TxDetailScreen(viewModel: preview, chrome: .none, onClose: {}, contactReturn: nil, openURL: { _ in })
                    .frame(width: width / scale, height: height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: width, height: height, alignment: .topLeading)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                    .padding(.top, 40)
                    .padding(.horizontal, 40)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 30))
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .padding(20)
        }
        .background(Color(uiColor: .dw_secondaryBackground()).ignoresSafeArea())
    }
}
