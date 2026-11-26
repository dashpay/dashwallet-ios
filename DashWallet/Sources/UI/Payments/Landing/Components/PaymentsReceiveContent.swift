//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import SwiftUI
import DashUIKit

/// The Receive tab: the balance toggle, the QR for its address, and the two
/// actions on that address.
///
/// Takes the view model rather than a resolved address, because the toggle
/// writes back to it and the placeholder wording depends on which balance is
/// selected — passing the parts separately would just rebuild the same object.
struct PaymentsReceiveContent: View {
    @ObservedObject var viewModel: PaymentsLandingViewModel

    var onCopyAddress: () -> Void
    var onShareAddress: () -> Void
    var onSpecifyAmount: () -> Void
    /// Copies the Identity option's username; the host shows the toast.
    var onCopyUsername: () -> Void = {}
    /// Opens the transaction behind a receipt. Passed through rather than
    /// acted on — which controller presents the details is the host's.
    var onViewTransaction: (Data) -> Void = { _ in }
    /// Closes the whole receive surface from the receipt's Done button.
    var onDone: () -> Void = {}
    /// `nil` renders the row dimmed and untappable. There is no import flow to
    /// route to yet — `ShortcutAction.importPrivateKey` is still a `break` in
    /// `HomeViewController+Shortcuts` — and a row that silently does nothing
    /// reads as a broken button.
    var onImportPrivateKey: (() -> Void)? = nil

    /// Which way the last network change moved along `receiveOptions`, so the
    /// incoming card slides in from the side it came from — the same rule the
    /// tab selector above follows.
    @State private var slidesForward = true

    private enum Layout {
        /// Matches `SegmentedControlLayout`'s own spring, so the pill and the
        /// card it selects travel together.
        static let slideResponse: Double = 0.3
        static let slideDamping: Double = 0.7
    }

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            if let receipt = viewModel.receipt {
                // A payment landed while this screen was being presented. The
                // receipt takes the whole surface: the address it was paid to
                // is spent attention now, and the next thing the user does is
                // finish or receive another.
                ReceiveReceiptCard(
                    receipt: receipt,
                    canViewTransaction: viewModel.canViewTransaction,
                    onViewTransaction: onViewTransaction,
                    onReceiveAnother: viewModel.receiveAnother,
                    onDone: onDone)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            } else {
                addressContent
            }
        }
    }

    // MARK: - Network selection

    /// Which address the card shows, as a row of buttons rather than a
    /// `SegmentedControl` — the design puts this inside the card, where the
    /// pill control's own background would be a second surface on top of the
    /// card's.
    ///
    /// When every title fits whole, the options divide the row evenly; when
    /// not (four options at 375 pt, or a large text size), the row scrolls
    /// sideways and titles are never truncated. Every selection change — the
    /// user's or one the model makes, such as falling back to Core — scrolls
    /// the selected option fully into view. The selected one carries the tint
    /// and the others are plain, because identical buttons would leave the
    /// screen unable to say which option is on it.
    private var networkRow: some View {
        ViewThatFits(in: .horizontal) {
            EvenOptionRow {
                optionButtons(fillsWidth: true)
            }
            .padding(.horizontal, 20)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        optionButtons(fillsWidth: false)
                    }
                    .padding(.horizontal, 20)
                }
                .onAppear { proxy.scrollTo(viewModel.network) }
                .onChange(of: viewModel.network) { _, selected in
                    withAnimation { proxy.scrollTo(selected) }
                }
            }
        }
        .padding(.vertical, 20)
    }

    private func optionButtons(fillsWidth: Bool) -> some View {
        ForEach(viewModel.receiveOptions) { option in
            DashUIKit.DashButton(
                text: option.title,
                fillsWidth: fillsWidth,
                size: .medium,
                style: option == viewModel.network ? .tintedGray : .plainBlack,
                action: { select(option) }
            )
            .id(option)
        }
    }

    /// Everything that changes the network goes through here so the direction
    /// of travel is known before the change lands — the card has to enter from
    /// whichever side the new segment sits on, and only this knows which.
    private var networkSelection: Binding<ReceiveOption> {
        Binding(
            get: { viewModel.network },
            set: { select($0) })
    }

    private func select(_ network: ReceiveOption) {
        let options = viewModel.receiveOptions
        guard let from = options.firstIndex(of: viewModel.network),
              let to = options.firstIndex(of: network),
              from != to
        else { return }

        slidesForward = to > from
        withAnimation(.spring(response: Layout.slideResponse,
                              dampingFraction: Layout.slideDamping)) {
            viewModel.network = network
        }
    }

    /// Matches the direction of travel: moving right, the new card enters from
    /// the right and the old one leaves to the left.
    private var slide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: slidesForward ? .trailing : .leading),
            removal: .move(edge: slidesForward ? .leading : .trailing))
    }

    /// The QR, the address and the actions — everything the screen shows while
    /// it is still waiting to be paid.
    private var addressContent: some View {
        VStack(alignment: .center, spacing: 20) {
            VStack(spacing: 0) {
                // Inside the card, and outside the animated block below it:
                // the control that causes the change must not travel with what
                // it changes.
                networkRow

                // The card itself holds still — only what is inside it travels.
                // ZStack so the outgoing and incoming contents share one slot
                // instead of stacking; keyed on the network so a change reads
                // as a replacement to animate rather than an in-place edit of
                // the QR and the address.
                ZStack(alignment: .top) {
                    cardBody
                        .id(viewModel.network)
                        .transition(slide)
                }
                // Keeps the travelling contents inside the card's edges. Square
                // rather than the card's 20pt radius: nothing is drawn near the
                // corners, so the rounding would cost a mask for no visible
                // difference.
                .clipped()
            }
            .modifier(MenuViewModifier(innerPadding: 0))

            // import private key - if needed

            if onImportPrivateKey != nil {
                Button {
                    onImportPrivateKey?()
                } label: {
                    DashUIKit.MenuItem(
                        leadingIcon: .custom(DashIcon.Menu.importPrivateKey.rawValue, bundle: .dashUIKit),
                        title: NSLocalizedString("Import private key", comment: "Payments"),
                        accessory: .none
                    )
                    .modifier(MenuViewModifier())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// What the card shows for the selected option.
    @ViewBuilder
    private var cardBody: some View {
        if viewModel.network == .identity {
            identityCardBody
        } else {
            addressCardBody
        }
    }

    /// The selected chain option: the QR, the address and the actions on it.
    private var addressCardBody: some View {
        VStack(alignment: .leading, spacing: 0) {

                VStack(alignment: .center, spacing: 20) {
                    qrCard

                    // 12, not 40: the address needs every point it can get to
                    // stay on one line, and the gap was spending them on
                    // nothing. `maxWidth: .infinity` on the text column is what
                    // keeps the copy button on the trailing edge now that the
                    // gap no longer pushes it there.
                    HStack(spacing: 12) {
                        if let address = viewModel.currentAddress {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Your DASH address", comment: "Payments"))
                                    .dashFont(.footnote)
                                    .foregroundStyle(Color.dash.secondaryText)

                                // One line, and cut in the middle when it does
                                // not fit. A Dash address is a single token the
                                // user reads across to check; broken over two
                                // lines it reads as two. Cutting the tail hides
                                // the half people actually check — the last
                                // characters are what gets compared against the
                                // sender's screen — so both ends stay.
                                Text(address)
                                    .dashFont(.subhead)
                                    .foregroundColor(.dash.primaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // The address is the thing the user is reaching
                            // for; the button beside it is the affordance, not
                            // the only target. Tapping the text copies too.
                            .contentShape(Rectangle())
                            .onTapGesture { onCopyAddress() }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(Text(NSLocalizedString("Copy", comment: "")))
                        } else {
                            // Same full-width, leading slot the address takes,
                            // so the copy button stays on the trailing edge
                            // instead of the pair centring in the row.
                            Text(NSLocalizedString("No address available", comment: "Payments"))
                                .font(.footnote)
                                .foregroundColor(Color.dash.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }


                        DashUIKit.DashButton(
                            leadingIcon: .custom(DashIcon.Icons.copyOutline.rawValue, bundle: .dashUIKit),
                            isEnabled: hasAddress,
                            size: .medium,
                            style: .tintedGray,
                            action: onCopyAddress
                        )
                    }
                    .padding(.vertical, 6)
                }
                // Stretches the QR/address block across the card. Without it
                // the block sizes to its content and the leading-aligned card
                // pins it left, which is what happened when the row's spacing
                // stopped being wide enough to fill the width on its own.
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 10)

                // `isEnabled:` rather than `.disabled(…)`: DashButton derives
                // its own colours from that property and applies `.disabled`
                // internally, so an outside modifier blocks the tap but leaves
                // the button looking live.
                HStack(spacing: 20) {
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Share address", comment: "Payments"),
                        isEnabled: hasAddress,
                        size: .medium,
                        style: .tintedGray,
                        action: onShareAddress
                    )

                    DashUIKit.DashButton(
                        text: NSLocalizedString("Specify amount", comment: "Payments"),
                        isEnabled: viewModel.canSpecifyAmount,
                        size: .medium,
                        style: .tintedGray,
                        action: onSpecifyAmount
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                watchingForPayment
                    .padding(.top, 14)
                    .padding(.bottom, 20)
        }
    }

    /// The Identity option: the QR of the bare Identity ID, the username and
    /// the ID with their copy buttons, Share ID, Specify amount, and why most
    /// senders cannot pay here (AC-01 – AC-04).
    private var identityCardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .center, spacing: 20) {
                qrCard

                VStack(spacing: 12) {
                    copyRow(
                        label: NSLocalizedString("Username", comment: ""),
                        value: viewModel.receiveIdentity?.username,
                        copyLabel: NSLocalizedString("Copy username", comment: "Receive, Identity option"),
                        action: onCopyUsername)

                    // One line, cut in the middle like an address: both ends
                    // are what a person compares.
                    copyRow(
                        label: NSLocalizedString("Identity ID", comment: ""),
                        value: viewModel.receiveIdentity?.identityIdBase58,
                        copyLabel: NSLocalizedString("Copy Identity ID", comment: "Receive, Identity option"),
                        action: onCopyAddress)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 40)
            .padding(.bottom, 10)

            HStack(spacing: 20) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Share ID", comment: "Receive, Identity option"),
                    isEnabled: hasAddress,
                    size: .medium,
                    style: .tintedGray,
                    action: onShareAddress
                )

                DashUIKit.DashButton(
                    text: NSLocalizedString("Specify amount", comment: "Payments"),
                    isEnabled: viewModel.canSpecifyAmount,
                    size: .medium,
                    style: .tintedGray,
                    action: onSpecifyAmount
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            DashUIKit.SystemMessageView(
                title: NSLocalizedString(
                    "Most exchanges and many wallets can send only to Core addresses",
                    comment: "Receive, Identity option warning"),
                subtitle: NSLocalizedString(
                    "Funds sent to your identity pay for Dash apps and usernames.",
                    comment: "Receive, Identity option warning"),
                icon: DashIcon.SystemMessage.warningTriangle.source,
                backgroundColor: Color.dash.yellowAlpha10
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)

            watchingForPayment
                .padding(.top, 14)
                .padding(.bottom, 20)
        }
    }

    /// A labelled value on one line, cut in the middle when it does not fit,
    /// with a copy button. Tapping the text copies too, as on the address row.
    private func copyRow(label: String, value: String?, copyLabel: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
                Text(value ?? "")
                    .dashFont(.subhead)
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text(NSLocalizedString("Copy", comment: "")))

            DashUIKit.DashButton(
                leadingIcon: .custom(DashIcon.Icons.copyOutline.rawValue, bundle: .dashUIKit),
                isEnabled: value != nil,
                size: .medium,
                style: .tintedGray,
                accessibilityLabel: copyLabel,
                action: action
            )
        }
        .padding(.vertical, 6)
    }

    /// Always laid out, and only faded when there is nothing to watch: an
    /// absent view takes its padding with it, which left the actions sitting
    /// on the card's bottom edge and made the card jump when watching began.
    private var watchingForPayment: some View {
        ReceiveWatchingIndicator()
            .opacity(viewModel.isWatchingForReceipt ? 1 : 0)
            .accessibilityHidden(!viewModel.isWatchingForReceipt)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isWatchingForReceipt)
    }

    private var hasAddress: Bool {
        viewModel.currentAddress != nil
    }

    // MARK: - QR

    @ViewBuilder
    private var qrCard: some View {
        VStack(spacing: 20) {
            if let address = viewModel.currentAddress,
               let qr = QRCodeGenerator.image(for: address) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
                    // White in both themes, not `secondaryBackground`: this is
                    // the code's quiet zone, and a scanner needs the contrast
                    // whatever the app is wearing. Without it the dark card ran
                    // straight up to the modules.
                    .padding(10)
                    .background(Color.dash.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if viewModel.network == .platform && !viewModel.platformIsReady {
                placeholder(NSLocalizedString("Platform sync starting…", comment: ""))
            } else if viewModel.network == .shielded {
                // Nil only until the shielded sub-wallet binds at startup
                // (the view model retries as the platform stack comes up).
                placeholder(NSLocalizedString("Shielded wallet starting…", comment: ""))
            } else {
                placeholder(NSLocalizedString("No address available", comment: ""))
            }
        }
    }

    /// Same 220pt square the QR occupies (200 + 10 padding a side), so
    /// switching balances doesn't make the actions below jump.
    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 8) {
            SwiftUI.ProgressView()
            Text(message)
                .font(.footnote)
                .foregroundColor(Color.dash.secondaryText)
        }
        .frame(width: 220, height: 220)
    }

}

// MARK: - ReceiveReceiptCard

/// The payment that just landed, in place of the address it was paid to.
///
/// Ported from the attended-receive work rather than rebuilt: the header is the
/// same `PaymentSuccessHeader` the send flow finishes on, so a receipt and a
/// sent confirmation read as two sides of one screen instead of two designs.
///
/// It reports rather than acts — which controller shows the transaction, and
/// what Done closes, are the host's to decide.
private struct ReceiveReceiptCard: View {
    let receipt: ReceiveReceipt
    let canViewTransaction: Bool
    let onViewTransaction: (Data) -> Void
    let onReceiveAnother: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            PaymentSuccessHeader(
                title: NSLocalizedString("Received", comment: "Receive success title"),
                amountDuffs: Int64(clamping: receipt.amountDuffs),
                fiatText: CurrencyExchanger.shared.fiatAmountString(
                    for: receipt.amountDuffs.dashAmount))

            VStack(spacing: 8) {
                row(NSLocalizedString("Balance", comment: "Receive receipt rail"),
                    receipt.rail.balanceName)
                row(NSLocalizedString("Status", comment: "Receive receipt status"),
                    receipt.statusTitle)
                row(NSLocalizedString("Time", comment: "Receive receipt time"),
                    receipt.receivedAt.formatted(date: .omitted, time: .shortened))
                if let memo = receipt.memo, !memo.isEmpty {
                    row(NSLocalizedString("Memo", comment: "Receive receipt memo"), memo)
                }
            }
            .padding(14)
            .modifier(MenuViewModifier(innerPadding: 0))

            if canViewTransaction, let transactionId = receipt.transactionId {
                Button {
                    onViewTransaction(transactionId)
                } label: {
                    Text(NSLocalizedString("View transaction", comment: "Receive receipt action"))
                        .dashFont(.subheadMedium)
                        .foregroundColor(.dash.blue)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 12)

            ButtonsGroup(
                orientation: .horizontal,
                size: .large,
                positiveButtonText: NSLocalizedString("Done", comment: "Receive receipt action"),
                positiveButtonAction: onDone,
                negativeButtonText: NSLocalizedString("Receive another", comment: "Receive receipt action"),
                negativeButtonAction: onReceiveAnother)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .dashFont(.caption1)
                .foregroundColor(.dash.secondaryText)
            Spacer()
            Text(value)
                .dashFont(.caption1Medium)
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

// MARK: - ReceiveWatchingIndicator

/// Says the screen is doing something on the user's behalf while an address is
/// on display, so a handoff does not feel like nothing is happening.
///
/// Shared with the specify-amount sheet, which makes the same promise over a QR
/// that carries the amount — the two must not drift into saying it differently.
struct ReceiveWatchingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            // `controlSize`, not `scaleEffect`: scaling resamples the spinner
            // after it is drawn, which is what turned it into a crunchy
            // asterisk. This asks UIKit for a small indicator and gets it drawn
            // at that size.
            SwiftUI.ProgressView()
                .controlSize(.small)
            Text(NSLocalizedString("Watching for a payment…", comment: "Receive screen activity"))
                .dashFont(.caption1)
                .foregroundColor(.dash.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }
}

/// Lays its children out in equal widths. Its ideal width is the widest
/// child's times their count, so `ViewThatFits` only picks it when every
/// child gets at least its whole title.
private struct EvenOptionRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let widest = ideal.map(\.width).max() ?? 0
        let width = proposal.width.map { max($0, widest * CGFloat(subviews.count)) }
            ?? widest * CGFloat(subviews.count)
        return CGSize(width: width, height: ideal.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = bounds.width / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + width * CGFloat(index), y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}

#if DEBUG

@MainActor
private func receiveSample(
    network: ReceiveOption = .core,
    coreAddress: String? = "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN",
    isAdvancedMode: Bool = false,
    identity: ReceiveIdentity? = nil,
    isWatching: Bool = false
) -> some View {
    let viewModel = PaymentsLandingViewModel.makeForPreview(
        activeTab: .receive, coreAddress: coreAddress, isWatching: isWatching)
    viewModel.updateReceiveState(isAdvancedMode: isAdvancedMode, identity: identity)
    viewModel.network = network
    return PaymentsReceiveContent(
        viewModel: viewModel,
        onCopyAddress: {},
        onShareAddress: {},
        onSpecifyAmount: {})
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Core address") {
    receiveSample()
}

/// Both action pills disable without an address — the row must not collapse.
@available(iOS 17, *)
#Preview("No address") {
    receiveSample(coreAddress: nil)
}

private let previewIdentity = ReceiveIdentity(
    identityId: Data((1...32).map { UInt8($0) }), username: "alice")

@available(iOS 17, *)
#Preview("Three options") {
    receiveSample(network: .platform, isAdvancedMode: true)
}

/// Four titles overflow 375 pt: the row scrolls, the selected Identity in view.
@available(iOS 17, *)
#Preview("Four options, 375 pt") {
    receiveSample(network: .identity, isAdvancedMode: true, identity: previewIdentity)
        .frame(width: 375)
}

@available(iOS 17, *)
#Preview("Identity, watching") {
    receiveSample(network: .identity, isAdvancedMode: true, identity: previewIdentity, isWatching: true)
}

/// The first read has not succeeded: everything works, no watching claim.
@available(iOS 17, *)
#Preview("Identity, not watching") {
    receiveSample(network: .identity, isAdvancedMode: true, identity: previewIdentity)
}

/// Identity credits have no transaction to open and carry no memo (SCR-03).
@available(iOS 17, *)
#Preview("Identity receipt") {
    ReceiveReceiptCard(
        receipt: ReceiveReceipt(
            id: "identity-preview",
            rail: .identity,
            amountDuffs: 50_000_000,
            receivedAt: Date(timeIntervalSince1970: 1_793_000_000),
            memo: nil,
            transactionId: nil),
        canViewTransaction: false,
        onViewTransaction: { _ in },
        onReceiveAnother: {},
        onDone: {})
        .padding(20)
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Four options, xxxLarge") {
    receiveSample(network: .shielded, isAdvancedMode: true, identity: previewIdentity)
        .dynamicTypeSize(.xxxLarge)
}

#endif
