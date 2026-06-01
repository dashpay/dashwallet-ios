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

    var title: String = ""
    @Binding var showBackButton: Bool
    var onBackButtonPressed: (() -> Void)? = nil
    /// When true (default), the content is wrapped in a greedy NavigationView +
    /// `.frame(maxHeight: .infinity)` so it fills the full sheet height.
    /// Set to false for self-sizing sheets (`.selfSizingSheet()`) — the content
    /// is measured at its natural height and the sheet snaps to fit.
    var fillsHeight: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
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

                VStack {
                    Rectangle()
                        .fill(Color(red: 0.83, green: 0.83, blue: 0.85))
                        .frame(width: 36, height: 5)
                        .cornerRadius(2.50)

                    Text(title)
                        .font(.calloutMedium)
                        .foregroundColor(.primaryText)
                        .padding(.top, 10)
                }
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
            .background(Color.primaryBackground)

            if fillsHeight {
                // Original greedy layout: NavigationView forces full-height expansion.
                // Required by existing callers (HomeView, DashPay dialogs, etc.).
                NavigationView {
                    content()
                        .navigationBarHidden(true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.primaryBackground)
                }
            } else {
                // Non-greedy: content is measured at its natural height.
                // Used with .selfSizingSheet() so the sheet hugs its content.
                // NavigationView is not needed — none of the self-sizing callers
                // require in-sheet navigation.
                content()
                    .frame(maxWidth: .infinity)
                    .background(Color.primaryBackground)
            }
        }
        // Only extend into the bottom safe area for the greedy (fill) layout.
        // For self-sizing sheets, ignoring the bottom safe area double-counts the
        // home-indicator inset (presentationDetents([.height]) already accounts for
        // it), which inflates the measured height and leaves a grey gap.
        .modifier(ConditionalBottomSafeArea(ignore: fillsHeight))
    }
}

private struct ConditionalBottomSafeArea: ViewModifier {
    let ignore: Bool

    func body(content: Content) -> some View {
        if ignore {
            content.edgesIgnoringSafeArea(.bottom)
        } else {
            content
        }
    }
}
