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

import DashUIKit
import SwiftUI

/// SCR-05 Select source. Draws the ViewModel's rows; the pick and the close are the flow's callbacks.
struct SelectSourceSheet: View {
    @ObservedObject var viewModel: SelectSourceViewModel

    var onClose: () -> Void

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            title: NSLocalizedString("Select source", comment: "External send"),
            showBackButton: .constant(false),
            onClose: onClose,
            content: { sheetContent })
    }

    /// The flow loads the rows once, after the sheet is up; until then it shows its loading state.
    @ViewBuilder private var sheetContent: some View {
        if viewModel.isLoading && viewModel.rows.isEmpty {
            HStack {
                Spacer()
                SwiftUI.ProgressView()
                    .accessibilityLabel(NSLocalizedString("Loading", comment: "External send"))
                Spacer()
            }
            .padding(.vertical, 48)
        } else {
            rowsList
        }
    }

    private var rowsList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.rows) { row in
                DashUIKit.RadioButtonRow(
                    title: row.title,
                    subtitle: row.reasonText ?? row.balanceFiatText,
                    trailingText: row.balanceText,
                    icon: row.source.icon,
                    isSelected: row.isSelected,
                    action: { viewModel.select(row.source) })
                    .disabled(!row.isSelectable)
                    .opacity(row.isSelectable ? 1 : 0.5)
            }
        }
        .modifier(DashUIKit.MenuViewModifier())
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

extension SendSource {
    /// The icon the app's balance rows use for this source.
    var icon: DashUIKit.DashIconSource {
        switch self {
        case .core: return DashIcon.Menu.dashLogoSquare.source
        case .shielded: return DashIcon.Features.shield.source
        case .platform: return DashIcon.Features.platform.source
        case .identity: return DashIcon.Features.identity.source
        }
    }
}

#if DEBUG

private struct PreviewBalances: ExternalSendBalanceReading {
    func spendableBalance(of source: SendSource) async -> UInt64? { nil }
}

@MainActor
private func previewSheet(_ rows: [SelectSourceViewModel.Row], selected: SendSource = .core,
                          loading: Bool = false) -> some View {
    let destination = Destination(type: .coreAddress, text: "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN")
    let vm = SelectSourceViewModel(destination: destination,
                                   selected: selected, balances: PreviewBalances())
    vm.setPreviewRows(rows, loading: loading)
    return PreviewHost(viewModel: vm)
}

/// The sheet over a backdrop; its rows are fixed, nothing loads them.
private struct PreviewHost: View {
    @ObservedObject var viewModel: SelectSourceViewModel

    var body: some View {
        Color.dash.primaryBackground.ignoresSafeArea()
            .sheet(isPresented: .constant(true)) { SelectSourceSheet(viewModel: viewModel, onClose: {}) }
    }
}

private func previewRow(_ source: SendSource, _ title: String, _ duffs: UInt64?,
                        reason: UnavailableReason? = nil) -> SelectSourceViewModel.Row {
    SelectSourceViewModel.Row(source: source, title: title, balanceDuffs: duffs,
                              balanceFiatText: duffs.map { "$\($0 / 2_000_000).00" }, unavailableReason: reason,
                              isSelected: false)
}

private let allAvailable = [
    previewRow(.core, "Core", 300_000_000), previewRow(.shielded, "Shielded", 200_000_000),
    previewRow(.platform, "Platform", 100_000_000), previewRow(.identity, "Identity", 50_000_000)
]

#Preview("Loading") { previewSheet([], loading: true) }

#Preview("All available") { previewSheet(allAvailable) }

#Preview("One selected") { previewSheet(allAvailable, selected: .platform) }

#Preview("Unavailable with reasons") {
    previewSheet([
        previewRow(.core, "Core", 300_000_000, reason: .coreToOtherIdentity),
        previewRow(.shielded, "Shielded", 200_000_000), previewRow(.platform, "Platform", 100_000_000),
        previewRow(.identity, "Identity", 50_000_000, reason: .notSupportedYet)
    ], selected: .shielded)
}

#Preview("Zero balances") {
    previewSheet([
        previewRow(.core, "Core", 0), previewRow(.shielded, "Shielded", 0),
        previewRow(.platform, "Platform", 0), previewRow(.identity, "Identity", 0)
    ])
}

#Preview("Unreadable balance") {
    previewSheet([
        previewRow(.core, "Core", 300_000_000), previewRow(.shielded, "Shielded", nil),
        previewRow(.platform, "Platform", 100_000_000)
    ])
}

#Preview("No identity row") { previewSheet(Array(allAvailable.prefix(3))) }

#Preview("Long text, large Dynamic Type") {
    previewSheet([
        previewRow(.core, "Core", 123_456_789_012_345, reason: .coreToScriptFormPlatformAddress),
        previewRow(.shielded, "Shielded", 200_000_000), previewRow(.platform, "Platform", 100_000_000),
        previewRow(.identity, "Identity", 50_000_000, reason: .paymentRequestCoreOnly)
    ], selected: .shielded)
        .dynamicTypeSize(.accessibility3)
}

#endif
