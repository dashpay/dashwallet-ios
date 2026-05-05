//  
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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
import SDWebImageSwiftUI

struct DashSpendPayIntro: View {
    let merchantIconUrl: String
    let merchantTitle: String
    let isMixing: Bool
    let dashBalance: UInt64

    @State private var balanceHidden: Bool = true

    private enum Layout {
        static let vStackSpacing: CGFloat = 0
        static let merchantHStackSpacing: CGFloat = 5
        static let balanceHStackSpacing: CGFloat = 4
        static let merchantIconSize: CGFloat = 18
        static let eyeCircleSize: CGFloat = 28
        static let eyeIconSize: CGFloat = 14
    }

    private var balanceLabel: String {
        (isMixing ? NSLocalizedString("Mixed balance", comment: "") : NSLocalizedString("Balance", comment: "")) + ":"
    }

    private var merchantIcon: some View {
        WebImage(url: URL(string: merchantIconUrl))
            .resizable()
            .indicator(.activity)
            .transition(.fade)
            .scaledToFit()
            .clipShape(Circle())
            .frame(width: Layout.merchantIconSize, height: Layout.merchantIconSize)
    }

    private var eyeIcon: some View {
        ZStack {
            Circle()
                .fill(Color.black1000Alpha5)
                .frame(width: Layout.eyeCircleSize, height: Layout.eyeCircleSize)

            Icon(name: .custom("eye_opened-icon", maxHeight: Layout.eyeIconSize))
                .foregroundColor(Color(red: 0, green: 0, blue: 0))
                .opacity(balanceHidden ? 1 : 0)

            Icon(name: .custom("eye_closed-icon", maxHeight: Layout.eyeIconSize))
                .foregroundColor(Color(red: 0, green: 0, blue: 0))
                .opacity(balanceHidden ? 0 : 1)
        }
        .compositingGroup()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.vStackSpacing) {
            Text(NSLocalizedString("Buy gift card", comment: "DashSpend"))
                .font(.title1)
                .fontWeight(.bold)

            HStack(alignment: .center, spacing: Layout.merchantHStackSpacing) {
                Text(NSLocalizedString("at", comment: "DashSpend"))
                merchantIcon
                Text(merchantTitle)
            }
            .font(.subhead)

            HStack(spacing: Layout.balanceHStackSpacing) {
                Text(balanceLabel)

                if balanceHidden {
                    Text("***********")
                } else {
                    DashAmount(amount: Int64(dashBalance), font: .subheadline, showDirection: false)
                    Text("~").font(.subheadline)
                    formattedFiatText(from: dashBalance)
                }

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { balanceHidden.toggle() } }) {
                    eyeIcon
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func formattedFiatText(from dashAmount: UInt64) -> some View {
        let text = try? CurrencyExchanger.shared.convertDash(amount: dashAmount.dashAmount, to: App.fiatCurrency).formattedFiatAmount

        Text(text ?? NSLocalizedString("Not available", comment: ""))
            .font(.subheadline)
            .foregroundColor(.secondaryText)
    }
}

#Preview("DashSpendPayIntro") {
    VStack(spacing: 20) {
        Text("DashSpendPayIntro").font(.caption).foregroundColor(.secondary)
        DashSpendPayIntro(
            merchantIconUrl: "",
            merchantTitle: "Amazon",
            isMixing: false,
            dashBalance: 555566
        )
        Divider()
        Text("SendIntro (reference)").font(.caption).foregroundColor(.secondary)
        SendIntro(
            title: "Buy gift card",
            preposition: "at",
            destination: "Amazon",
            dashBalance: nil,
            balanceLabel: "Balance:",
            avatarView: {
                Circle().fill(Color.orange).frame(width: 18, height: 18)
            }
        )
    }
    .padding()
}
