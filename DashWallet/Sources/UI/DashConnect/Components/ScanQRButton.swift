//
//  ScanQRButton.swift
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

/// The single "Scan QR" call to action, so the button reads the same wherever
/// it appears and the debug shortcut lives in one place.
///
/// In debug builds a long press feeds a mock payload, which lets the connect
/// flow be exercised without a second device showing a real login QR.
struct ScanQRButton: View {
    var size: DashUIKit.DashButtonSize = .large
    let onScanQR: () -> Void
    let onMockScan: () -> Void

    var body: some View {
        DashUIKit.DashButton(
            text: NSLocalizedString("Scan QR", comment: "DashConnect"),
            size: size,
            style: .filledBlue,
            action: onScanQR
        )
        #if DEBUG
        .onLongPressGesture(perform: onMockScan)
        #endif
    }
}

#Preview {
    VStack(spacing: 20) {
        ScanQRButton(onScanQR: {}, onMockScan: {})
        ScanQRButton(size: .small, onScanQR: {}, onMockScan: {})
    }
    .padding()
    .background(Color.primaryBackground)
}
