//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import Combine

struct PrivateNoteScreen: View {
    @Environment(\.presentationMode) private var presentationMode
    @FocusState private var isTextFieldFocused: Bool
    @StateObject private var viewModel = PrivateNoteViewModel()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text(NSLocalizedString("Private Note", comment: "Private Note"))
                    .font(.h5Bold)
                    .foregroundColor(.primaryText)
                
                TextInput(
                    label: NSLocalizedString("Note", comment: "Private Note"),
                    text: $viewModel.input,
                    isMultiline: true
//                    maxChars: 25
                ).focused($isTextFieldFocused)
                .frame(maxHeight: 100)
                .padding(.top, 20)
                    
                if viewModel.showError {
                    Text(viewModel.errorMessage)
                        .font(.footnote)
                        .foregroundColor(.systemRed)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
                
                Spacer()
                
                DashButton(
                    text: NSLocalizedString("Continue", comment: "Continue"),
                    isEnabled: viewModel.canContinue()
                ) {
                    viewModel.onContinue()
                }
                .padding(.bottom, 20)
            }.padding(.horizontal, 20)
        }
        .background(Color.secondaryBackground)
        .onAppear {
//            isTextFieldFocused = true
        }
    }
}
