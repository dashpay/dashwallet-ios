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
    @FocusState private var isFocused: Bool
    
    let label: String
    @Binding var text: String
    var isError: Bool = false
    var trailingIcon: Image?
    var trailingAction: (() -> Void)?
    var isMultiline: Bool = false
    var maxChars: Int? = nil
    
    @State private(set) var isOverCharLimit: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if isMultiline {
                    TextEditor(text: $text)
                        .focused($isFocused)
                        .autocorrectionDisabled(true)
                        .font(.body2)
                        .padding(.top, 20)
                        .modifier(ClearBackgroundModifier())
                        .onChange(of: text) { newValue in
                            if let max = maxChars {
                                isOverCharLimit = newValue.count > max
                            }
                        }
                } else {
                    TextField("", text: $text)
                        .focused($isFocused)
                        .autocorrectionDisabled(true)
                        .font(.body2)
                        .padding(.top, 15)
                        .onChange(of: text) { newValue in
                            if let max = maxChars {
                                isOverCharLimit = newValue.count > max
                            }
                        }
                }
                
                Text(label)
                    .font(.body2)
                    .foregroundColor(.secondaryText)
                    .offset(y: labelOffset)
                    .scaleEffect(labelScale, anchor: .leading)
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isFocused || !text.isEmpty)
                    .padding(.top, isMultiline ? 18 : 6)
                    .padding(.leading, isMultiline ? 4 : 0)

                HStack {
                    Spacer()
                    Button(action: {
                        trailingAction?() ?? clearText()
                    }) {
                        (trailingIcon ?? Image(systemName: "xmark.circle.fill"))
                            .foregroundColor(.tertiaryText)
                    }
                    .opacity(text.isEmpty ? 0 : 1)
                }.padding(.top, isMultiline ? 20 : 15)
            }
            
            if let max = maxChars {
                HStack {
                    Spacer()
                    Text("\(text.count)/\(max) " + NSLocalizedString("characters", comment: "TextInput"))
                        .font(.caption)
                        .foregroundColor(isOverCharLimit ? .systemRed : .tertiaryText)
                }
                .padding(.vertical, 8)
                .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: maxChars != nil ? 78 : 60)
        .background(backgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .overlay(
            Group {
                if isFocused && !isError && !isOverCharLimit {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.dashBlue.opacity(0.1), lineWidth: 3)
                        .padding(-2)
                }
            }
        )
        .onTapGesture {
            isFocused = true
        }
    }
    
    
    private var labelOffset: CGFloat {
        isFocused || !text.isEmpty ? -16 : 0
    }
    
    private var labelScale: CGFloat {
        isFocused || !text.isEmpty ? 0.85 : 1
    }
    
    private var backgroundColor: Color {
        if isError || isOverCharLimit {
            return Color.systemRed.opacity(0.1)
        }
        
        if isFocused {
            return Color.clear
        }
        
        return Color.gray400.opacity(0.13)
    }
    
    private var borderColor: Color {
        if isError || isOverCharLimit {
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

struct ClearBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TextInput(label: "Username", text: .constant(""))
        TextInput(label: "Password", text: .constant("password"))
        TextInput(label: "Email", text: .constant("user@example.com"), isError: true)
        TextInput(label: "Bio", text: .constant("This is a multiline bio."), isMultiline: true, maxChars: 25)
    }
    .padding()
}
