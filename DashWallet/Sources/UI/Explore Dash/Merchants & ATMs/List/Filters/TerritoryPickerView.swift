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
        NavigationView {
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
                .background(Color.secondaryBackground)
                .cornerRadius(10)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                if isLoading {
                    Spacer()
                    SwiftUI.ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                } else {
                    List {
                        // Current Location Option
                        TerritoryRowView(
                            title: NSLocalizedString("Current location", comment: "Explore Dash: Filters"),
                            isSelected: selectedTerritory == nil
                        ) {
                            onTerritorySelected(nil)
                            presentationMode.wrappedValue.dismiss()
                        }
                        
                        // Territory Options
                        ForEach(filteredTerritories, id: \.self) { territory in
                            TerritoryRowView(
                                title: territory,
                                isSelected: selectedTerritory == territory
                            ) {
                                onTerritorySelected(territory)
                                presentationMode.wrappedValue.dismiss()
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle(NSLocalizedString("Location", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Back", comment: "")) {
                        presentationMode.wrappedValue.dismiss()
                    }
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

private struct TerritoryRowView: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primaryText)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.dashBlue)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .background(Color.secondaryBackground)
    }
}
