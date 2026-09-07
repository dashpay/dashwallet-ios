//
//  ApproveSheetPresentation.swift
//  DashWallet
//
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

/// Applies the approve-connection sheet's presentation options, degrading on
/// older systems. Keeping it in a modifier means the sheet content is written
/// once rather than repeated per availability branch.
struct ApproveSheetPresentation: ViewModifier {
    let isLoading: Bool

    private let detentHeight: CGFloat = 620
    private let cornerRadius: CGFloat = 32

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationDetents([.height(detentHeight)])
                .presentationCornerRadius(cornerRadius)
                .interactiveDismissDisabled(isLoading)
        } else if #available(iOS 16.0, *) {
            content
                .presentationDetents([.height(detentHeight)])
                .interactiveDismissDisabled(isLoading)
        } else {
            content
        }
    }
}

extension View {
    /// Presents this view as the approve-connection sheet body.
    func approveSheetPresentation(isLoading: Bool) -> some View {
        modifier(ApproveSheetPresentation(isLoading: isLoading))
    }
}
