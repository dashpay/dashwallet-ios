//
//  SwapKitConstants.swift
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

enum SwapKitConstants {
    static let dashAsset = "DASH.DASH"
    /// Default max slippage (percent) for quotes/swaps — mirrors Android
    /// `SwapKitConstants.DEFAULT_SLIPPAGE_PERCENT = 2`.
    static let defaultSlippagePercent = 2
    /// SwapKit provider IDs (mirrors Android SwapKitConstants.kt).
    ///
    /// MAYACHAIN and MAYACHAIN_STREAMING are **separate** SwapKit providers, not aliases:
    /// streaming performs the swap over time for better price execution. Their `/tokens`
    /// lists differ (31 vs 18 assets on 2026-08-03), so both are needed — classifying from
    /// the streaming list alone hides Maya-routable assets such as `KUJI.KUJI` and `XRD.XRD`.
    /// Quotes request both and let SwapKit's routing pick.
    static let providerMayaChain = "MAYACHAIN"
    static let providerMayaStreaming = "MAYACHAIN_STREAMING"
    static let mayaProviders = [providerMayaChain, providerMayaStreaming]
    static let providerNear = "NEAR"
    /// routeId is valid 60s, cached ~5min (see SWAPKIT_PROTOCOL.md "Quote Lifecycle").
    static let routeFreshnessSeconds: TimeInterval = 60

    // Read from SwapKit-Info.plist — mirrors how Coinbase+Constants.swift reads Coinbase-Info.plist.
    // Drop SwapKit-Info.plist locally (git-ignored) and add it to dashwallet/dashpay targets in Xcode.
    static let apiKey: String = {
        if let path = Bundle.main.path(forResource: "SwapKit-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            return dict["API_KEY"] as? String ?? ""
        }
        return ""
    }()

    static var isConfigured: Bool { !apiKey.isEmpty }
}
