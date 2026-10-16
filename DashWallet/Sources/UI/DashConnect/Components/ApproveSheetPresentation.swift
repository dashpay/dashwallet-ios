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

/// Applies the approval sheets' presentation options — detent, corner radius
/// and no system drag indicator (`DashUIKit.BottomSheet` draws its own
/// grabber) — degrading on older systems. Keeping it in a modifier means the
/// sheet content is written once rather than repeated per availability branch.
/// Swipe-to-dismiss is gated by the sheet's `BottomSheet`, not here.
struct ApproveSheetPresentation: ViewModifier {
    private let detentHeight: CGFloat = 620
    private let cornerRadius: CGFloat = 32

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationDetents([.height(detentHeight)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(cornerRadius)
        } else if #available(iOS 16.0, *) {
            content
                .presentationDetents([.height(detentHeight)])
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }
}

extension View {
    /// Presents this view as a DashConnect approval sheet body.
    func approveSheetPresentation() -> some View {
        modifier(ApproveSheetPresentation())
    }
}
