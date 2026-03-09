//
//  EnterAddressViewModel.swift
//  DashWallet
//
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

import Foundation
import SwiftUI
import UIKit

@MainActor
class EnterAddressViewModel: ObservableObject {
    let coin: MayaCryptoCurrency

    @Published var addressText: String = ""
    @Published var errorMessage: String?
    @Published var hasClipboardContent: Bool = false
    @Published var revealedClipboardContent: String?

    var placeholderText: String {
        String(format: NSLocalizedString("%@ address", comment: "Maya"), coin.code)
    }

    var isAddressValid: Bool {
        !addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isClipboardRevealed: Bool {
        revealedClipboardContent != nil
    }

    init(coin: MayaCryptoCurrency) {
        self.coin = coin
    }

    func checkClipboard() {
        hasClipboardContent = UIPasteboard.general.hasStrings
    }

    func revealClipboard() {
        // Read clipboard content (triggers iOS paste permission banner on first access),
        // then set the published property so the view re-renders with content ready.
        // Animate the transition to prevent flash during system banner dismissal.
        let content = UIPasteboard.general.string
        withAnimation(.easeInOut(duration: 0.2)) {
            revealedClipboardContent = content
        }
    }

    func pasteFromClipboard() {
        guard let content = revealedClipboardContent else { return }
        addressText = content
        errorMessage = nil
    }

    func setAddress(_ address: String) {
        addressText = address
        errorMessage = nil
    }
}
