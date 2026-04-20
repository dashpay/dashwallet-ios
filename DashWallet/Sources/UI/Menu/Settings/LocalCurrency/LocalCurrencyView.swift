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

import SwiftUI

// MARK: - LocalCurrencyView

struct LocalCurrencyView: View {
    @StateObject private var viewModel: LocalCurrencyViewModel

    @State private var scrollViewOffcet: CGFloat = 0
    @State private var fullHeaderSize: CGSize = .zero

    var onSelect: (String) -> Void
    var onBack: (() -> Void)?

    init(
        currencyCode: String? = nil,
        onSelect: @escaping (String) -> Void,
        onBack: (() -> Void)? = nil
    ) {
        self._viewModel = StateObject(wrappedValue: LocalCurrencyViewModel(currencyCode: currencyCode))
        self.onSelect = onSelect
        self.onBack = onBack
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
                onBack: onBack,
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
        Color.primaryBackground
    }
}

private struct LocalCurrencyScrollContentView: View {

    let headerHeight: CGFloat
    let onScrollChanged: (CGPoint) -> Void
    var filteredItems: [CurrencyItem]
    var selectedCurrencyCode: String
    var searchQuery: String
    var select: (String) -> Void
    var onSelect: (String) -> Void

    var body: some View {
        ScrollViewWithOnScrollChanged(.vertical, showsIndicators: false) {
            VStack {
                Rectangle()
                    .opacity(0)
                    .frame(height: headerHeight)

                // Currency list
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
                .padding(filteredItems.count > 0 ? 6 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.secondaryBackground)
                )
            }
        } onScrollChanged: { offset in
            onScrollChanged(offset)
        }
    }
}

private struct LocalCurrencyTopOverlayView: View {
    let scrollOffset: CGFloat
    var onBack: (() -> Void)?
    @Binding var searchQuery: String

    var body: some View {
        VStack {
            header

            if scrollOffset > -20 {
                SearchBar(text: $searchQuery)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 6)
        .background(toolbarBackground)
        .animation(.smooth, value: scrollOffset)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            ZStack {
                if let onBack {
                    NavBarBack(onBack: onBack)
                }

                // Title
                Text(NSLocalizedString("Local Currency", comment: "Settings"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primaryText)
            }
        }
    }

    @ViewBuilder
    private var toolbarBackground: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.clear)
                .background(Color.primaryBackground)
                .ignoresSafeArea()

            Divider()
                .background(Color(red: 176/255, green: 182/255, blue: 188/255, opacity: 0.15))
                .opacity(scrollOffset < -20 ? 1 : 0)
        }

    }
}

// MARK: - Preview

#if DEBUG
extension LocalCurrencyView {
    fileprivate init(
        viewModel: LocalCurrencyViewModel,
        onSelect: @escaping (String) -> Void,
        onBack: (() -> Void)? = nil
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onSelect = onSelect
        self.onBack = onBack
    }
}

extension LocalCurrencyViewModel {
    convenience init(items: [CurrencyItem], selectedCode: String) {
        self.init(allItems: items, selectedCurrencyCode: selectedCode)
    }
}

#Preview {
    LocalCurrencyView(
        viewModel: LocalCurrencyViewModel(
            items: [
                CurrencyItem(code: "USD", name: "US Dollar",            flagName: "united states",    priceString: "42.50"),
                CurrencyItem(code: "EUR", name: "Euro",                  flagName: "european union",   priceString: "39.20"),
                CurrencyItem(code: "GBP", name: "British Pound",         flagName: "united kingdom",   priceString: "33.80"),
                CurrencyItem(code: "JPY", name: "Japanese Yen",          flagName: "japan",            priceString: "6380.00"),
                CurrencyItem(code: "UAH", name: "Ukrainian Hryvnia",     flagName: "ukraine",          priceString: "1750.00"),
                CurrencyItem(code: "PLN", name: "Polish Zloty",          flagName: "poland",           priceString: "168.00"),
                CurrencyItem(code: "CHF", name: "Swiss Franc",           flagName: "switzerland",      priceString: "37.10"),
                
            ],
            selectedCode: "USD"
        ),
        onSelect: { _ in },
        onBack: {}
    )
}
#endif
