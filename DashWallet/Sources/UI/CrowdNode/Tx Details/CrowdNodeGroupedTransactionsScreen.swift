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
        ScrollView {
            LazyVStack(spacing: 0) {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.title)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            DashAmount(amount: model.netAmount, font: .largeTitle, dashSymbolFactor: 0.7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(model.fiatAmount)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.caption)
                                .foregroundColor(.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Spacer()
                        
                        Icon(name: .custom(model.iconName))
                            .padding(10)
                            .frame(width: 50, height: 50)
                            .background(Color.secondaryBackground)
                            .clipShape(.circle)
                    }
                    .padding(.horizontal, 25)
                    .padding(.bottom, 5)
                }
                    
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("Why do I see all these transactions?", comment: "Crowdnode"))
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                        Text(NSLocalizedString("Your CrowdNode account was created using these transactions. ", comment: "Crowdnode"))
                            .font(.subheadline)
                            .foregroundColor(Color.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondaryBackground)
                    .cornerRadius(10)
                    .padding()
                }
                
    
                Section {
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
                                }.opacity(0)
                                                    
                                TransactionPreview(
                                    title: txItem.stateTitle,
                                    subtitle: txItem.shortDateString,
                                    icon: .custom(txItem.direction.iconName),
                                    dashAmount: txItem.signedDashAmount,
                                    overrideFiatAmount: txItem.fiatAmount
                                ) {
                                    self.currentTag = txItem.txHashHexString
                                    onShowBackButton(true)
                                }
                            }
                        }
                    }
                    .padding(5)
                    .background(Color.secondaryBackground)
                    .cornerRadius(10)
                    .padding(.horizontal, 15)
                    .shadow(color: .shadow, radius: 10, x: 0, y: 5)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.primaryBackground)
    }
}

