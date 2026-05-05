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
    @Environment(\.colorScheme) private var colorScheme

    var title: String = ""
    @Binding var showBackButton: Bool
    var onBackButtonPressed: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            grabber
            header

            contentSection
        }
        .background(Color.primaryBackground)
        .edgesIgnoringSafeArea(.bottom)
    }

    private var grabber: some View {
        Rectangle()
            .fill(Color(red: 0.83, green: 0.83, blue: 0.85))
            .frame(width: 36, height: 5)
            .cornerRadius(2.5)
            .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(alignment: .center) {
            backButtonSection
            Spacer()
            titleSection
            Spacer()
            closeButtonSection
        }
        .padding(.horizontal, 20)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var backButtonSection: some View {
        if showBackButton {
            Button {
                onBackButtonPressed?()
            } label: {
                Image(colorScheme == .dark ? "controls-back-dark-mode" : "controls-back")
                    .offset(x: -5, y: 5)
            }
            .frame(maxWidth: 50, maxHeight: .infinity)
        } else {
            ZStack { }
                .frame(maxWidth: 50)
        }
    }

    private var titleSection: some View {
        Text(title)
            .font(.calloutMedium)
            .foregroundColor(.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
    }

    private var closeButtonSection: some View {
        Button {
            presentationMode.wrappedValue.dismiss()
        } label: {
            Icon(name: .custom("toolbar-close", maxHeight: 14))
//                .foregroundColor(.primaryText)
//                .tint(Color(uiColor: UIColor(red: 0.14, green: 0.12, blue: 0.13, alpha: 1)))
                .tint(.primaryText)
        }
        .frame(width: 34, height: 34, alignment: .center)
        .overlay(
            RoundedRectangle(cornerRadius: 34)
                .stroke(Color.gray300Alpha30, lineWidth: 1.5)
        )
    }

    private var contentSection: some View {
        NavigationView {
            content()
                .navigationBarHidden(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primaryBackground)
        }
    }
}
