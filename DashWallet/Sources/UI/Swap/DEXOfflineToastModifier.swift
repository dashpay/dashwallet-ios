//
//  DEXOfflineToastModifier.swift
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

import DashUIKit
import SwiftUI

extension View {
    /// Overlays a persistent "No internet connection" toast at the bottom of a DEX screen.
    /// The toast is non-dismissable and visible whenever `isOnline` is `false`.
    func dexOfflineToast(isOnline: Bool) -> some View {
        modifier(DEXOfflineToastModifier(isOnline: isOnline))
    }
}

private struct DEXOfflineToastModifier: ViewModifier {
    let isOnline: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if !isOnline {
                    DashUIKit.Toast(
                        style: .noInternet,
                        message: NSLocalizedString("No internet connection", comment: "No connection")
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isOnline)
    }
}
