//
//  MayaCoinIconLoader.swift
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

import UIKit

/// Loads remote coin icons with a two-level cache: memory (`NSCache`) + disk (`URLCache`).
///
/// The remote source is the SwapKit token-list CDN, keyed by `chain.symbol` (the identifier
/// truncated at the first `-`). For example `ARB.GLD-0X…` → `arb.gld.png`, and
/// `BTC.BTC` → `btc.btc.png`. Disk-cached entries survive app restarts and are served
/// without re-downloading until the OS purges the cache.
///
/// This actor is responsible only for remote loading and caching.
/// The `convert.crypto` placeholder is shown by `SwapCoinIconView` while loading or on failure.
actor MayaCoinIconLoader {
    static let shared = MayaCoinIconLoader()

    private static let swapKitCDNBaseURL = "https://storage.googleapis.com/token-list-swapkit/images/"

    private let memoryCache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        let diskCache = URLCache(
            memoryCapacity: 0,
            diskCapacity: 100 * 1024 * 1024,
            diskPath: "maya_coin_icons"
        )
        let config = URLSessionConfiguration.default
        config.urlCache = diskCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)

        memoryCache.countLimit = 200
    }

    /// Returns the icon for a SwapKit/Maya asset identifier, or `nil` if unavailable.
    /// The CDN key is derived by truncating the identifier at the first `-`, so contract-suffixed
    /// tokens like `ARB.GLD-0X…` correctly resolve to `arb.gld.png`.
    /// Memory cache is checked first; on miss the image is downloaded and cached.
    func loadSwapKitIcon(for identifier: String) async -> UIImage? {
        let cdnKey = identifier.split(separator: "-", maxSplits: 1).first.map(String.init) ?? identifier
        let cdnKeyLowercased = cdnKey.lowercased()
        guard let url = URL(string: Self.swapKitCDNBaseURL + "\(cdnKeyLowercased).png") else {
            return nil
        }
        return await loadIcon(cacheKey: "swapkit:\(cdnKeyLowercased)", from: url)
    }

    private func loadIcon(cacheKey: String, from url: URL) async -> UIImage? {
        let key = cacheKey as NSString

        if let cached = memoryCache.object(forKey: key) {
            DSLogger.log("🧭 DashDEX icon TEMP: cache hit [\(cacheKey)] \(url.absoluteString)")
            return cached
        }

        do {
            DSLogger.log("🧭 DashDEX icon TEMP: GET \(url.absoluteString)")
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200,
                  let image = UIImage(data: data) else {
                DSLogger.log("🧭 DashDEX icon TEMP: MISS status=\(status) bytes=\(data.count) \(url.absoluteString)")
                return nil
            }
            DSLogger.log("🧭 DashDEX icon TEMP: OK status=200 bytes=\(data.count) \(url.absoluteString)")
            memoryCache.setObject(image, forKey: key)
            return image
        } catch {
            DSLogger.log("🧭 DashDEX icon TEMP: ERROR \(error.localizedDescription) \(url.absoluteString)")
            return nil
        }
    }
}
