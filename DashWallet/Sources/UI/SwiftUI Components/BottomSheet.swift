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

struct BottomSheet<Content: View>: View {
    @Environment(\.presentationMode) private var presentationMode
    
    @Binding var showBackButton: Bool
    var onBackButtonPressed: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                if showBackButton {
                    Button {
                        onBackButtonPressed?()
                    } label: {
                        Image("backarrow")
                            .offset(x: -5, y: 5)
                    }
                    .frame(maxWidth: 50, maxHeight: .infinity)
                } else {
                    ZStack { }.frame(maxWidth: 50)
                }
                
                Spacer()
                           
                Rectangle()
                    .fill(Color(red: 0.83, green: 0.83, blue: 0.85))
                    .frame(width: 36, height: 5)
                    .cornerRadius(2.50)
                    .padding(.top, 6)
                
                Spacer()
                           
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(Color.primaryText)
                        .imageScale(.large)
                        .font(Font.system(size: 14).weight(.semibold))
                }
                .frame(maxWidth: 50, maxHeight: .infinity)
            }
            .frame(height: 50)
            .padding(.horizontal, 10)
            
            NavigationView {
                content()
                    .navigationBarHidden(true)
            }
            .padding(.top, 4)
        }
    }
}
