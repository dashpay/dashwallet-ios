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
    let model: CNCreateAccountTxDetailsModel!
    
    @State var currentTag: String?
    
    var body: some View {
        List {
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

            Section() {
                ForEach(model.transactions, id: \.self) { tx in
                    ZStack {
                        NavigationLink(destination: TXDetailVCWrapper(tx: tx), tag: tx.txHashHexString, selection: self.$currentTag) {
                            SwiftUI.EmptyView()
                        }
                        .opacity(0)
                        
                        TransactionPreview(
                            title: tx.stateTitle,
                            subtitle: tx.shortDateString,
                            icon: .custom(tx.direction.iconName),
                            dashAmount: tx.formattedDashAmountWithDirectionalSymbol,
                            fiatAmount: tx.fiatAmount
                        ) {
                            self.currentTag = tx.txHashHexString
                        }
                    }
                }
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

struct TXDetailVCWrapper: UIViewControllerRepresentable {
    let tx: Transaction
    
    init(tx: Transaction) {
        self.tx = tx
    }
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let vc = TXDetailViewController(model: .init(transaction: tx))
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }
}
