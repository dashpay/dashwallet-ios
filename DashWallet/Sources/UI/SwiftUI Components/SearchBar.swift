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

struct SearchBar: View {

    private enum Layout {
        static let fieldHeight: CGFloat = 40
        static let fieldCornerRadius: CGFloat = 14
        static let fieldHorizontalPadding: CGFloat = 14
        static let fieldSpacing: CGFloat = 10
        static let cancelHorizontalPadding: CGFloat = 12
        static let cancelVerticalPadding: CGFloat = 6
        static let animationDuration: CGFloat = 0.25
    }

    @Binding var text: String
    @FocusState private var isFocused: Bool
    @State private var isEditing: Bool = false
    @State private var cancelButtonWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Layout.fieldSpacing) {
                magnifyingglass
                searchField
                clearButton
            }
            .padding(.horizontal, Layout.fieldHorizontalPadding)
            .frame(height: Layout.fieldHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.searchBg)
            .clipShape(.rect(cornerRadius: Layout.fieldCornerRadius))

            if isEditing {
                cancelButton
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: Layout.animationDuration), value: isEditing)
        .onAppear {
            isEditing = isFocused
        }
        .onChange(of: isFocused) { focused in
            withAnimation(.easeInOut(duration: Layout.animationDuration)) {
                isEditing = focused
            }
        }
    }

    @ViewBuilder
    private var clearButton: some View {
        if !text.isEmpty {
            Button(action: { text = "" }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Color.black1000Alpha30)
            }
        }
    }

    private var cancelButton: some View {
        Button(action: {
            text = ""
            withAnimation(.easeInOut(duration: Layout.animationDuration)) {
                isEditing = false
            }
            isFocused = false
        }) {
            Text(NSLocalizedString("Cancel", comment: ""))
                .padding(.horizontal, Layout.cancelHorizontalPadding)
                .padding(.vertical, Layout.cancelVerticalPadding)
        }
        .tint(.primaryText)
    }

    private var cancelButtonMeasurement: some View {
        cancelButton
            .fixedSize()
            .padding(.leading, Layout.fieldSpacing)
            .hidden()
            .captureSize { size in
                if abs(cancelButtonWidth - size.width) > 0.5 {
                    cancelButtonWidth = size.width
                }
            }
    }

    private var magnifyingglass: some View {
        Image(systemName: "magnifyingglass")
            .foregroundColor(Color.black1000Alpha50)
    }

    @ViewBuilder
    private var searchField: some View {
        if #available(iOS 17.0, *) {
            TextField(
                text: $text,
                prompt: Text(NSLocalizedString("Search", comment: "")).foregroundStyle(Color.black1000Alpha30)
            ) {
                EmptyView()
            }
            .focused($isFocused)
        } else {
            // Fallback on earlier versions
            TextField(NSLocalizedString("Search", comment: ""), text: $text)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .foregroundColor(.primaryText)
                .focused($isFocused)
        }
    }
}

private struct SearchBarSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private extension View {
    func captureSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: SearchBarSizePreferenceKey.self, value: geometry.size)
            }
        )
        .onPreferenceChange(SearchBarSizePreferenceKey.self, perform: onChange)
    }
}


#Preview {
    SearchBarPreview()
}

private struct SearchBarPreview: View {
    @State private var text = ""
    var body: some View {
        SearchBar(text: $text)
            .padding()
    }
}
