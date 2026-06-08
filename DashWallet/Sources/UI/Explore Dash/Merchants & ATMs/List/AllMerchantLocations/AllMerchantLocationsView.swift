//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

import CoreLocation
import SDWebImageSwiftUI
import SwiftUI

private enum Layout {
    static let contentSpacing: CGFloat = 20
    static let contentInsets: CGFloat = 20
    static let logoSize: CGFloat = 60
    static let listSpacing: CGFloat = 16
    static let topInset: CGFloat = 16
    static let bottomInset: CGFloat = 16
    static let scrollBottomInset: CGFloat = 40
}

struct AllMerchantLocationsView: View {
    @StateObject private var viewModel: AllMerchantLocationsViewModel

    var payWithDashHandler: (() -> Void)?
    var sellDashHandler: (() -> Void)?
    var onItemTapped: ((ExplorePointOfUse) -> Void)?
    var onItemsUpdated: (([ExplorePointOfUse]) -> Void)?

    init(pointOfUse: ExplorePointOfUse, searchRadius: Double = kDefaultRadius, searchCenterCoordinate: CLLocationCoordinate2D? = nil, currentFilters: PointOfUseListFilters? = nil) {
        _viewModel = StateObject(wrappedValue: AllMerchantLocationsViewModel(
            pointOfUse: pointOfUse,
            searchRadius: searchRadius,
            searchCenterCoordinate: searchCenterCoordinate,
            currentFilters: currentFilters
        ))
    }

    #if DEBUG
    init(currentItem: ExplorePointOfUse, previewItems: [ExplorePointOfUse] = [], isLoading: Bool = false) {
        _viewModel = StateObject(wrappedValue: AllMerchantLocationsViewModel(
            currentItem: currentItem,
            previewItems: previewItems,
            isLoading: isLoading
        ))
    }
    #endif

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Layout.contentSpacing) {
                MerchantHeaderView(pointOfUse: viewModel.currentItem)

                LocationsSection(
                    items: viewModel.items,
                    distanceTexts: viewModel.distanceTexts,
                    isLoading: viewModel.isLoading,
                    isLoadingNextPage: viewModel.isLoadingNextPage,
                    hasNextPage: viewModel.hasNextPage,
                    onItemTapped: { onItemTapped?($0) },
                    onLoadMore: { viewModel.loadMoreIfNeeded(currentItem: $0) }
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: Layout.scrollBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(20)
        .background(Color.secondaryBackground)
        .clipShape(.rect(cornerRadius: 20))
        .padding(.horizontal, Layout.contentInsets)
        .padding(.top, Layout.topInset)
        .padding(.bottom, Layout.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primaryBackground)
        .onAppear {
            viewModel.onItemsUpdated = onItemsUpdated
            onItemsUpdated?(viewModel.items)
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onItemsUpdated = nil
        }
    }
}

// MARK: - Header

private struct MerchantHeaderView: View {
    let pointOfUse: ExplorePointOfUse

    var body: some View {
        HStack(spacing: Layout.contentSpacing) {
            Group {
                if let logoUrl = pointOfUse.logoLocation, let url = URL(string: logoUrl) {
                    WebImage(url: url)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(pointOfUse.emptyLogoImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: Layout.logoSize, height: Layout.logoSize)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(pointOfUse.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primaryText)

                if let subtitle = pointOfUse.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondaryText)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Locations section

private struct LocationsSection: View {
    let items: [ExplorePointOfUse]
    let distanceTexts: [Int64: String]
    let isLoading: Bool
    let isLoadingNextPage: Bool
    let hasNextPage: Bool
    let onItemTapped: (ExplorePointOfUse) -> Void
    let onLoadMore: (ExplorePointOfUse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.listSpacing) {
            HStack(spacing: 8) {
                Text(NSLocalizedString("Select location", comment: "Explore Dash"))
                    .font(.footnoteMedium)
                    .foregroundStyle(Color.primaryText)

                if isLoading && !items.isEmpty {
                    SwiftUI.ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }

                Spacer()
            }

            if isLoading && items.isEmpty {
                loadingPlaceholder
            } else if items.isEmpty {
                emptyPlaceholder
            } else {
                LazyVStack(spacing: Layout.listSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onItemTapped(item)
                        } label: {
                            MerchantCellRow(
                                pointOfUse: item,
                                distanceText: distanceTexts[item.id]
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            guard hasNextPage else { return }
                            let triggerIndex = max(items.count - 5, 0)
                            guard index >= triggerIndex else { return }
                            onLoadMore(item)
                        }
                    }

                    if isLoadingNextPage {
                        footerLoader
                    }
                }
                .padding(.bottom, Layout.scrollBottomInset)
            }
        }

    }

    private var loadingPlaceholder: some View {
        HStack {
            Spacer()
            SwiftUI.ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.regular)
            Spacer()
        }
        .frame(minHeight: 120)
    }

    private var emptyPlaceholder: some View {
        HStack {
            Spacer()
            Text(NSLocalizedString("No locations found.", comment: "Explore Dash"))
                .font(.subhead)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(minHeight: 120)
    }

    private var footerLoader: some View {
        HStack {
            Spacer()
            SwiftUI.ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Loading") {
    NavigationView {
        AllMerchantLocationsView(
            currentItem: .previewMockMerchant(name: "Walmart"),
            previewItems: [],
            isLoading: true
        )
    }
}

#Preview("Empty") {
    NavigationView {
        AllMerchantLocationsView(
            currentItem: .previewMockMerchant(name: "Walmart"),
            previewItems: []
        )
    }
}

#Preview("With locations") {
    NavigationView {
        AllMerchantLocationsView(
            currentItem: .previewMockMerchant(name: "Walmart"),
            previewItems: [
                .previewMockMerchant(name: "Walmart", address1: "2800 E Camelback Rd", city: "Phoenix", territory: "AZ"),
                .previewMockMerchant(name: "Walmart", city: "Scottsdale", territory: "AZ"),
                .previewMockMerchant(name: "Walmart", city: "Tempe", territory: "AZ"),
            ]
        )
    }
}

#endif
