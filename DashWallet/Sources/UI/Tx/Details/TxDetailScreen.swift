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

// MARK: - TxDetailScreen

/// The transaction details: header, the info card (addresses, contact, fee,
/// date), tax category, recovery actions, the raw transaction and the block
/// explorers.
struct TxDetailScreen: View {
    enum Chrome {
        /// Embedded in another screen or sheet.
        case none
        /// The root of a modal stack: a close circle at the top.
        case closeButton
        /// The success screen after a payment: a Close button at the bottom.
        case bottomCloseButton
    }

    @ObservedObject var viewModel: TxDetailViewModel
    let chrome: Chrome
    let onClose: () -> Void
    /// The contact a host already shows, and how to go back to it: that
    /// contact's row goes back instead of stacking a second profile on top.
    let contactReturn: TXDetailViewController.ContactReturn?
    let openURL: (URL) -> Void

    @State private var showsExplorerPicker = false
    @State private var showsRawTransaction = false
    @State private var profileContact: ContactItem?
    @State private var copiedMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if chrome == .closeButton {
                DashUIKit.NavigationBar(leading: { EmptyView() }, trailing: {
                    DashUIKit.NavigationBarElement.close.button(action: onClose)
                })
            }

            ScrollView {
                LazyVStack(spacing: 15) {
                    ForEach(viewModel.sections, id: \.section) { content in
                        if content.section == .header {
                            TxDetailHeader(model: viewModel.model)
                                .id(viewModel.revision)
                        } else {
                            card(content.rows, separated: content.section != .info)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, chrome == .closeButton ? 0 : 8)
                .padding(.bottom, 20)
            }

            if chrome == .bottomCloseButton {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Close", comment: ""),
                    fillsWidth: true, size: .large, style: .filledBlue, action: onClose)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)
            }
        }
        .background(Color(uiColor: .dw_secondaryBackground()).ignoresSafeArea())
        .overlay { progressOverlay }
        .overlay(alignment: .bottom) { toastOverlay }
        .onAppear { viewModel.start() }
        .alert(
            viewModel.alert?.title ?? "",
            isPresented: Binding(get: { viewModel.alert != nil }, set: { if !$0 { viewModel.alert = nil } }),
            presenting: viewModel.alert
        ) { alert in
            if let confirmTitle = alert.confirmTitle {
                Button(confirmTitle, role: .destructive) { alert.onConfirm?() }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            } else {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) { alert.onDismiss?() }
            }
        } message: { alert in
            Text(alert.message)
        }
        .sheet(isPresented: $showsExplorerPicker) {
            DashUIKit.BottomSheet(
                title: NSLocalizedString("Select block explorer", comment: "Block explorer picker"),
                showBackButton: .constant(false)
            ) {
                BlockExplorerSelectionView { explorer in
                    showsExplorerPicker = false
                    if let url = viewModel.model.getExplorerURL(explorer: explorer) {
                        // After the picker has gone: nothing presents over a
                        // sheet that is still dismissing.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { openURL(url) }
                    }
                }
            }
            .presentationDetents([.height(240)])
        }
        .sheet(isPresented: $showsRawTransaction) {
            DashUIKit.BottomSheet(
                title: NSLocalizedString("Transaction", comment: "Raw transaction inspector"),
                showBackButton: .constant(false)
            ) {
                RawTransactionView(txidWire: viewModel.model.transaction.txHashData)
            }
        }
        .sheet(item: $profileContact) { contact in
            ContactProfileSheet(contact: contact)
        }
    }

    // MARK: Cards

    /// A card of rows; actions are separated by a line, the info rows are not.
    private func card(_ rows: [TxDetailViewModel.Row], separated: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                if separated, index > 0 {
                    Rectangle()
                        .fill(Color(uiColor: .dw_separatorLine()))
                        .frame(height: 1 / UIScreen.main.scale)
                        .padding(.horizontal, 15)
                }
                rowView(row)
            }
        }
        .background(Color(uiColor: .dw_background()))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func rowView(_ row: TxDetailViewModel.Row) -> some View {
        switch row {
        case .values(let title, let values):
            TxDetailValuesRow(title: title, values: values)
        case .contact(let title, let party):
            Button { openContact(party) } label: {
                TxDetailContactRow(title: title, contact: party)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .taxCategory(let title, let category):
            Button(action: viewModel.toggleTaxCategory) {
                HStack(spacing: 13) {
                    rowTitle(title)
                    Spacer(minLength: 8)
                    Text(category)
                        .font(Font(UIFont.dw_font(forTextStyle: .footnote)))
                        .foregroundColor(Color(uiColor: .dw_label()))
                    Image(systemName: "repeat")
                        .scaledSystemFont(size: 12, weight: .semibold, relativeTo: .footnote)
                        .foregroundColor(.dash.blue)
                        .frame(width: 14, height: 24)
                        .accessibilityHidden(true)
                }
                .padding(.leading, 15)
                .padding(.trailing, 20)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(NSLocalizedString("Change", comment: "")))
        case .retry(let title):
            actionRow(title, action: viewModel.retryStuckAssetLock)
        case .removeUnconfirmed:
            actionRow(NSLocalizedString("Remove if Not on Network", comment: "Delete a never-accepted transaction from local wallet state"),
                      color: .systemRed, action: viewModel.confirmRemoveUnconfirmed)
        case .viewTransaction:
            actionRow(NSLocalizedString("View Transaction", comment: "Raw transaction inspector")) { showsRawTransaction = true }
        case .copyRawTransaction:
            actionRow(NSLocalizedString("Copy Raw Transaction", comment: "Raw transaction inspector"), action: copyRawTransaction)
        case .explorer:
            actionRow(NSLocalizedString("View in Block Explorer", comment: "")) { showsExplorerPicker = true }
        case .swapExplorer(let title):
            actionRow(title) {
                if let link = viewModel.model.swapExplorerLink { openURL(link.url) }
            }
        }
    }

    private func rowTitle(_ title: String) -> some View {
        Text(title)
            .font(Font(UIFont.dw_font(forTextStyle: .footnote)).weight(.medium))
            .foregroundColor(Color(uiColor: .dw_secondaryText()))
    }

    private func actionRow(_ title: String, color: UIColor = .dw_label(), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Font(UIFont.dw_font(forTextStyle: .footnote)).weight(.medium))
                    .foregroundColor(Color(uiColor: color))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .scaledSystemFont(size: 13, weight: .semibold, relativeTo: .footnote)
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Overlays

    @ViewBuilder
    private var progressOverlay: some View {
        if let message = viewModel.progressMessage {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 12) {
                    SwiftUI.ProgressView()
                    Text(message)
                        .dashFont(.subhead)
                        .foregroundStyle(Color.dash.primaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .background(Color.dash.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(40)
            }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = viewModel.toast {
            DashUIKit.Toast(style: toast.style, message: toast.message)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .transition(.opacity)
                .task(id: toast.id) {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    if viewModel.toast == toast {
                        withAnimation { viewModel.toast = nil }
                    }
                }
        } else if let copiedMessage {
            DashUIKit.Toast(style: .success, message: copiedMessage)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .transition(.opacity)
                .task(id: copiedMessage) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { self.copiedMessage = nil }
                }
        }
    }

    // MARK: Actions

    /// Copies the serialized transaction hex. A transaction whose bytes are
    /// not stored on this device says so rather than copying nothing.
    private func copyRawTransaction() {
        if let hex = viewModel.rawTransactionHex() {
            UIPasteboard.general.string = hex
            withAnimation { copiedMessage = NSLocalizedString("Copied", comment: "") }
        } else {
            withAnimation { copiedMessage = NSLocalizedString("Raw transaction unavailable", comment: "Raw transaction inspector") }
        }
    }

    /// Opens the counterparty's contact profile, resolved from the contacts
    /// service's live snapshot. A payment whose contact is no longer there says
    /// so rather than silently doing nothing.
    private func openContact(_ party: TxDetailModel.ContactParty) {
        if let contactReturn, contactReturn.identityId == party.identityId {
            contactReturn.goBack()
            return
        }
        guard let contact = SwiftDashSDKContactsService.shared.contactItem(for: party.identityId) else {
            withAnimation { copiedMessage = NSLocalizedString("Contact is no longer available", comment: "DashPay Contacts") }
            return
        }
        profileContact = contact
    }
}

// MARK: - Header

private struct TxDetailHeader: View {
    let model: TxDetailModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(Font(UIFont.dw_font(forTextStyle: .subheadline)).weight(.medium))
                    .foregroundColor(Color(uiColor: .dw_label()))

                AttributedLabel(
                    text: model.dashAmountString(
                        with: UIFont.preferredFont(forTextStyle: .largeTitle).withWeight(UIFont.Weight.medium.rawValue)))

                Text(model.fiatAmount)
                    .font(Font(UIFont.dw_font(forTextStyle: .footnote)))
                    .foregroundColor(Color(uiColor: .dw_secondaryText()))
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Group {
                if let contact = model.contactParty {
                    TxDetailContactAvatar(contact: contact, directionIcon: model.icon)
                        .frame(width: 62, height: 62)
                } else {
                    Image(uiImage: model.icon)
                        .renderingMode(model.icon.renderingMode == .alwaysTemplate ? .template : .original)
                        .foregroundColor(Color(uiColor: model.tintColor))
                        .frame(width: 50, height: 50)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }
}

// MARK: - Values row

/// A titled row with one or more right-aligned values (addresses truncate in
/// the middle).
private struct TxDetailValuesRow: View {
    let title: String
    let values: [TxDetailViewModel.Value]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 15) {
            Text(title)
                .font(Font(UIFont.dw_font(forTextStyle: .footnote)).weight(.medium))
                .foregroundColor(Color(uiColor: .dw_secondaryText()))
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    switch value {
                    case .plain(let text):
                        Text(text)
                            .font(Font(UIFont.dw_font(forTextStyle: .footnote)))
                            .foregroundColor(Color(uiColor: .dw_label()))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    case .attributed(let text):
                        // Keeps its own font (caption1, the size the Dash
                        // symbol is drawn for), as the table cell did.
                        AttributedLabel(text: text, alignment: .right)
                    }
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// A `UILabel` for attributed text with image attachments (the Dash
/// symbol), which SwiftUI's `Text` does not draw.
private struct AttributedLabel: UIViewRepresentable {
    let text: NSAttributedString
    var alignment: NSTextAlignment = .natural
    var font: UIFont?

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.lineBreakMode = .byTruncatingMiddle
        label.adjustsFontForContentSizeCategory = true
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = text
        if let font { label.font = font }
        label.textAlignment = alignment
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let fitting = uiView.sizeThatFits(CGSize(width: proposal.width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        return CGSize(width: min(fitting.width, proposal.width ?? fitting.width), height: fitting.height)
    }
}
