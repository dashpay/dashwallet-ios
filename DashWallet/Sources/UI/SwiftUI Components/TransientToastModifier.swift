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

import DashUIKit
import SwiftUI

extension View {
    /// Overlays a `DashUIKit.Toast` at the bottom while `isPresented`, then
    /// clears the flag after `duration`.
    ///
    /// The sibling `dexOfflineToast` shows a toast for as long as a condition
    /// holds; this one is for a moment that has already passed — a copy, a
    /// save — where nothing will turn the flag off but time.
    ///
    /// Re-triggering while a toast is on screen restarts the countdown rather
    /// than stacking, because the timer is keyed on `isPresented`.
    func transientToast(
        isPresented: Binding<Bool>,
        style: ToastStyle,
        message: String,
        duration: TimeInterval = 2
    ) -> some View {
        modifier(TransientToastModifier(
            isPresented: isPresented,
            style: style,
            message: message,
            duration: duration))
    }
}

private struct TransientToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let style: ToastStyle
    let message: String
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    // No `onDismiss`: it draws a close button, and the
                    // `Spacer` beside that button makes the toast greedy —
                    // it would stretch edge to edge instead of hugging the
                    // message. Nothing here needs dismissing by hand anyway.
                    DashUIKit.Toast(style: style, message: message)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isPresented)
            .task(id: isPresented) {
                guard isPresented else { return }
                try? await Task.sleep(for: .seconds(duration))
                // Cancelled when the flag flips or the view goes away, so a
                // re-trigger restarts the countdown instead of being cut
                // short by the previous one.
                guard !Task.isCancelled else { return }
                isPresented = false
            }
    }
}

#if DEBUG

private struct TransientToastPreview: View {
    @State private var copied = false

    var body: some View {
        VStack {
            Spacer()
            // Qualified: the app has a `DashButton` of its own, with a
            // different Style enum.
            DashUIKit.DashButton(
                text: "Copy",
                size: .medium,
                style: .tintedGray,
                action: { copied = true })
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dash.primaryBackground)
        .transientToast(
            isPresented: $copied,
            style: .copied,
            message: NSLocalizedString("Copied", comment: ""))
    }
}

@available(iOS 17, *)
#Preview("Tap to show") {
    TransientToastPreview()
}

#endif
