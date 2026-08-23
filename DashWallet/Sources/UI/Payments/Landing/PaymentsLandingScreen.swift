//
//  PaymentsLandingScreen.swift
//  DashWallet
//

import DashUIKit
import SwiftUI
import UIKit

struct PaymentsLandingScreen: View {
    @ObservedObject var viewModel: PaymentsLandingViewModel

    var onClose: () -> Void
    var onCopyAddress: () -> Void
    var onShareAddress: () -> Void
    var onSpecifyAmount: () -> Void
    /// Opens the transaction behind a receive receipt. The host resolves the
    /// txid and presents the details, and pauses the attended session while
    /// they are up.
    var onViewTransaction: (Data) -> Void
    var onScanQR: () -> Void
    /// The Internal tab's embedded transfer form. The full landing shows it
    /// un-pinned (free From + To pickers); the balance-row receive/send
    /// sheets pin one endpoint via `transferReceivePinned`/`transferSendFrom`.
    var embeddedTransferViewModel: InternalTransferViewModel
    var onTransferCompleted: () -> Void = {}
    /// Set by the balance-row send sheet: the embedded transfer form pins
    /// this balance as its From card (destination picked on the To rows),
    /// instead of the receive sheet's pinned-destination layout.
    var transferSendFrom: ChainNetwork?
    /// True for the balance-row receive sheet: the transfer form pins the
    /// receive toggle's balance as its To card (source picked on the From
    /// rows). False (with `transferSendFrom` nil) = the free-form landing.
    var transferReceivePinned: Bool = false
    /// The Send tab IS the external-send form — pinned to the tapped
    /// balance as source on the balance-row send sheet, un-pinned (full
    /// From picker) on the full landing.
    var embeddedSendViewModel: SendViewModel
    /// The Send tab's address is valid → advance to the amount step. The host
    /// pushes `ExternalSendAmountScreen` onto the landing's navigation stack.
    var onSendContinue: () -> Void = {}
    /// A destination picked on the Internal tab's card — the host pushes the
    /// transfer form with that balance preselected as the To endpoint.
    var onInternalTransfer: (TransferDestination) -> Void = { _ in }
    /// "Send to address" on the Send tab's card — the host pushes the send
    /// form. (Its sibling row routes through `onScanQR`.)
    var onSendToAddress: () -> Void = {}
    /// False for the balance-row receive/send sheets: their grabber + hero
    /// selector are the top chrome — no X close button or title row.
    var showsHeader: Bool = true

    /// Raised by the Receive tab's copy button. Lives here rather than in
    /// `PaymentsReceiveContent` so the toast floats over the whole screen —
    /// inside that subtree it would be pinned above the action buttons.
    @State private var showsCopiedToast = false
    /// Which way the last tab change moved along `visibleTabs`, so the
    /// incoming content slides in from the side it came from.
    @State private var slidesForward = true

    private enum Layout {
        /// Side margin for the picker cards, so they line up with the tab
        /// selector above them instead of running to the screen edges.
        static let cardHorizontalPadding: CGFloat = 20
        /// Gap under the (currently unreachable) header.
        static let headerBottomPadding: CGFloat = 20
        /// Tighter for the balance-row sheets: the form they embed needs the
        /// vertical room for its amount row, endpoint cards and keypad.
        static let embeddedFormTopPadding: CGFloat = 12
        /// Far enough that a tap that drifts, or a vertical flick, is not read
        /// as a tab change.
        static let swipeMinimumDistance: CGFloat = 24
        /// Matches the selector pill's own spring (`SegmentedControlLayout`),
        /// so the pill and the content travel together.
        static let slideResponse: Double = 0.3
        static let slideDamping: Double = 0.7
    }

    /// Who the screen is drawing for. The payments tab shows pickers; the
    /// balance-row sheets hand one pinned endpoint to a whole embedded form
    /// instead. Resolved once here rather than re-derived per tab, so the
    /// spacing and the content can never disagree about which one it is.
    private enum Mode {
        /// The payments tab: every tab opens on a destination card.
        case picker
        /// Balance-row send sheet — the tapped balance is the source.
        case sendingFrom(ChainNetwork)
        /// Balance-row receive sheet — the receive toggle's balance is the
        /// destination, kept in lockstep by the hosting controller.
        case receivingInto
    }

    private var mode: Mode {
        if let transferSendFrom { return .sendingFrom(transferSendFrom) }
        if transferReceivePinned { return .receivingInto }
        return .picker
    }

    private var isPickerMode: Bool {
        if case .picker = mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            if showsHeader {
                header
            }

            PaymentsTabSelector(
                tabs: viewModel.visibleTabs,
                selection: tabSelection
            )
            .frame(height: 70)
            .padding(.top, 20)
            .padding(.horizontal, 16)

            // ZStack, not a plain sibling: during the slide both the outgoing
            // and incoming tab exist, and they have to share one slot instead
            // of stacking and shoving the layout.
            ZStack(alignment: .top) {
                tabContent
                    .id(viewModel.activeTab)
                    .transition(slide)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Color.dash.primaryBackground)
        // Makes the empty area below the card draggable too, so the swipe
        // works on the whole screen rather than only over the content.
        .contentShape(Rectangle())
        // `.gesture` (not `highPriority`) so rows and buttons keep winning
        // their taps. `including:` is how the gesture is switched off — the
        // modifier has no nil overload.
        .gesture(tabSwipe, including: isPickerMode ? .all : .subviews)
        .navigationBarHidden(true)
        // Keyed on the receipt's id, not on the receipt: a second payment
        // arriving replaces the card rather than cross-fading into itself.
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.receipt?.id)
        .sensoryFeedback(.success, trigger: viewModel.receipt?.id)
        .transientToast(
            isPresented: $showsCopiedToast,
            style: .copied,
            message: NSLocalizedString("Copied", comment: ""))
    }

    // MARK: - Swipe between tabs

    /// A horizontal swipe anywhere on the screen moves the selector one tab,
    /// the way the segmented control above it implies it should.
    ///
    /// Off in the balance-row sheets (`including: .subviews` above): there a
    /// tab is a whole form with a keypad, and paging away mid-entry would drop
    /// what the user typed. The picker tabs have nothing to lose and no scroll
    /// view of their own to fight over the gesture.
    private var tabSwipe: some Gesture {
        DragGesture(minimumDistance: Layout.swipeMinimumDistance)
            .onEnded { value in
                // Ignore a mostly-vertical drag, so a flick down the screen
                // doesn't change tab on its horizontal wobble.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                selectTab(offsetBy: value.translation.width < 0 ? 1 : -1)
            }
    }

    /// Moves `offset` tabs along `visibleTabs`, stopping at either end rather
    /// than wrapping — the selector shows the whole list, so wrapping would
    /// read as the pill teleporting.
    private func selectTab(offsetBy offset: Int) {
        let tabs = viewModel.visibleTabs
        guard let current = tabs.firstIndex(of: viewModel.activeTab) else { return }
        let target = current + offset
        guard tabs.indices.contains(target) else { return }

        select(tabs[target])
    }

    /// Everything that changes the tab goes through here, including the
    /// selector's own taps and drag — the content slides in from whichever
    /// side the new tab sits on, and only this knows which side that is.
    private var tabSelection: Binding<PaymentsLandingTab> {
        Binding(
            get: { viewModel.activeTab },
            set: { select($0) })
    }

    private func select(_ tab: PaymentsLandingTab) {
        let tabs = viewModel.visibleTabs
        guard let from = tabs.firstIndex(of: viewModel.activeTab),
              let to = tabs.firstIndex(of: tab),
              from != to
        else { return }

        slidesForward = to > from
        withAnimation(.spring(response: Layout.slideResponse,
                              dampingFraction: Layout.slideDamping)) {
            viewModel.activeTab = tab
        }
    }

    /// Matches the direction of travel: going right, the new tab enters from
    /// the right and the old one leaves to the left.
    private var slide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: slidesForward ? .trailing : .leading),
            removal: .move(edge: slidesForward ? .leading : .trailing))
    }

    /// Wraps a picker card as ONE view: spaced off the selector and pinned to
    /// the top. The Spacer has to live inside the branch — as a sibling in the
    /// outer stack it would not travel with the card, and the slide would tear
    /// the two apart.
    private func pickerLayout<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: - Tab content

    /// Each branch owns the gap under the selector, because the two kinds of
    /// content want different ones — a picker card breathes, an embedded form
    /// needs the pixels for its keypad.
    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.activeTab {
        case .receive:
            pickerLayout {
                PaymentsReceiveContent(
                    viewModel: viewModel,
                    onCopyAddress: {
                        onCopyAddress()
                        showsCopiedToast = true
                    },
                    onShareAddress: onShareAddress,
                    onSpecifyAmount: onSpecifyAmount,
                    onViewTransaction: onViewTransaction,
                    onDone: onClose
                )
                .padding(.horizontal, Layout.cardHorizontalPadding)
            }

        case .internalTransfer:
            switch mode {
            case .picker:
                pickerLayout {
                    PaymentsInternalCard(
                        onSelect: onInternalTransfer,
                        showsAdvancedDestinations: viewModel.isAdvancedMode)
                        .padding(.horizontal, Layout.cardHorizontalPadding)
                }

            case let .sendingFrom(source):
                InternalTransferScreen(
                    viewModel: embeddedTransferViewModel,
                    onCompleted: onTransferCompleted,
                    showsHeader: false,
                    sendFrom: source
                )
                .padding(.top, Layout.embeddedFormTopPadding)

            case .receivingInto:
                InternalTransferScreen(
                    viewModel: embeddedTransferViewModel,
                    onCompleted: onTransferCompleted,
                    showsHeader: false,
                    receiveInto: viewModel.network
                )
                .padding(.top, Layout.embeddedFormTopPadding)
            }

        case .send:
            switch mode {
            case .picker, .receivingInto:
                pickerLayout {
                    PaymentsSendCard(
                        onScanQR: onScanQR,
                        onSendToAddress: onSendToAddress
                    )
                    .padding(.horizontal, Layout.cardHorizontalPadding)
                }

            case .sendingFrom:
                SendScreen(
                    viewModel: embeddedSendViewModel,
                    onClose: onClose,
                    onScanQR: onScanQR,
                    onContinue: onSendContinue,
                    showsHeader: false
                )
                .padding(.top, Layout.embeddedFormTopPadding)
            }
        }
    }

    // MARK: - Header

    /// Back only, no title. The landing is where a flow starts, so the tab
    /// selector below already names the destination; the screens it pushes
    /// carry their own titles.
    ///
    /// Currently unreachable: every caller passes `showsHeader: false` since
    /// the landing became a tab.
    private var header: some View {
        NavigationBar(
            leading: { NavigationBarElement.back.button(action: onClose) })
            .padding(.bottom, Layout.headerBottomPadding)
    }

}

#if DEBUG

/// The full landing draws destination cards, which need no wallet at all. The
/// pinned variants at the bottom embed real forms instead, and previews run
/// without a wallet — those price nothing the SDK owns, so they render the
/// "fee unavailable" state rather than an enabled Continue.
@MainActor
private func landingSample(
    activeTab: PaymentsLandingTab = .internalTransfer,
    network: ChainNetwork = .core,
    visibleTabs: [PaymentsLandingTab] = PaymentsLandingTab.allCases,
    coreAddress: String? = "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN",
    transferAmount: String = "0",
    transferSendFrom: ChainNetwork? = nil,
    transferReceivePinned: Bool = false,
    showsHeader: Bool = true
) -> some View {

    PaymentsLandingScreen(
        viewModel: .makeForPreview(
            activeTab: activeTab,
            network: network,
            visibleTabs: visibleTabs,
            coreAddress: coreAddress),
        onClose: {},
        onCopyAddress: {},
        onShareAddress: {},
        onSpecifyAmount: {},
        onViewTransaction: { _ in },
        onScanQR: {},
        embeddedTransferViewModel: .makeForPreview(amountText: transferAmount),
        transferSendFrom: transferSendFrom,
        transferReceivePinned: transferReceivePinned,
        embeddedSendViewModel: .makeForPreview(pinnedSource: transferSendFrom),
        showsHeader: showsHeader)
}

// MARK: Tabs

/// The tab selector is the shared chrome — these three show it in each of its
/// selected states, above the content that tab actually renders.
@available(iOS 17, *)
#Preview("Internal tab") {
    landingSample(showsHeader: false)
}

/// The presentation the balance-row receive sheet uses: Send is not offered,
/// so the landing has to hold together on two tabs. `PaymentsTabSelector` has
/// its own previews for the selector's own states.
@available(iOS 17, *)
#Preview("Two tabs · receive sheet") {
    landingSample(
        activeTab: .receive,
        visibleTabs: [.receive, .internalTransfer])
}

// MARK: Receive tab states

/// No address resolved yet — the QR card gives way to its placeholder.
@available(iOS 17, *)
#Preview("Receive · no address") {
    landingSample(activeTab: .receive, coreAddress: nil)
}

@available(iOS 17, *)
#Preview("Receive · shielded placeholder") {
    landingSample(activeTab: .receive, network: .shielded)
}

// MARK: Sheet embeddings

/// Balance-row send sheet: no header (the sheet's grabber and hero selector are
/// the top chrome) and the transfer form's From card pinned.
@available(iOS 17, *)
#Preview("Send sheet · pinned From") {
    landingSample(
        transferAmount: "0.5",
        transferSendFrom: .core,
        showsHeader: false)
}

/// Balance-row receive sheet: the transfer form's To card is pinned to the
/// receive toggle's network.
@available(iOS 17, *)
#Preview("Receive sheet · pinned To") {
    landingSample(
        network: .platform,
        visibleTabs: [.receive, .internalTransfer],
        transferAmount: "0.5",
        transferReceivePinned: true,
        showsHeader: false)
}

#endif

