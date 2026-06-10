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

struct HaltedToast: View {
    
    @Binding var showHaltedToast: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {

                ZStack {
                    Color.black.opacity(0.001)
                        .frame(width: 24, height: 24)

                    ExclamationIcon(
                        size: CGSize(width: 18, height: 17),
                        fillColor: .systemYellow,
                        strokeColor: .systemYellow,
                        symbolColor: .primaryText
                    )
                }


                Text(NSLocalizedString("Some coins are not available because of the halted chain", comment: "Maya"))
                    .font(.subhead)
                    .foregroundColor(.white)
                    .padding(.vertical, 2)
                
                Spacer(minLength: 0)
            }
            
            Button {
                showHaltedToast = false
            } label: {
                XmarkIcon(size: 9, color: Color(red: 1, green: 1, blue: 1), lineWidth: 1.5)
                    .padding(8)
                    .background(Color.whiteAlpha10, in: .circle)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.black1000Alpha90)
        .clipShape(.rect(cornerRadius: 20))
        .contentShape(.rect)
    }
}

#Preview {
    HaltedToast(showHaltedToast: .constant(false))
        .padding(20)
}
