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

/// SCR-05 Select source. Draws the ViewModel's rows and its Toast; the pick and the close are the flow's callbacks.
struct SelectSourceSheet: View {
    @ObservedObject var viewModel: SelectSourceViewModel

    var onClose: () -> Void

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            title: NSLocalizedString("Select source", comment: "External send"),
            showBackButton: .constant(false),
            onClose: onClose,
            content: { sheetContent })
            .transientToast(
                isPresented: Binding(get: { viewModel.toastMessage != nil },
                                     set: { if !$0 { viewModel.dismissToast() } }),
                style: .info,
                message: viewModel.toastMessage ?? "",
                duration: 3)
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
                if row.isSelectable {
                    DashUIKit.RadioButtonRow(
                        title: row.title,
                        icon: row.source.icon,
                        isSelected: row.isSelected,
                        action: { viewModel.tap(row.source) })
                } else {
                    UnavailableSourceRow(row: row, action: { viewModel.tap(row.source) })
                }
            }
        }
        .modifier(DashUIKit.MenuViewModifier())
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

/// A source that cannot pay this destination: its icon and name dimmed, an "i" where the radio would be. The whole
/// row takes the tap, which shows the reason; it never selects. Laid out like `DashUIKit.RadioButtonRow`.
private struct UnavailableSourceRow: View {
    let row: SelectSourceViewModel.Row
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                HStack(spacing: 16) {
                    Image(dash: row.source.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                    Text(row.title)
                        .dashFont(.subheadMedium)
                        .foregroundStyle(Color.dash.primaryText)
                }
                .opacity(0.5)

                Spacer()

                DashIcon.NavigationBar.info.image
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityLabel(NSLocalizedString("Not available", comment: "External send"))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
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

@MainActor
private func previewSheet(_ rows: [SelectSourceViewModel.Row], selected: SendSource = .core,
                          loading: Bool = false, toast: String? = nil) -> some View {
    let destination = Destination(type: .coreAddress, text: "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN")
    let vm = SelectSourceViewModel(destination: destination, selected: selected)
    vm.setPreviewRows(rows, loading: loading, toastMessage: toast)
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

private func previewRow(_ source: SendSource, _ title: String,
                        reason: UnavailableReason? = nil) -> SelectSourceViewModel.Row {
    SelectSourceViewModel.Row(source: source, title: title, unavailableReason: reason, isSelected: false)
}

private let allAvailable = [
    previewRow(.core, "Core"), previewRow(.shielded, "Shielded"),
    previewRow(.platform, "Platform"), previewRow(.identity, "Identity")
]

private let identityUnavailable = [
    previewRow(.core, "Core"), previewRow(.shielded, "Shielded"), previewRow(.platform, "Platform"),
    previewRow(.identity, "Identity", reason: .notSupportedYet)
]

#Preview("Loading") { previewSheet([], loading: true) }

#Preview("All selectable") { previewSheet(allAvailable) }

#Preview("One selected") { previewSheet(allAvailable, selected: .platform) }

#Preview("With an unavailable row") { previewSheet(identityUnavailable) }

#Preview("Toast shown") {
    previewSheet(identityUnavailable, toast: UnavailableReason.notSupportedYet.localizedMessage)
}

#Preview("Payment request: Core only") {
    previewSheet([
        previewRow(.core, "Core"), previewRow(.shielded, "Shielded", reason: .paymentRequestCoreOnly),
        previewRow(.platform, "Platform", reason: .paymentRequestCoreOnly),
        previewRow(.identity, "Identity", reason: .paymentRequestCoreOnly)
    ])
}

#Preview("No identity row") { previewSheet(Array(allAvailable.prefix(3))) }

#Preview("Long text, large Dynamic Type") {
    previewSheet([
        previewRow(.core, "Core", reason: .coreToScriptFormPlatformAddress),
        previewRow(.shielded, "Shielded"),
        previewRow(.platform, "Platform", reason: .platformToScriptFormPlatformAddress),
        previewRow(.identity, "Identity")
    ], selected: .shielded, toast: UnavailableReason.coreToScriptFormPlatformAddress.localizedMessage)
        .dynamicTypeSize(.accessibility3)
}

#endif
