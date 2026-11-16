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

/// The From / To endpoint cards, in whichever of the two shapes the host
/// asked for.
///
/// The screen used to build all three inline, which is why choosing a layout
/// and drawing a balance row lived in the same 200 lines. Which shape applies
/// still follows from `receiveInto` alone, so the decision travels
/// with the drawing rather than with the screen.
///
/// Every shape is the design system's `ConverterCard` over one picker sheet.
/// The pinned variant used to be a hand-rolled row with its own radio list
/// instead — a second visual language and a second way to choose the same
/// endpoint, left behind when the standalone form moved to the card.
struct TransferEndpointCards: View {
    @ObservedObject var viewModel: InternalTransferViewModel

    /// Receive-sheet variant: fixes the destination card at the bottom and
    /// turns the rows above it into the source picker.
    var receiveInto: ChainNetwork?

    /// Which endpoint the standalone card is currently picking, if any.
    /// Presentation state only — the options and the selection belong to
    /// `TransferEndpointPicker` and the view model.
    @State private var picker: TransferEndpointSide?

    var body: some View {
        layout
            // One sheet for both layouts: what changes between them is
            // which endpoints it offers, not that it exists. No detent and no
            // drag indicator here — the picker is a `BottomSheet.selfSizing`,
            // which sets its own height detent and draws its own grabber.
            .sheet(item: $picker) { side in
                TransferEndpointPicker(
                    viewModel: viewModel,
                    side: side,
                    options: pickerOptions,
                    onPicked: { picker = nil })
            }
    }

    // MARK: - Layouts

    /// Both shapes are the design system's `ConverterCard` — they differ
    /// only in which row carries a tap and whether the seam badge swaps.
    @ViewBuilder
    private var layout: some View {
        if let target = receiveInto {
            receiveCards(target: target)
        } else {
            swappableCards
        }
    }

    /// Receive-sheet layout: the destination is the fixed bottom row and the
    /// top one picks the source among the other balances. `onSwap: nil` leaves
    /// the static arrow on the seam: with one side pinned there is nothing to
    /// exchange, only a direction to state.
    private func receiveCards(target: ChainNetwork) -> some View {
        DashUIKit.ConverterCard(
            fromItem: converterItem(
                viewModel.resolvedReceiveSource,
                onTap: { picker = .source }),
            toItem: converterItem(target),
            onSwap: nil)
    }

    /// Standalone screen: both rows are tappable — each opens the picker for
    /// its own side, over every endpoint that side accepts. The badge goes
    /// static (`onSwap: nil`) only for the one pair whose reverse does not
    /// exist; the view model owns that judgement.
    private var swappableCards: some View {
        DashUIKit.ConverterCard(
            fromItem: fromItem,
            toItem: toItem,
            onSwap: viewModel.canSwapEndpoints
                ? { viewModel.swapStandaloneEndpoints() }
                : nil)
    }

    /// What the picker offers, which is the one thing the two layouts
    /// disagree on. The pinned sheet reaches no identity and never lists the
    /// endpoint it has fixed, so it picks a plain balance through its own
    /// side's setter.
    private var pickerOptions: TransferEndpointPicker.Options {
        if let target = receiveInto {
            return .balances(
                availableSources(for: target),
                selected: viewModel.resolvedReceiveSource,
                select: viewModel.selectReceiveSource)
        }
        return .standalone
    }

    /// Whether a row opens a picker — and so whether it draws a chevron.
    ///
    /// Simple mode offers two balances and a badge between them that swaps
    /// which is which, so a picker would only ever offer the row the user is
    /// already looking at or the one directly opposite. The chevron promised a
    /// choice that did not exist.
    private var rowsArePickers: Bool {
        viewModel.isAdvancedMode
    }

    private func pickerTap(_ target: TransferEndpointSide) -> (() -> Void)? {
        rowsArePickers ? { picker = target } : nil
    }

    private var fromItem: DashUIKit.ConverterCardItem {
        viewModel.isIdentitySource
            ? identityConverterItem(onTap: pickerTap(.source))
            : converterItem(viewModel.source, onTap: pickerTap(.source))
    }

    private var toItem: DashUIKit.ConverterCardItem {
        if viewModel.isIdentityDestination {
            return identityConverterItem(onTap: pickerTap(.destination))
        }
        // With the identity on the FROM side the TO side is the withdrawal's
        // payout balance, which is a narrower set than `resolvedSendTarget`.
        let network = viewModel.isIdentitySource
            ? viewModel.resolvedWithdrawalTarget.network
            : viewModel.resolvedSendTarget
        return converterItem(network, onTap: pickerTap(.destination))
    }

    /// The identity's own credit balance, rendered in DASH like the balance
    /// rows — the same persisted number the profile sheet shows.
    private func identityConverterItem(onTap: (() -> Void)?) -> DashUIKit.ConverterCardItem {
        let display = TransferEndpointDisplay.identity(in: viewModel)
        return DashUIKit.ConverterCardItem(
            id: "identity",
            icon: display.icon,
            title: display.title,
            dashBalance: display.dashBalance ?? 0,
            trailingView: display.dashBalance == nil ? AnyView(Text("—")) : nil,
            onTap: onTap)
    }

    /// No From / To caption, unlike the picker rows: on a swap the two rows
    /// physically exchange places, so a caption riding along with one would
    /// read as the wrong side mid-flight. The badge on the seam is what says
    /// which way the transfer runs — the same bargain the Coinbase transfer
    /// card makes. `onTap` turns the whole row into the button that opens
    /// that side's picker.
    private func converterItem(
        _ network: ChainNetwork,
        onTap: (() -> Void)? = nil
    ) -> DashUIKit.ConverterCardItem {
        let display = TransferEndpointDisplay.network(network, in: viewModel)
        return DashUIKit.ConverterCardItem(
            id: network,
            icon: display.icon,
            title: display.title,
            dashBalance: display.dashBalance ?? 0,
            trailingView: display.dashBalance == nil ? AnyView(Text("—")) : nil,
            onTap: onTap)
    }

    // MARK: - Helpers

    /// The pinned sheet's picker list: the fixed endpoint's balance is left
    /// out entirely — only the standalone screen shows all three with
    /// same-balance taps rejected.
    private func availableSources(for target: ChainNetwork) -> [ChainNetwork] {
        viewModel.availableNetworks.filter { $0 != target }
    }
}

#if DEBUG

@MainActor
private func endpointCardsSample(
    receiveInto: ChainNetwork? = nil,
    source: ChainNetwork = .core,
    target: ChainNetwork = .platform
) -> some View {
    TransferEndpointCards(
        viewModel: .makeForPreview(
            source: source,
            target: target,
            receiveInto: receiveInto),
        receiveInto: receiveInto)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

/// The standalone screen: each row opens its own picker (tapping one in the
/// canvas presents the real sheet) and the seam badge swaps the two.
@available(iOS 17, *)
#Preview("Standalone · collapsed") {
    endpointCardsSample()
}

/// Identity destination: the To row is the identity (its own credit balance
/// in DASH) and the seam badge is the static arrow — nothing to swap into.
/// Both rows still open their pickers; the To one is how you get back to a
/// balance destination.
@available(iOS 17, *)
#Preview("Standalone · to Identity") {
    TransferEndpointCards(
        viewModel: .makeForPreview(identityDestination: true),
        receiveInto: nil)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

/// Identity source: credits leaving the identity for Transparent. The badge
/// swaps here — the reverse (a top-up from Transparent) exists.
@available(iOS 17, *)
#Preview("Standalone · from Identity") {
    TransferEndpointCards(
        viewModel: .makeForPreview(target: .core, identitySource: true),
        receiveInto: nil)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

/// The one static-badge pair: Shielded → Identity cannot be reversed, so the
/// seam shows the plain arrow rather than a swap that would fail.
@available(iOS 17, *)
#Preview("Standalone · Shielded → Identity") {
    TransferEndpointCards(
        viewModel: .makeForPreview(source: .shielded, identityDestination: true),
        receiveInto: nil)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

/// Receive sheet: the To card is pinned at the bottom, the From rows above it.
@available(iOS 17, *)
#Preview("Receive · into Shielded") {
    endpointCardsSample(receiveInto: .shielded, source: .core, target: .shielded)
}

@available(iOS 17, *)
#Preview("Dark") {
    endpointCardsSample(receiveInto: .shielded, source: .core, target: .shielded)
        .preferredColorScheme(.dark)
}

/// A zero balance still has to render an amount, not an empty trailing slot.
@available(iOS 17, *)
#Preview("Empty balances") {
    TransferEndpointCards(
        viewModel: .makeForPreview(
            coreDuffs: 0,
            platformCredits: 0,
            shieldedCredits: 0),
        receiveInto: nil)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

#endif
