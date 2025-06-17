//
//  Created by Claude Code
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
import UIKit

typealias Territory = String

struct TerritoryPickerView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var territories: [Territory] = []
    @State private var isLoading = true
    @State private var searchText = ""
    
    let selectedTerritory: Territory?
    let territoriesDataSource: TerritoryDataSource?
    let onTerritorySelected: (Territory?) -> Void
    
    private var filteredTerritories: [Territory] {
        if searchText.isEmpty {
            return territories
        }
        return territories.filter { territory in
            territory.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField(NSLocalizedString("Search territories", comment: ""), text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray400.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                if isLoading {
                    Spacer()
                    SwiftUI.ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                // Current Location Option
                                RadioButtonRow(
                                    title: NSLocalizedString("Current location", comment: "Explore Dash: Filters"),
                                    icon: .system("location.circle"),
                                    isSelected: selectedTerritory == nil
                                ) {
                                    onTerritorySelected(nil)
                                    presentationMode.wrappedValue.dismiss()
                                }
                                .background(Color.secondaryBackground)
                                .clipShape(RoundedShape(corners: .allCorners, radii: 12))
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                                .id("current_location")
                                
                                // Territory Options
                                VStack(spacing: 0) {
                                    ForEach(filteredTerritories, id: \.self) { territory in
                                        RadioButtonRow(
                                            title: territory,
                                            isSelected: selectedTerritory == territory
                                        ) {
                                            onTerritorySelected(territory)
                                            presentationMode.wrappedValue.dismiss()
                                        }
                                        .id(territory)
                                    }
                                }
                                .background(Color.secondaryBackground)
                                .clipShape(RoundedShape(corners: .allCorners, radii: 12))
                                .padding(.horizontal, 20)
                            }
                        }
                        .onAppear {
                            // Scroll to selected item after a small delay to ensure the view is loaded
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    if let selected = selectedTerritory {
                                        proxy.scrollTo(selected, anchor: .center)
                                    } else {
                                        proxy.scrollTo("current_location", anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                }
        }
        .background(Color.primaryBackground)
        .navigationTitle(NSLocalizedString("Location", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primaryText)
                }
            }
        }
        .onAppear {
            loadTerritories()
        }
    }
    
    private func loadTerritories() {
        guard let dataSource = territoriesDataSource else {
            isLoading = false
            return
        }
        
        dataSource { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let territories):
                    self.territories = territories.sorted()
                case .failure:
                    self.territories = []
                }
            }
        }
    }
}

