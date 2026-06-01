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
import MapKit
import SDWebImageSwiftUI
import SwiftUI

private enum Layout {
    static let cardSpacing: CGFloat = 20
    static let cardCornerRadius: CGFloat = 20
    static let cardInsets: CGFloat = 20
    static let logoSize: CGFloat = 60
    static let listSpacing: CGFloat = 16
    static let topInset: CGFloat = 32
    static let bottomInset: CGFloat = 32
}

struct AllMerchantLocationsView: View {
    @StateObject private var viewModel: AllMerchantLocationsViewModel

    var payWithDashHandler: (() -> Void)?
    var sellDashHandler: (() -> Void)?
    var onItemTapped: ((ExplorePointOfUse) -> Void)?

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
        VStack(spacing: 0) {
            MerchantLocationsMapView(items: viewModel.items)
                .frame(height: kDefaultOpenedMapPosition)

            ScrollView(.vertical, showsIndicators: false) {
                Card {
                    VStack(alignment: .leading, spacing: Layout.cardSpacing) {
                        MerchantHeaderView(pointOfUse: viewModel.currentItem)

                        LocationsSection(
                            items: viewModel.items,
                            distanceTexts: viewModel.distanceTexts,
                            isLoading: viewModel.isLoading,
                            onItemTapped: { onItemTapped?($0) }
                        )
                    }
                }
                .padding(.horizontal, Layout.cardInsets)
                .padding(.top, Layout.topInset)
                .padding(.bottom, Layout.bottomInset)
            }
            .background(Color.primaryBackground)
        }
        .onAppear { viewModel.onAppear() }
        .navigationTitle(NSLocalizedString("Where to Spend", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Map representable

private struct MerchantLocationsMapView: UIViewRepresentable {
    let items: [ExplorePointOfUse]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let newKeys = Set(items.compactMap { item -> String? in
            guard let coord = validCoordinate(for: item) else { return nil }
            return "\(item.id)|\(coord.latitude)|\(coord.longitude)"
        })

        guard newKeys != context.coordinator.lastKeys else { return }
        context.coordinator.lastKeys = newKeys

        let existing = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(existing)

        let annotations: [MKPointAnnotation] = items.compactMap { item in
            guard let coord = validCoordinate(for: item) else { return nil }
            let annotation = MKPointAnnotation()
            annotation.coordinate = coord
            annotation.title = item.name
            return annotation
        }

        guard !annotations.isEmpty else { return }
        mapView.addAnnotations(annotations)

        if !context.coordinator.didInitialZoom {
            context.coordinator.didInitialZoom = true
            mapView.showAnnotations(annotations, animated: false)
        }
    }

    private func validCoordinate(for item: ExplorePointOfUse) -> CLLocationCoordinate2D? {
        guard let lat = item.latitude, let lon = item.longitude else { return nil }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CLLocationCoordinate2DIsValid(coord) ? coord : nil
    }

    final class Coordinator {
        var lastKeys: Set<String> = []
        var didInitialZoom = false
    }
}

// MARK: - Header

private struct MerchantHeaderView: View {
    let pointOfUse: ExplorePointOfUse

    var body: some View {
        HStack(spacing: Layout.cardSpacing) {
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
    let onItemTapped: (ExplorePointOfUse) -> Void

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
                    ForEach(items, id: \.id) { item in
                        Button {
                            onItemTapped(item)
                        } label: {
                            MerchantCellRow(
                                pointOfUse: item,
                                distanceText: distanceTexts[item.id]
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
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
}

// MARK: - Card container

private struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(Layout.cardInsets)
            .background(Color.secondaryBackground)
            .clipShape(.rect(cornerRadius: Layout.cardCornerRadius))
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
