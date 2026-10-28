//
//  Created by Roman Chornyi
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

// MARK: - LocalCurrencyView

struct LocalCurrencyView: View {
    /// The bar's leading control: back when pushed (Settings), close when
    /// presented modally (amount screens, the Home shortcut). `nil` inside a
    /// `BottomSheet`, which draws its own chrome: only the title is shown.
    enum LeadingAction {
        case back(() -> Void)
        case close(() -> Void)
    }

    @StateObject private var viewModel: LocalCurrencyViewModel

    @State private var scrollViewOffcet: CGFloat = 0
    @State private var fullHeaderSize: CGSize = .zero

    var onSelect: (String) -> Void
    var leadingAction: LeadingAction?

    init(
        currencyCode: String? = nil,
        changesAppCurrency: Bool = true,
        leadingAction: LeadingAction? = nil,
        onSelect: @escaping (String) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: LocalCurrencyViewModel(
            currencyCode: currencyCode,
            changesAppCurrency: changesAppCurrency))
        self.onSelect = onSelect
        self.leadingAction = leadingAction
    }

    var body: some View {
        ZStack(alignment: .top) {
            background

            LocalCurrencyScrollContentView(
                headerHeight: fullHeaderSize.height,
                onScrollChanged: { offset in
                    scrollViewOffcet = min(offset.y, 0)
                },
                filteredItems: viewModel.filteredItems,
                selectedCurrencyCode: viewModel.selectedCurrencyCode,
                searchQuery: viewModel.searchQuery,
                select: viewModel.select(currencyCode:),
                onSelect: onSelect
            )
            .padding(.horizontal, 20)

            LocalCurrencyTopOverlayView(
                scrollOffset: scrollViewOffcet,
                leadingAction: leadingAction,
                searchQuery: $viewModel.searchQuery
            )
            .readingFrame { frame in
                if fullHeaderSize == .zero {
                    fullHeaderSize = frame.size
                }
            }
        }
    }

    private var background: some View {
        Color.dash.primaryBackground
    }
}

// MARK: - Modal presentation

/// `LocalCurrencyView` presented modally (the amount screens, the Home
/// shortcut): a close circle, and picking a currency hands it to `onSelect`
/// and dismisses.
final class LocalCurrencyModalController: UIHostingController<LocalCurrencyView> {
    init(currencyCode: String?, changesAppCurrency: Bool, onSelect: @escaping (String) -> Void) {
        super.init(rootView: LocalCurrencyView(leadingAction: .close {}, onSelect: { _ in }))
        rootView = LocalCurrencyView(
            currencyCode: currencyCode,
            changesAppCurrency: changesAppCurrency,
            leadingAction: .close { [weak self] in self?.dismiss(animated: true) },
            onSelect: { [weak self] code in
                onSelect(code)
                self?.dismiss(animated: true)
            })
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct LocalCurrencyScrollContentView: View {
    private enum Layout {
        static let containerCornerRadius: CGFloat = 20
        static let noResultsMinHeight: CGFloat = 150
    }

    let headerHeight: CGFloat
    let onScrollChanged: (CGPoint) -> Void
    var filteredItems: [CurrencyItem]
    var selectedCurrencyCode: String
    var searchQuery: String
    var select: (String) -> Void
    var onSelect: (String) -> Void

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowNoResults: Bool {
        filteredItems.isEmpty && !trimmedSearchQuery.isEmpty
    }

    private var noResultsText: String {
        String.localizedStringWithFormat(
            NSLocalizedString("No matches for \"%@\"", comment: "Local Currency: no search matches"),
            trimmedSearchQuery
        )
    }

    @ViewBuilder private var noResultsView: some View {
        VStack {
            Text(noResultsText)
                .font(.footnote)
                .foregroundColor(Color.dash.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: Layout.noResultsMinHeight, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: Layout.containerCornerRadius)
                .fill(Color.dash.secondaryBackground)
        )
    }

    @ViewBuilder private var currencyContent: some View {
        if shouldShowNoResults {
            noResultsView
        } else {
            LazyVStack(spacing: 2) {
                ForEach(filteredItems) { item in
                    LocalCurrencyCellView(
                        item: item,
                        isSelected: item.code == selectedCurrencyCode,
                        searchQuery: searchQuery
                    )
                    .onTapGesture {
                        select(item.code)
                        onSelect(item.code)
                    }
                }
            }
            .padding(filteredItems.isEmpty ? 0 : 6)
            .background(
                RoundedRectangle(cornerRadius: Layout.containerCornerRadius)
                    .fill(Color.dash.secondaryBackground)
            )
        }
    }

    var body: some View {
        ScrollViewWithOnScrollChanged(.vertical, showsIndicators: false) {
            VStack {
                Rectangle()
                    .opacity(0)
                    .frame(height: headerHeight)

                // Currency list
                currencyContent
            }
        } onScrollChanged: { offset in
            onScrollChanged(offset)
        }
    }
}

private struct LocalCurrencyTopOverlayView: View {
    let scrollOffset: CGFloat
    let leadingAction: LocalCurrencyView.LeadingAction?
    @Binding var searchQuery: String

    var body: some View {
        VStack {
            header

            if scrollOffset > -20 {
                DashUIKit.SearchBar(text: $searchQuery)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 6)
        .background(toolbarBackground)
        .animation(.easeInOut(duration: 0.2), value: scrollOffset)
    }

    @ViewBuilder
    private var header: some View {
        switch leadingAction {
        case .back(let action):
            DashUIKit.NavigationBar(
                leading: { DashUIKit.NavigationBarElement.back.button(action: action) },
                central: { title })
        case .close(let action):
            DashUIKit.NavigationBar(
                leading: { DashUIKit.NavigationBarElement.close.button(action: action) },
                central: { title })
        case nil:
            title
        }
    }

    private var title: some View {
        Text(NSLocalizedString("Local Currency", comment: "Settings"))
            .dashFont(.subheadMedium)
            .foregroundColor(.dash.primaryText)
    }

    @ViewBuilder private var toolbarBackground: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.clear)
                .background(Color.dash.primaryBackground)
                .ignoresSafeArea()

            Divider()
                .background(Color.dash.gray400Alpha13)
                .opacity(scrollOffset < -20 ? 1 : 0)
        }
    }
}

// MARK: - Preview

#if DEBUG
fileprivate extension LocalCurrencyView {
    init(
        viewModel: LocalCurrencyViewModel,
        leadingAction: LeadingAction?,
        onSelect: @escaping (String) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onSelect = onSelect
        self.leadingAction = leadingAction
    }
}

fileprivate extension LocalCurrencyViewModel {
    convenience init(items: [CurrencyItem], selectedCode: String) {
        self.init(allItems: items, selectedCurrencyCode: selectedCode)
    }
}

#Preview {
    LocalCurrencyView(
        viewModel: LocalCurrencyViewModel(
            items: [
                CurrencyItem(
                    code: "USD",
                    name: "US Dollar",
                    flagName: "united states",
                    priceString: "42.50"
                ),
                CurrencyItem(
                    code: "EUR",
                    name: "Euro",
                    flagName: "european union",
                    priceString: "39.20"
                ),
                CurrencyItem(
                    code: "GBP",
                    name: "British Pound",
                    flagName: "united kingdom",
                    priceString: "33.80"
                ),
                CurrencyItem(
                    code: "JPY",
                    name: "Japanese Yen",
                    flagName: "japan",
                    priceString: "6380.00"
                ),
                CurrencyItem(
                    code: "UAH",
                    name: "Ukrainian Hryvnia",
                    flagName: "ukraine",
                    priceString: "1750.00"
                ),
                CurrencyItem(
                    code: "PLN",
                    name: "Polish Zloty",
                    flagName: "poland",
                    priceString: "168.00"
                ),
                CurrencyItem(
                    code: "CHF",
                    name: "Swiss Franc",
                    flagName: "switzerland",
                    priceString: "37.10"
                )
            ],
            selectedCode: "USD"
        ),
        leadingAction: .back {},
        onSelect: { _ in }
    )
}
#endif
