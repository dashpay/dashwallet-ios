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

struct JoinDashPayView: View {
    var onAction: (() -> ())?

    var body: some View {
        Button(action: {
            onAction?()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Join DashPay", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(Color.primaryText)
                    
                    Text(NSLocalizedString("Create a username, add your friends.", comment: ""))
                        .font(.footnote)
                        .foregroundColor(Color.tertiaryText)
                }
                
                Spacer()
                
                Image("pay_user_accessory")
                    .frame(width: 32, height: 32)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(Color.secondaryBackground)
            .cornerRadius(10)
            .shadow(color: .shadow, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 16)
    }
}
