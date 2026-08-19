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

    /// Standalone screen: which endpoint's balance picker is presented as the
    /// bottom sheet. `nil` = none — the form shows just the two selected
    /// endpoint cards, never all six rows at once. Presentation state only; the
    /// selection itself lives in the view model.
    @State private var endpointPicker: EndpointGroup?

    private enum EndpointGroup: String, Identifiable {
        case from
        case to

        var id: String { rawValue }
    }

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

    private var swappableCards: some View {
        VStack(spacing: 12) {
            collapsedEndpointCard(viewModel.source, caption: NSLocalizedString("From", comment: "")) {
                endpointPicker = .from
            }
            collapsedEndpointCard(viewModel.resolvedSendTarget, caption: NSLocalizedString("To", comment: "")) {
                endpointPicker = .to
            }
        }
        .sheet(item: $endpointPicker) { group in
            endpointPickerSheet(for: group)
                .presentationDetents([.height(400)])
                .presentationDragIndicator(.visible)
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

    private func collapsedEndpointCard(
        _ network: ChainNetwork,
        caption: String,
        action: @escaping () -> Void
    ) -> some View {
        let display = networkDisplay(network)
        return TransferSourceRow(
            iconSystemName: display.icon,
            caption: caption,
            title: display.title,
            balanceTrailing: TransferSourceRow.dashBalanceTrailing(display.balance),
            selected: false,
            showsRadio: false,
            showsChevron: true,
            action: action)
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

    // MARK: - Picker sheet

    /// Bottom-sheet balance picker for one endpoint, sized to slide over
    /// the keypad area. Every pick applies and dismisses — picking the
    /// balance already on the opposite side moves that side to its default
    /// (the view model keeps the endpoints distinct).
    private func endpointPickerSheet(for group: EndpointGroup) -> some View {
        let isFrom = group == .from
        return VStack(alignment: .leading, spacing: 16) {
            Text(isFrom
                ? NSLocalizedString("Transfer from", comment: "Internal transfer source picker title")
                : NSLocalizedString("Transfer to", comment: "Internal transfer destination picker title"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.dash.primaryText)

            selectionGroup(
                caption: isFrom
                    ? NSLocalizedString("From", comment: "")
                    : NSLocalizedString("To", comment: ""),
                networks: ChainNetwork.allCases,
                selected: isFrom ? viewModel.source : viewModel.resolvedSendTarget,
                onSelect: { network in
                    if isFrom {
                        viewModel.selectStandaloneSource(network)
                    } else {
                        viewModel.selectStandaloneTarget(network)
                    }
                    endpointPicker = nil
                })

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dash.primaryBackground)
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

/// The standalone screen: two collapsed cards, each opening a picker sheet.
/// Tapping one in the canvas presents the real sheet.
@available(iOS 17, *)
#Preview("Standalone · collapsed") {
    endpointCardsSample()
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
