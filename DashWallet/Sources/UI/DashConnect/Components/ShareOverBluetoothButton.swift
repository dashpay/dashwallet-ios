//
//  ShareOverBluetoothButton.swift
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

/// The secondary call to action next to "Scan QR": sign a browser in over
/// Bluetooth instead of showing it a QR code.
struct ShareOverBluetoothButton: View {
    var size: DashUIKit.DashButtonSize = .large
    let action: () -> Void

    var body: some View {
        DashUIKit.DashButton(
            text: NSLocalizedString("Sign in on a browser", comment: "DashConnect: Bluetooth login"),
            size: size,
            style: .tintedBlue,
            action: action
        )
    }
}

#Preview {
    ShareOverBluetoothButton(action: {})
        .padding()
        .background(Color.primaryBackground)
}
