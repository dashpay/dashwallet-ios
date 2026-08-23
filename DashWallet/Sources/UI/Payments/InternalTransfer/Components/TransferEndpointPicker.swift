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

/// Which endpoint a picker is choosing. Also the sheet item, so the two
/// pickers share one `.sheet(item:)` — stacked `.sheet(isPresented:)`
/// modifiers on a single view only honour the outermost one.
enum TransferEndpointSide: Int, Identifiable {
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
}

/// The bottom-sheet endpoint picker behind either row of the standalone
/// transfer card.
///
/// It lives apart from `TransferEndpointCards` because it is a screen of its
/// own — chrome, a list and a selection — rather than part of the card that
/// happens to present it. What the card keeps is the presentation state; what
/// the sheet keeps is which endpoints each side accepts.
///
/// Which options appear is not symmetric, and that asymmetry is the reason
/// this type exists rather than one generic list: the identity is a valid
/// endpoint on both sides, but with the identity already on the FROM side the
/// TO side narrows to what a single state transition reaches.
struct TransferEndpointPicker: View {

    /// Which endpoints the sheet offers, and how a pick is applied.
    ///
    /// The two cases are not a style choice: the standalone screen picks a
    /// `TransferSource` / `TransferDestination` (identity included) through the
    /// standalone setters, while a pinned sheet picks a plain balance through
    /// the setter for its own side. One list, two vocabularies.
    enum Options {
        /// The standalone screen: every endpoint the side accepts.
        case standalone
        /// A pinned sheet (`sendFrom` / `receiveInto`): the balances that
        /// remain once the fixed endpoint is out. No identity — neither pinned
        /// variant can reach one.
        case balances([ChainNetwork], selected: ChainNetwork, select: (ChainNetwork) -> Void)
    }

    @ObservedObject var viewModel: InternalTransferViewModel

    let side: TransferEndpointSide

    var options: Options = .standalone

    /// Called after a pick has been applied, for the host to dismiss. Every
    /// pick applies immediately — there is no confirm step in this sheet.
    var onPicked: () -> Void

    var body: some View {
        // The design system draws the grabber, the titled header and the
        // close button. `selfSizing` measures the rows instead of taking a
        // detent, so the two-row list is not padded out to the four-row
        // height the other side needs.
        DashUIKit.BottomSheet.selfSizing(
            title: side.title,
            showBackButton: .constant(false)
        ) {
            rows
                // No trailing `Spacer` and no `maxHeight`: `selfSizing`
                // measures intrinsic height, which a greedy child would blow
                // up to whatever the sheet was offered.
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
    }

    private var rows: some View {
        VStack(spacing: 8) {
            switch options {
            case .standalone:
                switch side {
                case .source:
                    ForEach(sourceOptions, id: \.self) { source in
                        sourceRow(source)
                    }
                case .destination:
                    ForEach(destinationOptions, id: \.self) { destination in
                        destinationRow(destination)
                    }
                }

            case let .balances(networks, selected, select):
                ForEach(networks, id: \.self) { network in
                    row(
                        display: display(network: network),
                        selected: network == selected,
                        action: { select(network) })
                }
            }
        }
        .modifier(MenuViewModifier())
    }

    // MARK: - Options

    /// The three balances plus Identity. Picking one that collides with the
    /// To side moves THAT side — the view model keeps the endpoints distinct
    /// and coherent, so nothing is filtered out here.
    private var sourceOptions: [TransferSource] {
        ChainNetwork.allCases.map(TransferSource.balance) + [.identity]
    }

    /// The three balances plus Identity — which the payments landing card
    /// could reach but the screen itself could not, before this picker.
    ///
    /// With the identity as the source it narrows to Transparent and Platform:
    /// the two targets one state transition reaches. Shielded is absent
    /// because nothing moves credits from an identity into the Orchard pool,
    /// and Identity because it cannot fund itself.
    ///
    /// A wallet with no registered identity still lists Identity — the amount
    /// validation is where that gap is named, the same way the landing card
    /// offers it.
    private var destinationOptions: [TransferDestination] {
        if viewModel.isIdentitySource {
            return IdentityWithdrawalTarget.allCases.map { .balance($0.network) }
        }
        return ChainNetwork.allCases.map(TransferDestination.balance) + [.identity]
    }

    // MARK: - Rows

    private func sourceRow(_ source: TransferSource) -> some View {
        row(
            display: display(network: source.balanceNetwork),
            selected: viewModel.transferSource == source,
            action: { viewModel.selectStandaloneSource(source) })
    }

    private func destinationRow(_ destination: TransferDestination) -> some View {
        row(
            display: display(network: destination.balanceNetwork),
            selected: viewModel.destination == destination,
            action: { viewModel.selectStandaloneDestination(destination) })
    }

    /// The design system's `MenuItem`, with the blue tick as its trailing
    /// accessory.
    ///
    /// Name and mark only. No From / To caption — the sheet's own title
    /// already says which side is being chosen, and repeating it four times
    /// reads as noise. No radio circle either: the tick is the selection. And
    /// no balance, which the cards behind the sheet are already showing.
    private func row(
        display: TransferEndpointDisplay,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            onPicked()
        } label: {
            DashUIKit.MenuItem(
                leadingIcon: display.icon,
                title: display.title,
                accessory: .selection(isSelected: selected)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `nil` is the identity row — the one endpoint that is not a balance.
    private func display(network: ChainNetwork?) -> TransferEndpointDisplay {
        guard let network else { return .identity(in: viewModel) }
        return .network(network, in: viewModel)
    }
}

// MARK: - Endpoint → balance

private extension TransferSource {
    var balanceNetwork: ChainNetwork? {
        if case .balance(let network) = self { return network }
        return nil
    }
}

private extension TransferDestination {
    var balanceNetwork: ChainNetwork? {
        if case .balance(let network) = self { return network }
        return nil
    }
}

#if DEBUG

@MainActor
private func endpointPickerSample(
    _ side: TransferEndpointSide,
    viewModel: InternalTransferViewModel,
    options: TransferEndpointPicker.Options = .standalone
) -> some View {
    TransferEndpointPicker(viewModel: viewModel, side: side, options: options, onPicked: {})
}

/// Four rows: the three balances plus Identity, with the current source
/// selected.
@available(iOS 17, *)
#Preview("From") {
    endpointPickerSample(.source, viewModel: .makeForPreview())
}

@available(iOS 17, *)
#Preview("To") {
    endpointPickerSample(.destination, viewModel: .makeForPreview())
}

/// The narrowed To side: with the identity as the source only Transparent
/// and Platform remain, and the sheet sizes down to those two rows.
@available(iOS 17, *)
#Preview("To · from Identity") {
    endpointPickerSample(
        .destination,
        viewModel: .makeForPreview(target: .core, identitySource: true))
}

/// Every balance at zero still renders an amount, not an empty trailing slot.
@available(iOS 17, *)
#Preview("Empty balances") {
    endpointPickerSample(
        .source,
        viewModel: .makeForPreview(
            identityCredits: 0,
            coreDuffs: 0,
            platformCredits: 0,
            shieldedCredits: 0))
}

/// The pinned send sheet's To list: two balances, no identity row, and the
/// pinned From balance left out entirely.
@available(iOS 17, *)
#Preview("To · pinned send sheet") {
    endpointPickerSample(
        .destination,
        viewModel: .makeForPreview(source: .core, target: .shielded, sendFrom: .core),
        options: .balances([.platform, .shielded], selected: .shielded, select: { _ in }))
}

@available(iOS 17, *)
#Preview("Dark") {
    endpointPickerSample(.source, viewModel: .makeForPreview())
        .preferredColorScheme(.dark)
}

#endif
