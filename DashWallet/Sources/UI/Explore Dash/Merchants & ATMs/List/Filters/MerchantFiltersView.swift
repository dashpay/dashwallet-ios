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

import SwiftUI

struct MerchantFiltersView: View {
    @StateObject private var viewModel: MerchantFiltersViewModel
    @Environment(\.presentationMode) private var presentationMode
    
    let onApplyFilters: (PointOfUseListFilters?) -> Void
    
    init(
        currentFilters: PointOfUseListFilters?,
        showLocationSettings: Bool = false,
        showRadius: Bool = false,
        showTerritory: Bool = false,
        territoriesDataSource: TerritoryDataSource? = nil,
        showSortByDistance: Bool = true,
        onApplyFilters: @escaping (PointOfUseListFilters?) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: MerchantFiltersViewModel(
            filters: currentFilters,
            showLocationSettings: showLocationSettings,
            showRadius: showRadius,
            showTerritory: showTerritory,
            territoriesDataSource: territoriesDataSource,
            showSortByDistance: showSortByDistance
        ))
        self.onApplyFilters = onApplyFilters
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Sort By Section
                    FilterSection(title: NSLocalizedString("Sort by", comment: "Explore Dash/Merchants/Filters")) {
                        RadioButtonRow(
                            title: NSLocalizedString("Name", comment: "Explore Dash: Filters"),
                            isSelected: viewModel.sortByName
                        ) {
                            viewModel.toggleSortBy(.name)
                        }
                        
                        if viewModel.showSortByDistance {
                            RadioButtonRow(
                                title: NSLocalizedString("Distance", comment: "Explore Dash: Filters"),
                                isSelected: viewModel.sortByDistance
                            ) {
                                viewModel.toggleSortBy(.distance)
                            }
                        }
                            
                        RadioButtonRow(
                            title: NSLocalizedString("Discount", comment: "Explore Dash: Filters"),
                            isSelected: viewModel.sortByDiscount
                        ) {
                            viewModel.toggleSortBy(.discount)
                        }
                    }
                        
                    // Payment Type Section
                    FilterSection(title: NSLocalizedString("Payment Type", comment: "Explore Dash/Merchants/Filters")) {
                        RadioButtonRow(
                            title: NSLocalizedString("Dash", comment: "Explore Dash: Filters"),
                            icon: .custom("image.explore.dash.wts.payment.dash"),
                            isSelected: viewModel.payWithDash,
                            style: .checkbox
                        ) {
                            viewModel.payWithDash.toggle()
                        }
                            
                        RadioButtonRow(
                            title: NSLocalizedString("Gift Card", comment: "Explore Dash: Filters"),
                            icon: .custom("image.explore.dash.wts.payment.gift-card"),
                            isSelected: viewModel.useGiftCard,
                            style: .checkbox
                        ) {
                            viewModel.useGiftCard.toggle()
                        }
                    }
                        
                    // Gift Card Types Section
                    FilterSection(title: NSLocalizedString("Gift card types", comment: "Explore Dash/Merchants/Filters")) {
                        RadioButtonRow(
                            title: NSLocalizedString("Flexible amounts", comment: "Explore Dash: Filters"),
                            isSelected: viewModel.denominationFlexible,
                            style: .checkbox
                        ) {
                            viewModel.denominationFlexible.toggle()
                        }
                            
                        RadioButtonRow(
                            title: NSLocalizedString("Fixed amounts", comment: "Explore Dash: Filters"),
                            isSelected: viewModel.denominationFixed,
                            style: .checkbox
                        ) {
                            viewModel.denominationFixed.toggle()
                        }
                    }
                        
                    // Location Section
                    if viewModel.showTerritory {
                        FilterSection(title: NSLocalizedString("Location", comment: "")) {
                            NavigationLink(destination: TerritoryPickerView(
                                selectedTerritory: viewModel.selectedTerritory,
                                territoriesDataSource: viewModel.territoriesDataSource
                            ) { territory in
                                viewModel.selectedTerritory = territory
                            }) {
                                FilterDisclosureItem(
                                    title: viewModel.selectedTerritory ?? NSLocalizedString("Current location", comment: "Explore Dash: Filters")
                                )
                            }
                        }
                    }
                        
                    // Radius Section
                    if viewModel.showRadius && DWLocationManager.shared.isAuthorized {
                        FilterSection(title: NSLocalizedString("Radius", comment: "Explore Dash/Merchants/Filters")) {
                            ForEach(viewModel.availableRadiusOptions) { option in
                                RadioButtonRow(
                                    title: option.displayText,
                                    isSelected: viewModel.selectedRadius == option
                                ) {
                                    viewModel.toggleRadius(option)
                                }
                            }
                        }
                    }
                        
                    // Location Service Settings
                    if viewModel.showLocationSettings && !DWLocationManager.shared.isAuthorized {
                        FilterSection(title: NSLocalizedString("Current Location Settings", comment: "Explore Dash/Merchants/Filters")) {
                            FilterDisclosureItem(
                                title: DWLocationManager.shared.localizedStatus
                            ) {
                                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(settingsUrl)
                                }
                            }
                        }
                    }
                        
                    // Reset Filters
                    FilterSection(title: nil) {
                        Button(action: {
                            viewModel.resetFilters()
                        }) {
                            Text(NSLocalizedString("Reset Filters", comment: "Explore Dash"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(viewModel.canReset ? .red : Color.tertiaryText)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .disabled(!viewModel.canReset)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color.primaryBackground)
        .navigationBarTitle(NSLocalizedString("Filters", comment: "Explore Dash"), displayMode: .inline)
        .navigationBarItems(
            leading: Button(NSLocalizedString("Close", comment: "")) {
                presentationMode.wrappedValue.dismiss()
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.dashBlue),
            trailing: Button(NSLocalizedString("Apply", comment: "")) {
                let filters = viewModel.buildFilters()
                onApplyFilters(filters)
                presentationMode.wrappedValue.dismiss()
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(viewModel.canApply ? .dashBlue : Color.tertiaryText)
            .disabled(!viewModel.canApply)
        )
    }
}

// MARK: - Supporting Views

private struct FilterSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = title {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondaryText)
                    .padding(.leading, 15)
                    .padding(.vertical, 12)
            }
            
            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 6)
            .background(Color.secondaryBackground)
            .clipShape(RoundedShape(corners: .allCorners, radii: 12))
            .padding(.bottom, 20)
        }
    }
}


private struct FilterDisclosureItem: View {
    let title: String
    let action: (() -> Void)?
    
    init(title: String, action: (() -> Void)? = nil) {
        self.title = title
        self.action = action
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.body2)
                .fontWeight(.medium)
                .foregroundColor(.primaryText)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .imageScale(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            action?()
        }
    }
}
