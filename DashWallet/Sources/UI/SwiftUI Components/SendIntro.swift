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

struct SendIntro: View {
    var title: String
    var destination: String? = nil
    var dashBalance: Int64? = nil
    var balanceLabel: String? = nil
    @State var balanceHidden: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if let destination = destination {
                HStack(spacing: 2) {
                    Text(NSLocalizedString("to", comment: "Send Screen: to address"))
                    Text(destination)
                        .font(.subheadline)
                        .padding(.leading, 4)
                }
                .padding(.top, 4)
                .padding(.bottom, 2)
            }
            
            if let dashBalance = dashBalance {
                HStack(spacing: 4) {
                    if let balanceLabel = balanceLabel {
                        Text(balanceLabel).font(.subheadline)
                    } else {
                        Text(NSLocalizedString("Balance", comment: "Send Screen: to address") + ":").font(.subheadline)
                    }

                    if balanceHidden {
                        Text("***********").font(.subheadline)
                    } else {
                        DashAmount(amount: dashBalance, font: .subheadline, showDirection: false)
                        Text("~").font(.subheadline)
                        FormattedFiatText(from: dashBalance)
                    }
                    
                    Button(action: {
                        balanceHidden.toggle()
                    }) {
                        Image(systemName: balanceHidden ? "eye.slash.fill" : "eye.fill")
                            .resizable()
                            .scaledToFit()
                            .imageScale(.medium)
                            .frame(width: 17, height: 17)
                            .frame(width: 28, height: 28)
                            .foregroundColor(.gray500)
                            .background(Color.primaryText.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .frame(width: 36, height: 36)
                }
                .foregroundColor(.secondaryText)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func FormattedFiatText(from dashAmount: Int64) -> some View {
        let text = (try? CurrencyExchanger.shared.convertDash(amount: abs(dashAmount.dashAmount), to: App.fiatCurrency).formattedFiatAmount) ?? NSLocalizedString("Not available", comment: "")
            
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondaryText)
    }
}
