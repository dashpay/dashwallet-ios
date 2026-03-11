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

struct FeatureTopText: View {
    var title: String
    var text: String?
    var label: String? = nil
    var alignment: TextAlignment = .center
    var labelIcon: IconName? = nil
    var linkAction: (() -> Void)? = nil
    var shakeLabel: Bool = false
    
    var body: some View {
        VStack(alignment: getStackAlignment(), spacing: 6) {
            Text(title)
                .font(.title1)
                .multilineTextAlignment(alignment)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .foregroundColor(.primaryText)
          
            if let text = text {
                Text(text)
                    .font(.subhead)
                    .multilineTextAlignment(alignment)
                    .lineSpacing(3)
                    .foregroundColor(.secondaryText)
            }
            
            if let label = label {
                DashButton(text: label, trailingIcon: labelIcon, style: .plain, size: .small, stretch: false) {
                    linkAction?()
                }
                .padding(.top, 8)
                .overrideForegroundColor(.dashBlue)
                .wiggle(shakeLabel)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .frame(maxWidth: .infinity)
    }
    
    func getStackAlignment() -> HorizontalAlignment {
        switch self.alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}

extension View {
    func wiggle(_ trigger: Bool) -> some View {
        modifier(WiggleModifier(trigger: trigger))
    }
}

struct WiggleModifier: ViewModifier {
    let trigger: Bool
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .offset(x: isAnimating ? -20 : 0)
            .onChange(of: trigger) { newValue in
                guard newValue else { return }
                withAnimation(.easeInOut(duration: 0.05).repeatCount(3)) {
                    isAnimating = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isAnimating = false
                }
            }
    }
}


#Preview {
    FeatureTopText(
        title: "Simplify your crypto taxes",
        text: "Connect your crypto wallets to the ZenLedger platform. Learn more and get started with your Dash Wallet transactions.",
        label: "zenledger.io",
        labelIcon: .custom("external.link")
    )
}
