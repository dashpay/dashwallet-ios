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

struct SwapPortalScaffold: View {
    let logoAssetName: String
    let title: String
    let description: String
    var onBack: () -> Void
    var onConvertDash: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            NavigationBar(leading: {
                NavigationBarElement.back.button { onBack() }
            })

            ScrollView {
                VStack(spacing: 20) {
                    introSection
                    actionsCard
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.primaryBackground.ignoresSafeArea())
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            logoContainer
            descriptionBlock
        }
        .padding(20)
        .background(Color.secondaryBackground)
        .clipShape(.rect(cornerRadius: 20))
        .shadow(color: .shadow, radius: 10, x: 0, y: 5)
    }

    private var actionsCard: some View {
        MenuItem(
            title: NSLocalizedString("Convert Dash", comment: "Swap portal"),
            subtitle: NSLocalizedString("From Dash Wallet to any crypto", comment: "Swap portal"),
            icon: .custom("convert.crypto"),
            action: { onConvertDash?() }
        )
        .modifier(SwapMenuCardStyle())
    }

    private var logoContainer: some View {
        Icon(name: .custom(logoAssetName, maxHeight: 60))
            .frame(width: 60, height: 60)
    }

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2)
                .foregroundColor(.primaryText)

            Text(description)
                .font(.footnote)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
