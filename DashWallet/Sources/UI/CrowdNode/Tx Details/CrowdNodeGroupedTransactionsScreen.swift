//  
//  Created by Andrei Ashikhmin
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

struct CrowdNodeGroupedTransactionsScreen: View {
    @State private var currentTag: String?
    
    let model: CNCreateAccountTxDetailsModel!
    @Binding var backNavigationRequested: Bool
    var onShowBackButton: (Bool) -> Void
    
    var body: some View {
        LazyVStack {
            Section() {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.title)
                        .font(.subheadline)
//                            .fontWeight(.medium)
                    
                    Text(model.dashAmountString)
                        .font(.largeTitle)
//                            .fontWeight(.medium)
                    
                    Text(model.fiatAmount)
                        .font(.caption)
                        .foregroundColor(.tertiaryText)
                }
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden)
                
            Section() {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("Why do I see all these transactions?", comment: "Crowdnode"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        
                    Text(NSLocalizedString("Your CrowdNode account was created using these transactions. ", comment: "Crowdnode"))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondaryBackground)
                .cornerRadius(10)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden)
            
//            ForEach(viewModel.txItems.keys.sorted(by: { key1, key2 in
//                key1.date > key2.date
//            }), id: \.self) { key in
//                Section(header: SectionHeader(key)
//                    .padding(.bottom, -24)
//                ) {
//                    VStack(spacing: 0) {
//                        ForEach(viewModel.txItems[key]!, id: \.id) { txItem in
//                            TransactionPreviewFrom(txItem: txItem)
//                                .padding(.horizontal, 5)
//                        }
//                    }
//                    .padding(.bottom, 4)
//                    .background(Color.secondaryBackground)
//                    .clipShape(RoundedShape(corners: [.bottomLeft, .bottomRight], radii: 10))
//                    .padding(15)
//                    .shadow(color: .shadow, radius: 10, x: 0, y: 5)
//                }

            Section() {
                                    VStack(spacing: 0) {
                                        ForEach(model.transactions, id: \.self) { txItem in
                                            ZStack {
                                                NavigationLink(
                                                    destination: TXDetailVCWrapper(
                                                                    tx: txItem,
                                                                    navigateBack: $backNavigationRequested,
                                                                    onDismissed: {
                                                                        onShowBackButton(false)
                                                                    }
                                                                 ).navigationBarHidden(true),
                                                    tag: txItem.txHashHexString,
                                                    selection: self.$currentTag
                                                ) {
                                                    SwiftUI.EmptyView()
                                                }
                                                .opacity(0)
                                                
                                                TransactionPreview(
                                                    title: txItem.stateTitle,
                                                    subtitle: txItem.shortDateString,
                                                    icon: .custom(txItem.direction.iconName),
                                                    dashAmount: txItem.direction == .sent ? -Int64(txItem.dashAmount) : Int64(txItem.dashAmount)
                                                ) {
                                                    self.currentTag = txItem.txHashHexString
                                                    onShowBackButton(true)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.bottom, 4)
                                    .background(Color.secondaryBackground)
                                    .clipShape(RoundedShape(corners: [.bottomLeft, .bottomRight], radii: 10))
                                    .padding(15)
                                    .shadow(color: .shadow, radius: 10, x: 0, y: 5)
                
                
            }
//            .frame(maxWidth: .infinity)
//            .background(Color.secondaryBackground)
//            .cornerRadius(10)
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
    }
}

