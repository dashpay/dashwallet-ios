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

struct TextInput: View {
    let label: String
    @Binding var text: String
    @State private var isFocused: Bool = false
    var isError: Bool = false
    var trailingIcon: Image?
    var trailingAction: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                Text(label)
                    .font(.body2)
                    .foregroundColor(.secondaryText)
                    .offset(y: labelOffset)
                    .scaleEffect(labelScale, anchor: .leading)
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isFocused || !text.isEmpty)
                
                TextField("", text: $text) { focused in
                    withAnimation {
                        isFocused = focused
                    }
                }
                .font(.body2)
                .padding(.top, 15)

                HStack {
                    Spacer()
                    Button(action: {
                        trailingAction?() ?? clearText()
                    }) {
                        trailingIcon ?? Image(systemName: "xmark.circle.fill")
                    }
//                    .opacity(text.isEmpty ? 0 : 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 58)
        .background(backgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .overlay(
            Group {
                if isFocused {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.dashBlue.opacity(0.1), lineWidth: 3)
                        .padding(-2)
                }
            }
        )
    }
    
    
    private var labelOffset: CGFloat {
        isFocused || !text.isEmpty ? -16 : 0
    }
    
    private var labelScale: CGFloat {
        isFocused || !text.isEmpty ? 0.8 : 1
    }
    
    private var backgroundColor: Color {
        if isError {
            return Color.systemRed.opacity(0.1)
        }
        
        if isFocused {
            return Color.clear
        }
        
        return Color.gray400.opacity(0.13)
    }
    
    private var borderColor: Color {
        if isError {
            return .systemRed
        }
        
        if isFocused {
            return .dashBlue
        }
        
        return Color.clear
    }
    
    private func clearText() {
        text = ""
    }
}


// Preview
struct TextInput_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            TextInput(label: "Username", text: .constant(""))
            TextInput(label: "Password", text: .constant("password"))
            TextInput(label: "Email", text: .constant("user@example.com"), isError: true)
        }
        .padding()
    }
}
