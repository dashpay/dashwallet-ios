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

struct CreateInvitationButton: View {
    var action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image("icon_create_invitation")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 37, height: 37)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Create a new invitation", nil))
                        .font(.footnote)
                        .foregroundColor(.primaryText)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    
                    Text(NSLocalizedString("Invite your friends and family to join the Dash Network.", nil))
                        .font(.caption)
                        .foregroundColor(.tertiaryText)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color.secondaryBackground)
            .cornerRadius(8)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(NSLocalizedString("Create a new invitation", nil))
        .accessibilityHint(NSLocalizedString("Invite your friends and family to join the Dash Network.", nil))
    }
}

// Replicating the DWBasePressableControl behavior
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    VStack {
        CreateInvitationButton {
            print("Create invitation tapped")
        }
        .padding()
        
        Spacer()
    }
    .background(Color.primaryBackground)
} 