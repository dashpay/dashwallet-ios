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
    @State private var showTerritories: Bool = false
    
    let onApplyFilters: (PointOfUseListFilters?) -> Void
    
    init(
        currentFilters: PointOfUseListFilters?,
        filterGroups: [PointOfUseListFiltersGroup],
        territoriesDataSource: TerritoryDataSource? = nil,
        sortOptions: [PointOfUseListFilters.SortBy] = [.name, .distance],
        onApplyFilters: @escaping (PointOfUseListFilters?) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: MerchantFiltersViewModel(
            filters: currentFilters,
            filterGroups: filterGroups,
            territoriesDataSource: territoriesDataSource,
            sortOptions: sortOptions
        ))
        self.onApplyFilters = onApplyFilters
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Sort By Section - Only show if there are multiple options
                    if viewModel.sortOptions.contains(.distance) || viewModel.ctxGiftCards || viewModel.piggyGiftCards {
                        FilterSection(title: NSLocalizedString("Sort by", comment: "Explore Dash/Merchants/Filters")) {
                            RadioButtonRow(
                                title: NSLocalizedString("Name", comment: "Explore Dash: Filters"),
                                isSelected: viewModel.sortByName
                            ) {
                                viewModel.toggleSortBy(.name)
                            }
                            
                            if viewModel.sortOptions.contains(.distance) {
                                RadioButtonRow(
                                    title: NSLocalizedString("Distance", comment: "Explore Dash: Filters"),
                                    isSelected: viewModel.sortByDistance
                                ) {
                                    viewModel.toggleSortBy(.distance)
                                }
                            }
                                
                            if viewModel.sortOptions.contains(.discount) {
                                RadioButtonRow(
                                    title: NSLocalizedString("Discount", comment: "Explore Dash: Filters"),
                                    isSelected: viewModel.sortByDiscount
                                ) {
                                    viewModel.toggleSortBy(.discount)
                                }
                            }
                        }
                    }
                    
                    if viewModel.showPaymentTypes {
                        // Payment Type Section
                        FilterSection(title: NSLocalizedString("Spending options", comment: "Explore Dash/Merchants/Filters")) {
                            RadioButtonRow(
                                title: NSLocalizedString("Dash", comment: "Explore Dash: Filters"),
                                icon: .custom("dashCurrency", maxHeight: 20),
                                isSelected: viewModel.payWithDash,
                                style: .checkbox
                            ) {
                                viewModel.togglePaymentMethod(.dash)
                            }
                            
                            RadioButtonRow(
                                title: NSLocalizedString("CTX gift cards", comment: "Explore Dash: Filters"),
                                icon: .custom("ctx.logo"),
                                isSelected: viewModel.ctxGiftCards,
                                style: .checkbox
                            ) {
                                viewModel.togglePaymentMethod(.ctx)
                            }
                            
                            RadioButtonRow(
                                title: NSLocalizedString("Piggy Cards gift cards", comment: "Explore Dash: Filters"),
                                icon: .custom("piggycards.logo.small"),
                                isSelected: viewModel.piggyGiftCards,
                                style: .checkbox
                            ) {
                                viewModel.togglePaymentMethod(.piggyCards)
                            }
                        }
                    }
                        
                    // Gift Card Types Section - Only show if Gift Card is selected
                    if viewModel.showGiftCardTypes && (viewModel.ctxGiftCards || viewModel.piggyGiftCards) {
                        FilterSection(title: NSLocalizedString("Gift card types", comment: "Explore Dash/Merchants/Filters")) {
                            RadioButtonRow(
                                title: NSLocalizedString("Flexible amounts", comment: "Explore Dash: Filters"),
                                isSelected: viewModel.denominationFlexible,
                                style: .checkbox
                            ) {
                                viewModel.toggleDenominationType(.flexible)
                            }
                                
                            RadioButtonRow(
                                title: NSLocalizedString("Fixed denominated amounts", comment: "Explore Dash: Filters"),
                                isSelected: viewModel.denominationFixed,
                                style: .checkbox
                            ) {
                                viewModel.toggleDenominationType(.fixed)
                            }
                        }
                    }
                        
                    // Location Section
                    if viewModel.showTerritory {
                        FilterSection(title: NSLocalizedString("Location", comment: "")) {
                            FilterDisclosureItem(
                                title: viewModel.selectedTerritory ?? NSLocalizedString("Current location", comment: "Explore Dash: Filters"),
                                action: {
                                    showTerritories = true
                                }
                            )
                        }
                    }
                    
                    // Radius Section
                    if viewModel.showRadius {
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
                .animation(.easeInOut(duration: 0.3), value: viewModel.ctxGiftCards)
                .animation(.easeInOut(duration: 0.3), value: viewModel.sortOptions)
            }
            
            NavigationLink(destination: TerritoryPickerView(
                selectedTerritory: viewModel.selectedTerritory,
                territoriesDataSource: viewModel.territoriesDataSource
            ) { territory in
                viewModel.selectedTerritory = territory
            }, isActive: $showTerritories) {
                EmptyView()
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
