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

/// The From / To endpoint cards, in whichever of the three shapes the host
/// asked for.
///
/// The screen used to build all three inline, which is why choosing a layout
/// and drawing a balance row lived in the same 200 lines. Which shape applies
/// still follows from `sendFrom` / `receiveInto` alone, so the decision travels
/// with the drawing rather than with the screen.
struct TransferEndpointCards: View {
    @ObservedObject var viewModel: InternalTransferViewModel

    /// Send-sheet variant: fixes the source card at the top and turns the rows
    /// below it into the destination picker. Takes precedence over `receiveInto`.
    var sendFrom: ChainNetwork?

    /// Receive-sheet variant: fixes the destination card at the bottom and
    /// turns the rows above it into the source picker.
    var receiveInto: ChainNetwork?

    /// Which endpoint the standalone card is currently picking, if any.
    /// Presentation state only; the selection itself lives in the view model.
    ///
    /// One enum rather than two flags because both sheets hang off the same
    /// view, where stacked `.sheet(isPresented:)` modifiers only honour the
    /// outermost one.
    private enum EndpointPicker: Int, Identifiable {
        case source
        case destination

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .source:
                return NSLocalizedString("Transfer from", comment: "Internal transfer source picker title")
            case .destination:
                return NSLocalizedString("Transfer to", comment: "Internal transfer destination picker title")
            }
        }

        var caption: String {
            switch self {
            case .source: return NSLocalizedString("From", comment: "")
            case .destination: return NSLocalizedString("To", comment: "")
            }
        }
    }

    @State private var picker: EndpointPicker?

    @ViewBuilder
    var body: some View {
        if let source = sendFrom {
            sendCards(source: source)
        } else if let target = receiveInto {
            receiveCards(target: target)
        } else {
            swappableCards
        }
    }

    // MARK: - Layouts

    /// Send-sheet layout: the source stays pinned as the top card; the rows
    /// below pick the destination among the other two balances. No swap
    /// badge — the source is fixed by the tapped balance row.
    @ViewBuilder
    private func sendCards(source: ChainNetwork) -> some View {
        VStack(spacing: 12) {
            pinnedCard(source, caption: NSLocalizedString("From", comment: ""))
            selectionGroup(
                caption: NSLocalizedString("To", comment: ""),
                networks: availableTargets(for: source),
                selected: viewModel.resolvedSendTarget,
                onSelect: viewModel.selectSendTarget)
        }
    }

    /// Receive-sheet layout: the destination stays pinned as the bottom
    /// card; the rows above pick the source among the other two balances.
    /// No swap badge — the destination is fixed by the tapped balance row.
    @ViewBuilder
    private func receiveCards(target: ChainNetwork) -> some View {
        VStack(spacing: 12) {
            selectionGroup(
                caption: NSLocalizedString("From", comment: ""),
                networks: availableSources(for: target),
                selected: viewModel.resolvedReceiveSource,
                onSelect: viewModel.selectReceiveSource)

            pinnedCard(target, caption: NSLocalizedString("To", comment: ""))
        }
    }

    /// Standalone screen: the design system's `ConverterCard`, the same pair of
    /// rows the Coinbase transfer screen uses, with the swap badge on the seam.
    /// Both rows are tappable — each opens the picker for its own side, over
    /// every endpoint that side accepts. The badge goes static (`onSwap: nil`)
    /// only for the one pair whose reverse does not exist; the view model
    /// owns that judgement.
    private var swappableCards: some View {
        DashUIKit.ConverterCard(
            fromItem: fromItem,
            toItem: toItem,
            onSwap: viewModel.canSwapEndpoints
                ? { viewModel.swapStandaloneEndpoints() }
                : nil)
            // No detent and no drag indicator here: `pickerSheet` returns a
            // `BottomSheet.selfSizing`, which sets its own height detent and
            // draws its own grabber.
            .sheet(item: $picker) { picker in
                pickerSheet(picker)
            }
    }

    private var fromItem: DashUIKit.ConverterCardItem {
        viewModel.isIdentitySource
            ? identityConverterItem(onTap: { picker = .source })
            : converterItem(viewModel.source, onTap: { picker = .source })
    }

    private var toItem: DashUIKit.ConverterCardItem {
        if viewModel.isIdentityDestination {
            return identityConverterItem(onTap: { picker = .destination })
        }
        // With the identity on the FROM side the TO side is the withdrawal's
        // payout balance, which is a narrower set than `resolvedSendTarget`.
        let network = viewModel.isIdentitySource
            ? viewModel.resolvedWithdrawalTarget.network
            : viewModel.resolvedSendTarget
        return converterItem(network, onTap: { picker = .destination })
    }

    /// The identity's own credit balance, rendered in DASH like the balance
    /// rows — the same persisted number the profile sheet shows.
    private func identityConverterItem(onTap: @escaping () -> Void) -> DashUIKit.ConverterCardItem {
        DashUIKit.ConverterCardItem(
            id: "identity",
            icon: DashIcon.Features.identity.source,
            title: InternalTransferViewModel.identityBalanceName,
            dashBalance: Int64(viewModel.identityBalanceCredits / 1000),
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
        DashUIKit.ConverterCardItem(
            id: network,
            icon: converterIcon(network),
            title: network.balanceName,
            dashBalance: Int64(balanceDuffs(network)),
            onTap: onTap)
    }

    /// Catalog assets rather than the picker rows' SF Symbols: `ConverterCard`
    /// draws the icon plain at 30pt, with no tinted circle behind it to carry
    /// the colour.
    private func converterIcon(_ network: ChainNetwork) -> DashIconSource {
        switch network {
        case .core: return DashIcon.Menu.dashLogoSquare.source
        case .platform: return DashIcon.Features.platform.source
        case .shielded: return DashIcon.Features.shield.source
        }
    }

    /// Every balance as duffs, which is what `ConverterCardItem` renders.
    /// Platform and Shielded are held in credits — 1000 per duff.
    private func balanceDuffs(_ network: ChainNetwork) -> UInt64 {
        switch network {
        case .core: return viewModel.coreBalanceDuffs
        case .platform: return viewModel.platformCredits / 1000
        case .shielded: return viewModel.shieldedBalance / 1000
        }
    }

    // MARK: - Cards

    /// Non-tappable pinned endpoint card (the fixed From of the send sheet).
    private func pinnedCard(_ network: ChainNetwork, caption: String) -> some View {
        let display = networkDisplay(network)
        return TransferSourceRow(
            iconSystemName: display.icon,
            caption: caption,
            title: display.title,
            balanceTrailing: TransferSourceRow.dashBalanceTrailing(display.balance),
            selected: false,
            showsRadio: false,
            action: {})
    }

    private func selectionGroup(
        caption: String,
        networks: [ChainNetwork],
        selected: ChainNetwork,
        onSelect: @escaping (ChainNetwork) -> Void
    ) -> some View {
        VStack(spacing: 8) {
            ForEach(networks, id: \.self) { network in
                let display = networkDisplay(network)
                TransferSourceRow(
                    iconSystemName: display.icon,
                    caption: caption,
                    title: display.title,
                    balanceTrailing: TransferSourceRow.dashBalanceTrailing(display.balance),
                    selected: selected == network,
                    action: { onSelect(network) })
            }
        }
    }

    // MARK: - Endpoint picker sheets

    /// Both pickers are the design system's `BottomSheet`, which draws the
    /// grabber, the titled header and the close button. `selfSizing` measures
    /// the rows instead of taking a detent, so the To side's two-row list
    /// (identity as the source) is not padded out to the four-row height the
    /// From side needs.
    private func pickerSheet(_ picker: EndpointPicker) -> some View {
        DashUIKit.BottomSheet.selfSizing(
            title: picker.title,
            showBackButton: .constant(false)
        ) {
            pickerRows {
                switch picker {
                case .source: sourceSelection
                case .destination: destinationSelection
                }
            }
        }
    }

    /// The From side: the three balances plus Identity. Every pick applies
    /// and dismisses; picking one that collides with the To side moves THAT
    /// side (the view model keeps the endpoints distinct and coherent).
    private var sourceSelection: some View {
        VStack(spacing: 8) {
            ForEach(sourceOptions, id: \.self) { source in
                sourceRow(source)
            }
        }
    }

    /// The To side: the three balances plus Identity, which the landing card
    /// could reach but the screen itself could not. With the identity as the
    /// source it narrows to Transparent and Platform — the two targets one
    /// state transition reaches.
    private var destinationSelection: some View {
        VStack(spacing: 8) {
            ForEach(destinationOptions, id: \.self) { destination in
                destinationRow(destination)
            }
        }
    }

    /// Shared insets for both row lists.
    ///
    /// No title, no background and — importantly — no trailing `Spacer`: the
    /// header above draws the first two, and `selfSizing` measures the
    /// content's intrinsic height, which a greedy spacer would blow up to
    /// whatever the sheet was offered.
    private func pickerRows<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
    }

    private var sourceOptions: [TransferSource] {
        ChainNetwork.allCases.map(TransferSource.balance) + [.identity]
    }

    /// What the To side can be. With the identity as the source that is only
    /// what one state transition reaches — Transparent and Platform — and
    /// never the identity itself.
    private var destinationOptions: [TransferDestination] {
        if viewModel.isIdentitySource {
            return IdentityWithdrawalTarget.allCases.map { .balance($0.network) }
        }
        return ChainNetwork.allCases.map(TransferDestination.balance) + [.identity]
    }

    private func sourceRow(_ source: TransferSource) -> some View {
        let display = endpointDisplay(isIdentity: source == .identity, balance: sourceNetwork(source))
        return TransferSourceRow(
            iconSystemName: display.icon,
            caption: EndpointPicker.source.caption,
            title: display.title,
            balanceTrailing: TransferSourceRow.dashBalanceTrailing(display.balance),
            selected: viewModel.transferSource == source,
            action: {
                viewModel.selectStandaloneSource(source)
                picker = nil
            })
    }

    private func destinationRow(_ destination: TransferDestination) -> some View {
        let display = endpointDisplay(
            isIdentity: destination == .identity,
            balance: destinationNetwork(destination))
        return TransferSourceRow(
            iconSystemName: display.icon,
            caption: EndpointPicker.destination.caption,
            title: display.title,
            balanceTrailing: TransferSourceRow.dashBalanceTrailing(display.balance),
            selected: viewModel.destination == destination,
            action: {
                viewModel.selectStandaloneDestination(destination)
                picker = nil
            })
    }

    private func sourceNetwork(_ source: TransferSource) -> ChainNetwork? {
        if case .balance(let network) = source { return network }
        return nil
    }

    private func destinationNetwork(_ destination: TransferDestination) -> ChainNetwork? {
        if case .balance(let network) = destination { return network }
        return nil
    }

    /// `networkDisplay` widened to the identity, which both sides can now be.
    /// `balance == nil` means the identity row.
    private func endpointDisplay(
        isIdentity: Bool,
        balance: ChainNetwork?
    ) -> (icon: String, title: String, balance: String) {
        guard !isIdentity, let balance else {
            return ("person.crop.circle.fill",
                    InternalTransferViewModel.identityBalanceName,
                    viewModel.identityBalanceFormatted)
        }
        return networkDisplay(balance)
    }

    // MARK: - Helpers

    /// Icon / title / formatted balance for a balance row, one source of
    /// truth for the pinned cards and picker rows.
    private func networkDisplay(_ network: ChainNetwork) -> (icon: String, title: String, balance: String) {
        switch network {
        case .core:
            return ("d.circle.fill", network.balanceName, viewModel.coreBalanceFormatted)
        case .platform:
            return ("creditcard.fill", network.balanceName, viewModel.platformCreditsFormatted)
        case .shielded:
            return ("shield.fill", network.balanceName, viewModel.shieldedBalanceFormatted)
        }
    }

    /// Pinned-sheet picker lists (the balance-row arrow sheets): the fixed
    /// endpoint's balance is left out entirely — only the standalone screen
    /// shows all three with same-balance taps rejected.
    private func availableTargets(for source: ChainNetwork) -> [ChainNetwork] {
        ChainNetwork.allCases.filter { $0 != source }
    }

    private func availableSources(for target: ChainNetwork) -> [ChainNetwork] {
        ChainNetwork.allCases.filter { $0 != target }
    }
}

#if DEBUG

@MainActor
private func endpointCardsSample(
    sendFrom: ChainNetwork? = nil,
    receiveInto: ChainNetwork? = nil,
    source: ChainNetwork = .core,
    target: ChainNetwork = .platform
) -> some View {
    TransferEndpointCards(
        viewModel: .makeForPreview(
            source: source,
            target: target,
            sendFrom: sendFrom,
            receiveInto: receiveInto),
        sendFrom: sendFrom,
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
        sendFrom: nil,
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
        sendFrom: nil,
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
        sendFrom: nil,
        receiveInto: nil)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

/// Send sheet: the From card is pinned, the To rows are the picker.
@available(iOS 17, *)
#Preview("Send · from Transparent") {
    endpointCardsSample(sendFrom: .core, source: .core, target: .shielded)
}

@available(iOS 17, *)
#Preview("Send · from Shielded") {
    endpointCardsSample(sendFrom: .shielded, source: .shielded, target: .core)
}

/// Receive sheet: the To card is pinned at the bottom, the From rows above it.
@available(iOS 17, *)
#Preview("Receive · into Shielded") {
    endpointCardsSample(receiveInto: .shielded, source: .core, target: .shielded)
}

@available(iOS 17, *)
#Preview("Dark") {
    endpointCardsSample(sendFrom: .core, source: .core, target: .shielded)
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
        sendFrom: nil,
        receiveInto: nil)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

#endif
